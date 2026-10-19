"""List installed web apps for Google Meet that can open a meeting link.

Prints JSON: [{"name", "command", "authuser"}]. command is the app's launch command with %u where
the meeting URL goes; authuser is the Google account index or email the app uses ("" if none).
Handles browser "--app=URL" web apps (Linux Mint / Big Linux WebApp manager, Vivaldi, Chromium)
and installed Chromium PWAs ("--app-id=…").
"""

from __future__ import annotations

import configparser
import json
import os
import shlex
import sys
from urllib.parse import parse_qs, urlparse

MEET_HOST = "meet.google.com"
FIELD_CODES = ("%u", "%U", "%f", "%F", "%i", "%c", "%k")


def application_dirs() -> list[str]:
    data_home = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    data_dirs = (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":")
    return [os.path.join(d, "applications") for d in [data_home] + data_dirs if d]


def read_entry(path: str) -> dict[str, str] | None:
    parser = configparser.RawConfigParser(strict=False, interpolation=None)
    parser.optionxform = str
    try:
        parser.read(path, encoding="utf-8")
    except (configparser.Error, UnicodeDecodeError, OSError):
        return None
    if not parser.has_section("Desktop Entry"):
        return None
    return dict(parser.items("Desktop Entry"))


def app_from_entry(entry: dict[str, str]) -> dict[str, str] | None:
    exec_line = entry.get("Exec", "")
    name = entry.get("Name", "")
    try:
        argv = shlex.split(exec_line)
    except ValueError:
        return None
    argv = [arg for arg in argv if arg not in FIELD_CODES]
    if not argv:
        return None
    for index, arg in enumerate(argv):
        if arg.startswith("--app=") and MEET_HOST in arg:
            url = arg[len("--app="):]
            query = parse_qs(urlparse(url).query)
            authuser = (query.get("authuser") or [""])[0]
            argv = argv[:index] + ["--app=%u"] + argv[index + 1:]
            return {"name": name, "command": shlex.join(argv), "authuser": authuser}
    # Chromium PWA: its own window opens a given URL with this switch.
    is_pwa = any(arg.startswith("--app-id=") for arg in argv)
    if is_pwa and "meet" in name.lower():
        return {
            "name": name,
            "command": shlex.join(argv + ["--app-launch-url-for-shortcuts-menu-item=%u"]),
            "authuser": "",
        }
    return None


def main() -> int:
    apps = []
    seen = set()
    for directory in application_dirs():
        try:
            names = sorted(os.listdir(directory))
        except OSError:
            continue
        for filename in names:
            if not filename.endswith(".desktop") or filename in seen:
                continue
            seen.add(filename)
            entry = read_entry(os.path.join(directory, filename))
            if not entry or entry.get("Type", "Application") != "Application":
                continue
            app = app_from_entry(entry)
            if app:
                apps.append(app)
    json.dump(apps, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
