"""The wheel download of package/contents/scripts/install_python_deps.py, with PyPI mocked."""
from __future__ import annotations

import hashlib
import importlib.util
import io
import json
import pathlib
import tempfile
import unittest
import zipfile
from unittest import mock

SCRIPT = pathlib.Path(__file__).resolve().parent.parent / "package/contents/scripts/install_python_deps.py"
spec = importlib.util.spec_from_file_location("install_python_deps", SCRIPT)
deps = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deps)


def wheel(files):
	buffer = io.BytesIO()
	with zipfile.ZipFile(buffer, "w") as archive:
		for name, text in files.items():
			archive.writestr(name, text)
	return buffer.getvalue()


class FakePyPI:
	"""fetch(): the JSON of each release in WHEELS and its wheel, with the wheel's real SHA-256
	unless `bad` names a package."""

	def __init__(self, wheels, bad=()):
		self.wheels = wheels
		self.bad = bad
		self.fetched = []

	def __call__(self, url):
		self.fetched.append(url)
		for name, blob in self.wheels.items():
			if url == "https://files.example/%s.whl" % name:
				return blob
			if url.startswith("https://pypi.org/pypi/%s/" % name):
				digest = "0" * 64 if name in self.bad else hashlib.sha256(blob).hexdigest()
				return json.dumps({"urls": [{"packagetype": "bdist_wheel", "filename": name + "-1-py3-none-any.whl",
					"url": "https://files.example/%s.whl" % name, "digests": {"sha256": digest}}]}).encode()
		raise AssertionError("unexpected fetch " + url)


class WheelInstallTest(unittest.TestCase):
	def setUp(self):
		self.tmp = tempfile.TemporaryDirectory()
		self.target = self.tmp.name

	def tearDown(self):
		self.tmp.cleanup()

	def install(self, pypi, present=()):
		with mock.patch.object(deps, "WHEELS", [("mod_" + n.replace("-", "_"), n, "1", "") for n in pypi.wheels]), \
				mock.patch.object(deps, "fetch", pypi), \
				mock.patch.object(deps, "importable", lambda name, target: name in present):
			return deps.with_wheels(self.target)

	def test_installs_the_missing_ones(self):
		pypi = FakePyPI({"alpha": wheel({"alpha.py": "x = 1"}), "beta": wheel({"beta/__init__.py": ""})})
		self.install(pypi, present=("mod_beta",))
		self.assertTrue((pathlib.Path(self.target) / "alpha.py").exists())
		self.assertFalse((pathlib.Path(self.target) / "beta").exists(), "already importable: skipped")
		self.assertFalse(any("beta" in url for url in pypi.fetched))

	def test_checksum_mismatch_is_refused(self):
		pypi = FakePyPI({"alpha": wheel({"alpha.py": "x = 1"})}, bad=("alpha",))
		with self.assertRaises(ValueError):
			self.install(pypi)
		self.assertFalse((pathlib.Path(self.target) / "alpha.py").exists())

	def test_path_outside_the_target_is_refused(self):
		pypi = FakePyPI({"evil": wheel({"../evil.py": "x = 1"})})
		with self.assertRaises(ValueError):
			self.install(pypi)
		self.assertFalse((pathlib.Path(self.target).parent / "evil.py").exists())

	def test_an_older_one_is_replaced(self):
		pypi = FakePyPI({"alpha": wheel({"alpha.py": "x = 1"})})
		with mock.patch.object(deps, "WHEELS", [("mod_alpha", "alpha", "7.3.0", "6.1")]), \
				mock.patch.object(deps, "fetch", pypi), \
				mock.patch.object(deps, "importable", lambda name, target: True), \
				mock.patch.object(deps, "installed_version", lambda dist, target: "5.0.13"):
			deps.with_wheels(self.target)
		self.assertTrue((pathlib.Path(self.target) / "alpha.py").exists(), "5.0.13 < 6.1: installed")

	def test_version_tuple(self):
		self.assertEqual(deps.version_tuple("2.9.0.post0"), (2, 9, 0))
		self.assertGreaterEqual(deps.version_tuple("7.3.0"), deps.version_tuple("6.1"))
		self.assertLess(deps.version_tuple("5.0.13"), deps.version_tuple("6.1"))

	def test_only_https(self):
		with self.assertRaises(ValueError):
			deps.fetch("http://pypi.org/pypi/x/json")


if __name__ == "__main__":
	unittest.main()
