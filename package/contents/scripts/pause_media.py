#!/usr/bin/env python3
"""Pause the media players that are playing (MPRIS), eg: before joining a meeting.

Talks to the session bus with dbus-send (part of D-Bus itself), so no Python D-Bus module is
needed. Players on other devices (KDE Connect) and the playerctld proxy are left alone.

Prints the number of players paused. --dry-run lists the playing players instead.
"""

import argparse
import re
import subprocess
import sys

MPRIS_PREFIX = 'org.mpris.MediaPlayer2.'
SKIPPED = ('org.mpris.MediaPlayer2.kdeconnect', 'org.mpris.MediaPlayer2.playerctld')
TIMEOUT = 3


def dbus_send(dest, path, method, *args):
    command = ['dbus-send', '--session', '--print-reply', '--reply-timeout=2000',
               '--dest=' + dest, path, method] + list(args)
    result = subprocess.run(command, capture_output=True, text=True, timeout=TIMEOUT, check=False)
    return result.stdout if result.returncode == 0 else None


def players():
    reply = dbus_send('org.freedesktop.DBus', '/org/freedesktop/DBus', 'org.freedesktop.DBus.ListNames')
    names = re.findall(r'string "([^"]+)"', reply or '')
    return [name for name in names
            if name.startswith(MPRIS_PREFIX) and not name.startswith(SKIPPED)]


def is_playing(name):
    reply = dbus_send(name, '/org/mpris/MediaPlayer2', 'org.freedesktop.DBus.Properties.Get',
                      'string:org.mpris.MediaPlayer2.Player', 'string:PlaybackStatus')
    return bool(reply) and '"Playing"' in reply


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dry-run', action='store_true', help='list the playing players only')
    args = parser.parse_args(argv)
    paused = 0
    for name in players():
        try:
            if not is_playing(name):
                continue
            if args.dry_run:
                print(name)
                continue
            if dbus_send(name, '/org/mpris/MediaPlayer2', 'org.mpris.MediaPlayer2.Player.Pause') is not None:
                paused += 1
        except (OSError, subprocess.TimeoutExpired):
            continue
    if not args.dry_run:
        print(paused)
    return 0


if __name__ == '__main__':
    sys.exit(main())
