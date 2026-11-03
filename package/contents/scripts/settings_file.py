#!/usr/bin/env python3
"""Writes and reads the widget's settings file (Settings > Views > Settings backup, issue #21).

QML can't write files, so the settings page sends the file's text base64-encoded, part by part (a
command line has a length limit):
  write --path FILE.json --part N --data BASE64 [--last]
Part 0 starts FILE.json.part (0600), the others append to it; --last renames it to FILE.json.
  read --path FILE.json
prints the file (at most MAX_SIZE bytes). Only .json files.
"""

import argparse
import base64
import os
import sys

MAX_SIZE = 4 * 1024 * 1024


def fail(message):
	print(message, file=sys.stderr)
	return 1


def write(path, part, data, last):
	try:
		blob = base64.b64decode(data.encode("ascii"), validate=True)
	except ValueError as err:
		return fail("Bad data: %s" % err)
	temp = path + ".part"
	if part == 0:
		fd = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
	else:
		if not os.path.isfile(temp):
			return fail("Part %d without the ones before" % part)
		if os.path.getsize(temp) + len(blob) > MAX_SIZE:
			os.unlink(temp)
			return fail("Too large")
		fd = os.open(temp, os.O_WRONLY | os.O_APPEND)
	with os.fdopen(fd, "wb") as handle:
		handle.write(blob)
	if last:
		os.replace(temp, path)
	return 0


def read(path):
	if not os.path.isfile(path):
		return fail("Not a file")
	if os.path.getsize(path) > MAX_SIZE:
		return fail("Too large")
	with open(path, "rb") as handle:
		sys.stdout.write(handle.read().decode("utf-8", errors="replace"))
	return 0


def main(argv=None):
	parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
	sub = parser.add_subparsers(dest="command", required=True)
	w = sub.add_parser("write")
	w.add_argument("--path", required=True)
	w.add_argument("--part", type=int, required=True)
	w.add_argument("--data", required=True)
	w.add_argument("--last", action="store_true")
	r = sub.add_parser("read")
	r.add_argument("--path", required=True)
	args = parser.parse_args(argv)

	path = os.path.abspath(os.path.expanduser(args.path))
	if not path.lower().endswith(".json"):
		return fail("Only .json files")
	try:
		if args.command == "write":
			return write(path, args.part, args.data, args.last)
		return read(path)
	except OSError as err:
		return fail(err.strerror or str(err))


if __name__ == "__main__":
	sys.exit(main())
