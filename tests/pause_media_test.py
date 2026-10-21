import os
import stat
import subprocess
import sys
import tempfile
import textwrap
import unittest

SCRIPT = os.path.join(os.path.dirname(__file__), '..', 'package', 'contents', 'scripts', 'pause_media.py')

# A dbus-send stand-in: two players playing (one on a KDE Connect phone), one paused; logs calls.
FAKE_DBUS_SEND = textwrap.dedent('''\
    #!/usr/bin/env python3
    import os, sys
    args = sys.argv[1:]
    dest = [a for a in args if a.startswith('--dest=')][0][len('--dest='):]
    with open(os.environ['FAKE_LOG'], 'a') as log:
        log.write(dest + ' ' + args[-1] + '\\n')
    if dest == 'org.freedesktop.DBus':
        for name in ['org.mpris.MediaPlayer2.elisa', 'org.mpris.MediaPlayer2.vlc',
                     'org.mpris.MediaPlayer2.kdeconnect.mpris_phone', 'org.kde.plasmashell']:
            print('      string "%s"' % name)
    elif 'PlaybackStatus' in args[-1]:
        print('   variant       string "%s"' % ('Paused' if dest.endswith('vlc') else 'Playing'))
''')


class PauseMediaTest(unittest.TestCase):
    def run_script(self, *args):
        with tempfile.TemporaryDirectory() as tmp:
            fake = os.path.join(tmp, 'dbus-send')
            with open(fake, 'w') as f:
                f.write(FAKE_DBUS_SEND)
            os.chmod(fake, stat.S_IRWXU)
            log = os.path.join(tmp, 'log')
            env = dict(os.environ, PATH=tmp + os.pathsep + os.environ.get('PATH', ''), FAKE_LOG=log)
            out = subprocess.run([sys.executable, '-I', SCRIPT] + list(args), env=env,
                                 capture_output=True, text=True, check=True).stdout
            calls = open(log).read().splitlines() if os.path.exists(log) else []
            return out, calls

    def test_pauses_only_local_players_that_play(self):
        out, calls = self.run_script()
        self.assertEqual(out.strip(), '1')
        pauses = [c for c in calls if c.endswith('Player.Pause')]
        self.assertEqual(pauses, ['org.mpris.MediaPlayer2.elisa org.mpris.MediaPlayer2.Player.Pause'])
        self.assertFalse(any('kdeconnect' in c for c in calls))

    def test_dry_run_lists_without_pausing(self):
        out, calls = self.run_script('--dry-run')
        self.assertEqual(out.split(), ['org.mpris.MediaPlayer2.elisa'])
        self.assertFalse(any(c.endswith('Player.Pause') for c in calls))


if __name__ == '__main__':
    unittest.main()
