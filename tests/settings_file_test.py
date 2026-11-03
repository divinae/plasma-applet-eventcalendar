"""package/contents/scripts/settings_file.py: the settings file written in parts and read back."""
from __future__ import annotations

import base64
import contextlib
import importlib.util
import io
import os
import pathlib
import stat
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parent.parent / "package/contents/scripts/settings_file.py"
spec = importlib.util.spec_from_file_location("settings_file", SCRIPT)
sf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sf)


def b64(text):
	return base64.b64encode(text.encode("utf-8")).decode("ascii")


class SettingsFileTest(unittest.TestCase):
	def setUp(self):
		self.tmp = tempfile.TemporaryDirectory()
		self.path = os.path.join(self.tmp.name, "settings.json")

	def tearDown(self):
		self.tmp.cleanup()

	def run_main(self, *argv):
		out, err = io.StringIO(), io.StringIO()
		with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
			code = sf.main(list(argv))
		return code, out.getvalue(), err.getvalue()

	def test_parts_then_read(self):
		text = '{"app": "org.kde.plasma.eventcalendar", "name": "Zażółć"}'
		data = b64(text)
		parts = [data[i:i + 8] for i in range(0, len(data), 8)]
		for n, part in enumerate(parts):
			args = ["write", "--path", self.path, "--part", str(n), "--data", part]
			self.assertEqual(self.run_main(*(args + (["--last"] if n == len(parts) - 1 else [])))[0], 0)
		self.assertFalse(os.path.exists(self.path + ".part"))
		self.assertEqual(stat.S_IMODE(os.stat(self.path).st_mode), 0o600)
		code, out, _ = self.run_main("read", "--path", self.path)
		self.assertEqual((code, out), (0, text))

	def test_not_finished_leaves_the_old_file(self):
		pathlib.Path(self.path).write_text("old")
		self.run_main("write", "--path", self.path, "--part", "0", "--data", b64("new"))
		self.assertEqual(pathlib.Path(self.path).read_text(), "old")

	def test_only_json(self):
		code, _, err = self.run_main("read", "--path", os.path.join(self.tmp.name, "x.txt"))
		self.assertEqual(code, 1)
		self.assertIn("json", err)

	def test_a_later_part_needs_the_first(self):
		self.assertEqual(self.run_main("write", "--path", self.path, "--part", "1", "--data", b64("x"))[0], 1)

	def test_too_large(self):
		pathlib.Path(self.path).write_bytes(b" " * (sf.MAX_SIZE + 1))
		self.assertEqual(self.run_main("read", "--path", self.path)[0], 1)


if __name__ == "__main__":
	unittest.main()
