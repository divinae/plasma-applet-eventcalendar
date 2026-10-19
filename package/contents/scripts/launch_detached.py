"""Start a GUI app detached from the widget: launch_detached.py -- ARGV...

The app gets its own session and /dev/null for stdin/stdout/stderr, so nothing waits on it.
Exits 0 when it started; 127 when the program can't be run; the app's exit code when it quits
with an error within a moment (eg: a bad option), so the caller can fall back to the browser.
"""

from __future__ import annotations

import subprocess
import sys

STARTUP_CHECK_SECONDS = 1.5


def main(argv: list[str]) -> int:
    if argv[:1] == ["--"]:
        argv = argv[1:]
    if not argv:
        print("usage: launch_detached.py -- ARGV...", file=sys.stderr)
        return 2
    try:
        child = subprocess.Popen(
            argv,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
            close_fds=True,
        )
    except OSError as exc:  # Not found, not executable
        print("cannot start {}: {}".format(argv[0], exc.strerror), file=sys.stderr)
        return 127
    try:
        code = child.wait(timeout=STARTUP_CHECK_SECONDS)
    except subprocess.TimeoutExpired:
        return 0  # Still running: started
    # Exited already: fine with 0 (browsers hand the URL to a running instance), else an error.
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
