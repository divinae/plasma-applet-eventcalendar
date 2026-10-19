import argparse
import datetime
import hashlib
import ipaddress
import json
import os
import socket
import sys
import urllib.parse
import urllib.request

LOCAL_DATA_DIR = os.path.realpath(
	os.path.expanduser("~/.local/share/plasma_org.kde.plasma.eventcalendar")
)
LOCAL_PYTHON_DIR = os.path.join(LOCAL_DATA_DIR, "python")
if os.path.isdir(LOCAL_PYTHON_DIR) and LOCAL_PYTHON_DIR not in sys.path:
	sys.path.insert(0, LOCAL_PYTHON_DIR)

from icalendar import Calendar

try:
	import recurring_ical_events  # expands RRULE/EXDATE/RECURRENCE-ID into occurrences
except ImportError:
	recurring_ical_events = None

MAX_ICS_BYTES = 10 * 1024 * 1024
REQUEST_TIMEOUT = 15
ALLOWED_URL_SCHEMES = {"file", "http", "https"}
SAFE_REMOTE_SCHEMES = {"http", "https"}
LOCAL_ICS_DIR = LOCAL_DATA_DIR


def date_to_json(date_value):
	if isinstance(date_value, datetime.datetime):
		return {"dateTime": date_value.isoformat()}
	return {"date": date_value.isoformat()}


def stringify(value):
	return "" if value is None else str(value)


def get_event_date(event, key):
	value = event.get(key)
	if value is None or not hasattr(value, "dt"):
		return None
	return value.dt


def get_event_bounds(event):
	start = get_event_date(event, "DTSTART")
	if start is None:
		return None, None
	end = getattr(event, "end", None) or get_event_date(event, "DTEND")
	if end is None:
		duration = get_event_date(event, "DURATION")
		if isinstance(duration, datetime.timedelta):
			end = start + duration
		elif isinstance(start, datetime.date) and not isinstance(start, datetime.datetime):
			end = start + datetime.timedelta(days=1)
		else:
			end = start
	return start, end


def build_event_uid(event, start_date, end_date):
	uid = stringify(event.get("UID")).strip()
	if uid:
		return uid

	summary = stringify(event.get("SUMMARY")).strip()
	digest = hashlib.sha1(
		"|".join([
			start_date.isoformat(),
			end_date.isoformat(),
			summary,
		]).encode("utf-8", "ignore")
	).hexdigest()
	return digest


def events_to_json(event_list=None, indent=4):
	if event_list is None:
		event_list = []

	data = {"items": []}
	for event in event_list:
		status = stringify(event.get("STATUS")).strip().lower()
		if status == "cancelled":
			continue
		start_date, end_date = get_event_bounds(event)
		if start_date is None or end_date is None:
			# No usable DTSTART / end: skipped
			continue

		ical_uid = build_event_uid(event, start_date, end_date)
		item = {
			"kind": "calendar#event",
			"etag": "\"0123456789012345\"",
			"iCalUID": ical_uid,
			"id": "ics_{}_{}_{}".format(
				ical_uid,
				start_date.isoformat(),
				end_date.isoformat(),
			),
			"status": status or "confirmed",
			"htmlLink": "",
			"summary": stringify(event.get("SUMMARY")),
			"start": date_to_json(start_date),
			"end": date_to_json(end_date),
		}

		if "CREATED" in event and hasattr(event["CREATED"], "dt"):
			item["created"] = event["CREATED"].dt.isoformat()
		if "LAST-MODIFIED" in event and hasattr(event["LAST-MODIFIED"], "dt"):
			item["updated"] = event["LAST-MODIFIED"].dt.isoformat()
		if "LOCATION" in event:
			item["location"] = stringify(event.get("LOCATION"))
		if "DESCRIPTION" in event:
			item["description"] = stringify(event.get("DESCRIPTION"))

		data["items"].append(item)

	return json.dumps(data, indent=indent)


#--- Raw events (import): the VEVENTs as they are, recurring series kept with their rules.

def time_zone_name(dt):
	"""IANA name of an aware datetime's zone, or "" (UTC offsets, unknown or Windows names)."""
	tz = getattr(dt, "tzinfo", None)
	if tz is None:
		return ""
	name = getattr(tz, "key", None) or getattr(tz, "zone", None) or ""
	if not name:
		if dt.utcoffset() == datetime.timedelta(0):
			return "UTC"
		return ""
	try:
		import zoneinfo
		zoneinfo.ZoneInfo(name)
	except Exception:
		return ""
	return name


def raw_date_to_json(value):
	if isinstance(value, datetime.datetime):
		data = {"dateTime": value.isoformat()}
		zone = time_zone_name(value)
		if zone:
			data["timeZone"] = zone
		return data
	return {"date": value.isoformat()}


def ical_date_value(value):
	"""An EXDATE/RDATE value: a date, a UTC time, or a floating (local) time."""
	if isinstance(value, datetime.datetime):
		if value.tzinfo is not None:
			return value.astimezone(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
		return value.strftime("%Y%m%dT%H%M%S")
	if isinstance(value, datetime.date):
		return value.strftime("%Y%m%d")
	return None


def date_list_lines(event, key):
	"""EXDATE / RDATE as lines Google accepts: times in UTC, so no (maybe Windows) TZID."""
	prop = event.get(key)
	if prop is None:
		return []
	props = prop if isinstance(prop, list) else [prop]
	times = []
	dates = []
	for item in props:
		for entry in getattr(item, "dts", []):
			value = getattr(entry, "dt", None)
			if isinstance(value, tuple):  # RDATE periods aren't supported by Google
				continue
			text = ical_date_value(value)
			if text is None:
				continue
			if isinstance(value, datetime.datetime):
				times.append(text)
			else:
				dates.append(text)
	lines = []
	if times:
		lines.append("{}:{}".format(key, ",".join(times)))
	if dates:
		lines.append("{};VALUE=DATE:{}".format(key, ",".join(dates)))
	return lines


def event_recurrence(event):
	lines = []
	rules = event.get("RRULE")
	if rules is not None:
		for rule in (rules if isinstance(rules, list) else [rules]):
			lines.append("RRULE:" + rule.to_ical().decode("utf-8"))
	lines.extend(date_list_lines(event, "RDATE"))
	lines.extend(date_list_lines(event, "EXDATE"))
	return lines


def event_to_raw(event):
	start, end = get_event_bounds(event)
	if start is None or end is None:
		return None
	item = {
		"iCalUID": build_event_uid(event, start, end),  # Google's import needs one
		"summary": stringify(event.get("SUMMARY")),
		"start": raw_date_to_json(start),
		"end": raw_date_to_json(end),
		"allDay": not isinstance(start, datetime.datetime),
	}
	for key, name in (("LOCATION", "location"), ("DESCRIPTION", "description")):
		if key in event:
			item[name] = stringify(event.get(key))
	transp = stringify(event.get("TRANSP")).strip().upper()
	if transp:
		item["transp"] = transp
	klass = stringify(event.get("CLASS")).strip().upper()
	if klass:
		item["class"] = klass
	recurrence = event_recurrence(event)
	if recurrence:
		item["recurrence"] = recurrence
	recurrence_id = get_event_date(event, "RECURRENCE-ID")
	if recurrence_id is not None:
		item["recurrenceId"] = raw_date_to_json(recurrence_id)
	attendees = event.get("ATTENDEE")
	if attendees is not None:
		item["attendeeCount"] = len(attendees) if isinstance(attendees, list) else 1
	return item


def raw_events_to_json(cal, indent=4):
	"""The calendar's VEVENTs without expanding recurring series. Cancelled ones are skipped."""
	data = {"items": [], "skipped": 0}
	method = stringify(cal.get("METHOD")).strip().upper()
	if method:
		data["method"] = method
	for event in cal.walk("vevent"):
		status = stringify(event.get("STATUS")).strip().lower()
		item = None if status == "cancelled" else event_to_raw(event)
		if item is None:
			data["skipped"] += 1
			continue
		data["items"].append(item)
	return json.dumps(data, indent=indent)


def read_import_file(path):
	"""A .ics file the user picked to import (any folder, unlike calendar URLs)."""
	if path.startswith("file://"):
		path = urllib.request.url2pathname(urllib.parse.urlparse(path).path)
	path = os.path.realpath(os.path.expanduser(path))
	if not path.lower().endswith(".ics"):
		raise ValueError("Only .ics files can be imported")
	if not os.path.isfile(path):
		raise ValueError("File not found")
	with open(path, "rb") as handle:
		data = handle.read(MAX_ICS_BYTES + 1)
	if len(data) > MAX_ICS_BYTES:
		raise ValueError("Calendar file exceeds size limit")
	return Calendar.from_ical(data)


def ensure_date_time(dt):
	if isinstance(dt, datetime.date) and not isinstance(dt, datetime.datetime):
		dt = datetime.datetime.combine(dt, datetime.time.min)
	if isinstance(dt, datetime.datetime) and dt.tzinfo is not None:
		# ICS feeds (eg. Outlook) mix tz-aware timed events with naive all-day
		# dates; comparing them against the naive query bounds raises TypeError.
		dt = dt.astimezone().replace(tzinfo=None)
	return dt


def event_within(event, start_time, end_time):
	event_start_date, event_end_date = get_event_bounds(event)
	if event_start_date is None or event_end_date is None:
		return False

	event_start = ensure_date_time(event_start_date)
	event_end = ensure_date_time(event_end_date)
	start_time = ensure_date_time(start_time)
	end_time = ensure_date_time(end_time)
	if event_start == event_end:
		return start_time <= event_start < end_time
	return event_start < end_time and start_time < event_end


def validate_remote_host(parsed_url):
	hostname = parsed_url.hostname
	if not hostname:
		raise ValueError("Remote calendar URL is missing a hostname")

	for family, _, _, _, sockaddr in socket.getaddrinfo(hostname, None):
		address = sockaddr[0]
		ip = ipaddress.ip_address(address)
		if (
			ip.is_private
			or ip.is_loopback
			or ip.is_link_local
			or ip.is_multicast
			or ip.is_reserved
			or ip.is_unspecified
		):
			raise ValueError("Refusing remote calendar URL that resolves to a local/private address")


def parse_calendar_url(raw_url):
	parsed = urllib.parse.urlparse(raw_url, scheme="file")
	scheme = parsed.scheme.lower()
	if scheme not in ALLOWED_URL_SCHEMES:
		raise ValueError("Unsupported calendar URL scheme: {}".format(parsed.scheme))

	if scheme == "file":
		if parsed.netloc not in ("", "localhost"):
			raise ValueError("Only local file calendar URLs are supported")
		path = os.path.realpath(urllib.request.url2pathname(parsed.path or ""))
		if not path:
			raise ValueError("Calendar file path is empty")
		if not path.lower().endswith(".ics"):
			raise ValueError("Local calendar files must use the .ics extension")
		try:
			if os.path.commonpath([LOCAL_ICS_DIR, path]) != LOCAL_ICS_DIR:
				raise ValueError("Local calendar files must stay inside the applet data directory")
		except ValueError:
			raise ValueError("Local calendar file path is invalid")
		return parsed

	validate_remote_host(parsed)
	return parsed


class SafeRedirectHandler(urllib.request.HTTPRedirectHandler):
	def redirect_request(self, req, fp, code, msg, headers, newurl):
		parsed = parse_calendar_url(newurl)
		if parsed.scheme not in SAFE_REMOTE_SCHEMES:
			raise ValueError("Redirected calendar URL must stay on http/https")
		return super().redirect_request(req, fp, code, msg, headers, newurl)


def read_calendar_bytes(parsed_url):
	if parsed_url.scheme == "file":
		path = urllib.request.url2pathname(parsed_url.path or "")
		if not path:
			raise ValueError("Calendar file path is empty")
		with open(path, "rb") as handle:
			data = handle.read(MAX_ICS_BYTES + 1)
	else:
		opener = urllib.request.build_opener(SafeRedirectHandler)
		request = urllib.request.Request(
			urllib.parse.urlunparse(parsed_url),
			headers={"User-Agent": "eventcalendar/1.0"},
		)
		with opener.open(request, timeout=REQUEST_TIMEOUT) as sock:
			data = sock.read(MAX_ICS_BYTES + 1)

	if len(data) > MAX_ICS_BYTES:
		raise ValueError("Calendar file exceeds size limit")
	return data


class CalendarManager:
	def __init__(self, url):
		self.url = url
		self.cal = None

	def read(self):
		parsed_url = parse_calendar_url(self.url)
		text = read_calendar_bytes(parsed_url)
		self.cal = Calendar.from_ical(text)

	@property
	def events(self):
		return self.cal.walk("vevent")

	def query(self, start_time, end_time):
		if recurring_ical_events is not None:
			# Expand recurring series into individual occurrences (RRULE, EXDATE,
			# RECURRENCE-ID overrides). Without this, recurring meetings only
			# match on their series start date and every other occurrence is lost.
			yield from recurring_ical_events.of(self.cal).between(start_time, end_time)
			return
		for event in self.events:
			if event_within(event, start_time, end_time):
				yield event


def parse_date(date_str):
	return datetime.datetime.strptime(date_str, "%Y-%m-%d")


def argparse_date(value):
	try:
		return parse_date(value)
	except ValueError:
		msg = "Not a valid date: '{}'.".format(value)
		raise argparse.ArgumentTypeError(msg)


if __name__ == "__main__":
	parser = argparse.ArgumentParser(description="Read and query ICS calendar files")
	parser.add_argument("--url", type=str, help="The .ics file or URL to read (query)")
	subparsers = parser.add_subparsers(help="Commands", dest="subcommand")

	query = subparsers.add_parser("query")
	query.add_argument("startTime", type=argparse_date, help="Inclusive starting date in YYYY-MM-DD format")
	query.add_argument("endTime", type=argparse_date, help="Exclusive ending date in YYYY-MM-DD format")

	events = subparsers.add_parser("events", help="Print the file's events as they are (no recurrence expansion)")
	events.add_argument("path", type=str, help="A local .ics file (path or file:// URL)")

	args = parser.parse_args()

	if args.subcommand == "events":
		try:
			print(raw_events_to_json(read_import_file(args.path)))
		except Exception as error:
			print("{}: {}".format(type(error).__name__, error), file=sys.stderr)
			sys.exit(1)
		sys.exit(0)

	if not args.url:
		parser.error("--url is required")
	manager = CalendarManager(args.url)
	if args.subcommand == "query":
		manager.read()
		event_list = manager.query(args.startTime, args.endTime)
		print(events_to_json(event_list))
