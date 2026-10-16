"""Script to handle oauth redirects from Google"""

import json
import os
import html
import urllib.parse
import urllib.request
import urllib.error
import argparse
import signal
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs

import logging

# Private runtime dir (not world-readable /tmp): the log and the pid file of a running listener.
runtime_dir = os.environ.get("XDG_RUNTIME_DIR") or os.path.join(os.path.expanduser("~"), ".cache")
os.makedirs(runtime_dir, exist_ok=True)
log_path = os.path.join(runtime_dir, "eventcalendar-google-redirect.log")
pid_path = os.path.join(runtime_dir, "eventcalendar-google-redirect.pid")

logging.basicConfig(
    filename=log_path,
    level=logging.INFO,
    format='%(asctime)s %(levelname)s: %(message)s'
)
try:
    os.chmod(log_path, 0o600)
except OSError:
    pass

# The hosted helper page (redirect mode "hosted") posts the code back from this origin.
HELPER_ORIGIN = "https://alikestocode.github.io"
LISTEN_TIMEOUT = 5 * 60  # seconds: give up if the browser never comes back

client_id = client_secret = listen_port = redirect_uri = code_verifier = expected_state = None
exit_code = 0
asset_dir = os.path.join(os.path.dirname(__file__), "oauth_assets")
success_template_path = os.path.join(asset_dir, "success.html")
style_path = os.path.join(asset_dir, "style.css")


def masked_argv(argv):
    """argv for the log, without the client secret / PKCE verifier / state values."""
    secret_flags = {"--client_secret", "--code_verifier", "--state"}
    result = []
    hide_next = False
    for arg in argv:
        result.append("***" if hide_next else arg)
        hide_next = arg in secret_flags
    return result


def stop_previous_listener():
    """A listener left over from a cancelled sign-in still holds the port: stop it."""
    try:
        with open(pid_path, "r") as handle:
            pid = int(handle.read().strip())
    except (OSError, ValueError):
        return
    if pid == os.getpid():
        return
    try:
        with open("/proc/{}/cmdline".format(pid), "rb") as handle:
            if b"google_redirect.py" not in handle.read():
                return  # The pid was reused by something else
        os.kill(pid, signal.SIGTERM)
    except OSError:
        return
    for _ in range(20):  # Wait up to 2 s for the port to be released
        time.sleep(0.1)
        try:
            os.kill(pid, 0)
        except OSError:
            break
    logging.info("Stopped previous listener (pid %s)", pid)


def mask_value(value, keep_start=6, keep_end=4):
    if not value:
        return ""
    text = str(value)
    if len(text) <= keep_start + keep_end:
        return text
    return "{}...{} (len={})".format(text[:keep_start], text[-keep_end:], len(text))


def load_success_page():
    if not os.path.isfile(success_template_path):
        return ""
    try:
        with open(success_template_path, "r", encoding="utf-8") as handle:
            template = handle.read()
    except Exception:
        return ""
    if "{{STYLE}}" in template:
        css = ""
        if os.path.isfile(style_path):
            try:
                with open(style_path, "r", encoding="utf-8") as handle:
                    css = handle.read()
            except Exception:
                css = ""
        template = template.replace("{{STYLE}}", css)
    return template


def render_success_page(code, token_data):
    template = load_success_page()
    if not template:
        return ""
    safe_code = html.escape(code or "")
    token_json = ""
    if token_data is not None:
        token_json = json.dumps(token_data, sort_keys=True, indent=2)
    safe_token_json = html.escape(token_json)
    template = template.replace("{{CODE}}", safe_code)
    template = template.replace("{{TOKEN_JSON}}", safe_token_json)
    return template


def exchange_code_for_token(code):
    # Exchange code for token from https://oauth2.googleapis.com/token
    # using the following POST request:
    logging.info("Exchanging code for token (code=%s)", mask_value(code))
    token_params = {
        "code": code,
        "client_id": client_id,
        "redirect_uri": redirect_uri,
        "grant_type": "authorization_code",
    }
    if client_secret:
        token_params["client_secret"] = client_secret
    if code_verifier:
        token_params["code_verifier"] = code_verifier
    data = urllib.parse.urlencode(token_params).encode("utf-8")
    req = urllib.request.Request("https://oauth2.googleapis.com/token", data)
    response = urllib.request.urlopen(req)
    logging.info("Token endpoint response status: %s", getattr(response, "status", "unknown"))
    token_data = json.loads(response.read().decode("utf-8"))
    logging.info(
        "Token response keys: %s (has_refresh_token=%s)",
        list(token_data.keys()),
        "refresh_token" in token_data,
    )
    return token_data


class OAuthRedirectHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        return

    def _send_headers(self, status, content_type):
        self.send_response(status)
        self.send_header("Content-type", content_type)
        # Only the hosted helper page may post the code from a browser (no "*": any web page
        # could otherwise send its own code and sign the widget into another account).
        if self.headers.get("Origin") == HELPER_ORIGIN:
            self.send_header("Access-Control-Allow-Origin", HELPER_ORIGIN)
            self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
            self.send_header("Access-Control-Allow-Headers", "Content-Type")
            self.send_header("Access-Control-Allow-Private-Network", "true")
        self.end_headers()

    def _reject(self, reason):
        logging.warning("Rejected request: %s", reason)
        self._send_headers(403, "text/plain")
        self.wfile.write(b"Rejected.")

    def _shutdown(self):
        logging.info("Shutting down server.")
        threading.Thread(target=self.server.shutdown, daemon=True).start()

    def _set_exit_code(self, code):
        global exit_code
        exit_code = code

    def _extract_code(self, value):
        if not value:
            return ""
        text = value.strip()
        parsed = urlparse(text)
        if parsed.query:
            params = parse_qs(parsed.query)
            if "code" in params:
                return params["code"][0]
        if "code=" in text:
            params = parse_qs(text.split("?", 1)[-1])
            if "code" in params:
                return params["code"][0]
        return text

    def _handle_code(self, code, html_response):
        logging.info("Handling code (code=%s)", mask_value(code))
        if not code:
            self._send_headers(400, "text/plain")
            self.wfile.write(b"Missing code parameter in redirect.")
            return
        try:
            token_data = exchange_code_for_token(code)
        except urllib.error.HTTPError as e:
            err_body = e.read().decode("utf-8")
            logging.error("Token exchange HTTPError %s: %s", e.code, err_body)
            print(err_body)
            sys.stdout.flush()
            self._set_exit_code(1)
            self._send_headers(400, "text/plain")
            self.wfile.write(b"Handling redirect failed.")
            self._shutdown()
            return
        except urllib.error.URLError as e:
            logging.error("Token exchange URLError: %s", str(e))
            print(str(e))
            sys.stdout.flush()
            self._set_exit_code(1)
            self._send_headers(400, "text/plain")
            self.wfile.write(b"Handling redirect failed.")
            self._shutdown()
            return

        print(json.dumps(token_data, sort_keys=True))
        sys.stdout.flush()
        self._set_exit_code(0)
        if html_response:
            html = render_success_page(code, token_data)
            self._send_headers(200, "text/html")
            if html:
                self.wfile.write(html.encode("utf-8"))
            else:
                self.wfile.write(
                    b"OAuth redirect handled successfully. You can close this tab now."
                )
        else:
            self._send_headers(200, "text/plain")
            self.wfile.write(b"OK")
        self._shutdown()

    def do_OPTIONS(self):
        logging.info("OPTIONS %s from %s", self.path, self.client_address)
        self._send_headers(204, "text/plain")

    def do_GET(self):
        logging.info("GET %s from %s", urlparse(self.path).path, self.client_address)
        query = urlparse(self.path).query
        params = parse_qs(query)
        if "error" in params:
            # The user denied access: report it and stop listening.
            print(json.dumps({"error": params["error"][0]}))
            sys.stdout.flush()
            self._set_exit_code(1)
            self._send_headers(200, "text/plain")
            self.wfile.write(b"Sign-in was cancelled. You can close this tab.")
            self._shutdown()
            return
        # The redirect from Google carries the state we sent: anything else wasn't started by us.
        if expected_state and params.get("state", [""])[0] != expected_state:
            if "code" in params:
                self._reject("state mismatch")
            else:
                self._send_headers(404, "text/plain")  # Eg: favicon.ico
            return
        code = params.get("code", [""])[0]
        self._handle_code(self._extract_code(code), html_response=True)

    def do_POST(self):
        logging.info("POST %s from %s", self.path, self.client_address)
        origin = self.headers.get("Origin")
        if origin and origin != HELPER_ORIGIN:
            self._reject("origin {}".format(origin))
            return
        content_length = int(self.headers.get("Content-Length", 0))
        raw_body = self.rfile.read(content_length).decode("utf-8") if content_length else ""
        content_type = self.headers.get("Content-Type", "")
        code = ""
        if "application/json" in content_type:
            try:
                payload = json.loads(raw_body) if raw_body else {}
                code = payload.get("code", "")
            except json.JSONDecodeError:
                code = ""
        else:
            params = parse_qs(raw_body)
            code = params.get("code", [""])[0]
        self._handle_code(self._extract_code(code), html_response=False)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--client_id", required=True)
    parser.add_argument("--client_secret", default="")
    parser.add_argument("--listen_port", required=True, type=int)
    parser.add_argument("--redirect_uri", default="")
    parser.add_argument("--code_verifier", default="")
    parser.add_argument("--state", default="")
    args = parser.parse_args()
    logging.info("Script started with args: %s", masked_argv(sys.argv))
    client_id = args.client_id
    client_secret = args.client_secret
    listen_port = args.listen_port
    redirect_uri = args.redirect_uri or "http://127.0.0.1:{}/".format(listen_port)
    code_verifier = args.code_verifier
    expected_state = args.state

    stop_previous_listener()
    # Loopback only: the browser on this machine is the only expected client.
    server_address = ("127.0.0.1", listen_port)
    try:
        httpd = HTTPServer(server_address, OAuthRedirectHandler)
    except Exception:
        logging.exception("Failed to start server")
        sys.exit(1)
    try:
        with open(pid_path, "w") as handle:
            handle.write(str(os.getpid()))
    except OSError:
        pass
    signal.signal(signal.SIGTERM, lambda signum, frame: threading.Thread(target=httpd.shutdown, daemon=True).start())
    timer = threading.Timer(LISTEN_TIMEOUT, httpd.shutdown)
    timer.daemon = True
    timer.start()
    logging.info("Server started on 127.0.0.1:%s", listen_port)
    exit_code = 2  # Stays 2 if stopped by the timeout or SIGTERM without a code
    httpd.serve_forever()
    timer.cancel()
    try:
        with open(pid_path, "r") as handle:
            if handle.read().strip() == str(os.getpid()):
                os.remove(pid_path)
    except OSError:
        pass
    sys.exit(exit_code)
