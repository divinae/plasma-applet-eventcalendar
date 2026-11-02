#!/usr/bin/env python3
"""Installs the Python modules Event Calendar NG reads .ics files and CalDAV with (icalendar and
recurring-ical-events, with what they need) into the widget's own folder, without root:
~/.local/share/plasma_org.kde.plasma.eventcalendar/python, which icsjson.py puts on sys.path.

The same as ./install does, for an install from the KDE Store or Discover (which runs no script).
In order: pip (--target), uv (--target), else the wheels from PyPI themselves: pinned versions,
pure-Python wheels only, each checked against the SHA-256 PyPI publishes for it (as pip does).
Only the modules Python can't import yet are installed.

Prints one JSON line: {"ok": true, "method": "pip" | "uv" | "wheels" | "present"} or
{"ok": false, "error": "...", "noInstaller": bool}. Exit code 0 / 1.
"""

import argparse
import hashlib
import importlib.util
import io
import json
import os
import shutil
import subprocess
import sys
import urllib.request
import zipfile

TARGET = os.path.expanduser("~/.local/share/plasma_org.kde.plasma.eventcalendar/python")
SPEC = "recurring-ical-events>=3.8,<4"
TIMEOUT = 60

# (import name, PyPI name, version, oldest that works with the rest): pure-Python wheels known to
# work together. One already importable at least that old is kept (an older one gets this version
# in the target, which comes first on the path). click: x_wr_timezone imports it;
# typing_extensions: icalendar on Python < 3.13.
WHEELS = [
	("six", "six", "1.17.0", ""),
	("dateutil", "python-dateutil", "2.9.0.post0", "2.8.1"),
	("tzdata", "tzdata", "2026.6", ""),
	("typing_extensions", "typing-extensions", "4.12.2", ""),
	("click", "click", "8.1.8", ""),
	("icalendar", "icalendar", "7.3.0", "6.1"),
	("x_wr_timezone", "x-wr-timezone", "2.0.1", "1.0"),
	("recurring_ical_events", "recurring-ical-events", "3.8.2", "3.8"),
]
NEEDED = ("icalendar", "recurring_ical_events")


def importable(name, target):
	"""Whether a fresh Python finds module `name` (with `target` on its path, as icsjson.py has)."""
	code = "import sys; sys.path.insert(0, sys.argv[1]); import " + name
	return subprocess.run([sys.executable, "-I", "-c", code, target],
		stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0


def version_tuple(text):
	parts = []
	for piece in str(text).split("."):
		digits = ""
		for c in piece:
			if not c.isdigit():
				break
			digits += c
		if not digits:
			break # "post0", "rc1": the release numbers end there
		parts.append(int(digits))
	return tuple(parts)


def installed_version(dist, target):
	"""The version of distribution `dist` Python finds (with `target` first), or None."""
	code = ("import sys; sys.path.insert(0, sys.argv[1]); import importlib.metadata as m\n"
		"try: print(m.version(sys.argv[2]))\nexcept Exception: pass")
	result = subprocess.run([sys.executable, "-I", "-c", code, target, dist], stdout=subprocess.PIPE,
		stderr=subprocess.DEVNULL, text=True)
	return result.stdout.strip() or None


def usable(module, dist, oldest, target):
	"""Importable, and (when `oldest` is set) at least that version."""
	if not importable(module, target):
		return False
	if not oldest:
		return True
	version = installed_version(dist, target)
	return version is not None and version_tuple(version) >= version_tuple(oldest)


def all_present(target):
	return all(importable(name, target) for name in NEEDED)


def run(cmd):
	try:
		result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=600)
	except (OSError, subprocess.TimeoutExpired) as err:
		return False, str(err)
	return result.returncode == 0, result.stdout


def has_pip():
	return importlib.util.find_spec("pip") is not None


def with_pip(target):
	return run([sys.executable, "-m", "pip", "install", "--disable-pip-version-check", "--no-warn-script-location",
		"--upgrade", "--target", target, SPEC])


def with_uv(target):
	uv = shutil.which("uv")
	return run([uv, "pip", "install", "--python", sys.executable, "--target", target, SPEC])


def fetch(url):
	if not url.startswith("https://"):
		raise ValueError("not https: " + url)
	with urllib.request.urlopen(url, timeout=TIMEOUT) as response:
		return response.read()


def wheel_for(name, version):
	"""The release's pure-Python wheel: (url, sha256) from PyPI's JSON."""
	data = json.loads(fetch("https://pypi.org/pypi/%s/%s/json" % (name, version)))
	for item in data.get("urls", []):
		filename = item.get("filename", "")
		if item.get("packagetype") == "bdist_wheel" and filename.endswith("-none-any.whl"):
			return item["url"], item["digests"]["sha256"]
	raise ValueError("no pure-Python wheel for %s %s" % (name, version))


def with_wheels(target):
	os.makedirs(target, exist_ok=True)
	for module, name, version, oldest in WHEELS:
		if usable(module, name, oldest, target):
			continue
		url, sha256 = wheel_for(name, version)
		blob = fetch(url)
		if hashlib.sha256(blob).hexdigest() != sha256:
			raise ValueError("checksum mismatch for %s %s" % (name, version))
		with zipfile.ZipFile(io.BytesIO(blob)) as wheel:
			for member in wheel.namelist():
				path = os.path.normpath(os.path.join(target, member))
				if not path.startswith(os.path.normpath(target) + os.sep):
					raise ValueError("unsafe path in %s: %s" % (name, member))
			wheel.extractall(target)
	return True, ""


def main(argv=None):
	parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
	parser.add_argument("--target", default=TARGET, help=argparse.SUPPRESS) # Tests
	args = parser.parse_args(argv)
	target = os.path.abspath(args.target)

	def done(result):
		print(json.dumps(result))
		return 0 if result.get("ok") else 1

	if all_present(target):
		return done({"ok": True, "method": "present"})
	os.makedirs(target, exist_ok=True)
	attempts = []
	if has_pip():
		attempts.append(("pip", with_pip))
	if shutil.which("uv"):
		attempts.append(("uv", with_uv))
	attempts.append(("wheels", with_wheels))
	errors = []
	for method, install in attempts:
		try:
			ok, output = install(target)
		except Exception as err: # noqa: BLE001 (any failure: the next way, then an error line)
			ok, output = False, str(err)
		if ok and all_present(target):
			return done({"ok": True, "method": method})
		last = ((output or "").strip().splitlines() or [""])[-1]
		errors.append("%s: %s" % (method, last) if last else method)
	return done({"ok": False, "error": "; ".join(str(e) for e in errors)[:400], "noInstaller": not has_pip() and not shutil.which("uv")})


if __name__ == "__main__":
	sys.exit(main())
