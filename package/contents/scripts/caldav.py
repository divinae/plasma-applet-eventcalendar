"""CalDAV client for the widget: discover calendars, query, create/update/delete and import events.

python3 caldav.py <command> ... prints JSON on stdout and exits 0. On failure it exits 1 with one
line on stderr, "KIND: message", KIND being AUTH, NOTFOUND, CONFLICT, NETWORK, PROTOCOL, INPUT,
DEPS or KEYRING (the keyring couldn't be read, eg: not up yet at login; try again later).

Commands (all take --account ID --user USERNAME):
	discover --url URL
	query --url CALENDAR START END            (YYYY-MM-DD, END exclusive)
	put --url CALENDAR [--href RES --etag E] [--event-b64 B64]
	                                          (event JSON as base64 of UTF-8, else on stdin)
	delete --href RES --etag E
	import --url CALENDAR --file PATH

The password comes from the keyring (secret_store.py, scope "caldav-account", key "password",
account_id ID). For tests and command-line use only, --password-stdin reads it from the first
line of stdin instead (for put, the event JSON follows on the next lines). The password is never
taken from argv and never printed.
"""

import argparse
import base64
import datetime
import hashlib
import ipaddress
import json
import os
import re
import socket
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid
import xml.etree.ElementTree as ET

SCRIPT_DIR = os.path.dirname(os.path.realpath(__file__))
if SCRIPT_DIR not in sys.path:
	sys.path.insert(0, SCRIPT_DIR)

# The .ics modules (icalendar, recurring-ical-events): missing (an install from the KDE Store), every
# command answers "DEPS: ..." (the widget offers to install them), not a traceback.
try:
	import icsjson  # noqa: E402  (also puts the bundled icalendar / recurring_ical_events on sys.path)
	from icalendar import Calendar, Event  # noqa: E402
except ImportError as import_error:
	icsjson = None
	Calendar = Event = None
	MISSING_MODULE = getattr(import_error, "name", None) or str(import_error)
else:
	MISSING_MODULE = ""

REQUEST_TIMEOUT = 20
MAX_RESPONSE_BYTES = 20 * 1024 * 1024
MAX_REDIRECTS = 5
REDIRECT_CODES = (301, 302, 307, 308)
USER_AGENT = "eventcalendar-ng-caldav/1.0"
PRODID = "-//Event Calendar NG//CalDAV//EN"
SECRET_SCOPE = "caldav-account"
SECRET_KEY = "password"

NS_DAV = "DAV:"
NS_CALDAV = "urn:ietf:params:xml:ns:caldav"
NS_CS = "http://calendarserver.org/ns/"
NS_ICAL = "http://apple.com/ns/ical/"
PREFIXES = {NS_DAV: "d", NS_CALDAV: "c", NS_CS: "cs", NS_ICAL: "ical"}

ERROR_KINDS = ("AUTH", "NOTFOUND", "CONFLICT", "NETWORK", "PROTOCOL", "INPUT", "DEPS", "KEYRING")


def tag(ns, name):
	return "{%s}%s" % (ns, name)


class CalDavError(Exception):
	def __init__(self, kind, message):
		assert kind in ERROR_KINDS
		super().__init__(message)
		self.kind = kind
		self.message = message

	def line(self):
		return "{}: {}".format(self.kind, " ".join(str(self.message).split()))


def url_path(url):
	"""A URL's path only, for messages (no host, no userinfo, no query)."""
	try:
		return urllib.parse.urlsplit(url).path or "/"
	except ValueError:
		return "?"


def error_for_status(status, url):
	path = url_path(url)
	if status in (401, 403):
		return CalDavError("AUTH", "Access denied (HTTP {}) for {}".format(status, path))
	if status in (404, 410):
		return CalDavError("NOTFOUND", "Not found (HTTP {}): {}".format(status, path))
	if status == 412:
		return CalDavError("CONFLICT", "Changed on the server (HTTP 412): {}".format(path))
	return CalDavError("PROTOCOL", "Unexpected HTTP {} for {}".format(status, path))


#--- URL rules

def resolve_host(hostname):
	return [info[4][0] for info in socket.getaddrinfo(hostname, None)]


def is_local_address(address):
	ip = ipaddress.ip_address(address.split("%", 1)[0])
	if ip.version == 6 and ip.ipv4_mapped is not None:
		ip = ip.ipv4_mapped
	return ip.is_loopback or ip.is_private


def check_url(url):
	"""Normalized absolute URL (no userinfo, no fragment) or CalDavError INPUT/NETWORK.

	https anywhere; plain http only when every address of the host is loopback or private."""
	if not isinstance(url, str) or not url.strip():
		raise CalDavError("INPUT", "URL is empty")
	try:
		parts = urllib.parse.urlsplit(url.strip())
		port = parts.port
	except ValueError:
		raise CalDavError("INPUT", "Invalid URL")
	scheme = parts.scheme.lower()
	if scheme not in ("http", "https"):
		raise CalDavError("INPUT", "URL must use https")
	host = parts.hostname
	if not host:
		raise CalDavError("INPUT", "URL has no host")
	if scheme == "http":
		try:
			addresses = resolve_host(host)
		except (socket.gaierror, UnicodeError, OSError) as error:
			raise CalDavError("NETWORK", "Cannot resolve host: {}".format(getattr(error, "strerror", None) or error))
		try:
			local = bool(addresses) and all(is_local_address(a) for a in addresses)
		except ValueError:
			local = False
		if not local:
			raise CalDavError("INPUT", "http only for local servers")
	netloc = "[{}]".format(host) if ":" in host else host
	if port:
		netloc += ":{}".format(port)
	return urllib.parse.urlunsplit((scheme, netloc, parts.path or "/", parts.query, ""))


def origin(url):
	parts = urllib.parse.urlsplit(url)
	scheme = parts.scheme.lower()
	port = parts.port or (443 if scheme == "https" else 80)
	return scheme, (parts.hostname or "").lower(), port


def check_redirect(old_url, new_url):
	if origin(old_url) != origin(new_url):
		raise CalDavError("PROTOCOL", "Redirect to another server refused ({})".format(url_path(new_url)))


#--- HTTP

class _NoRedirect(urllib.request.HTTPRedirectHandler):
	def redirect_request(self, req, fp, code, msg, headers, newurl):
		return None  # handled in Client.request (keeps the method and body)


class Client:
	def __init__(self, user, password):
		self.user = user or ""
		token = base64.b64encode("{}:{}".format(self.user, password or "").encode("utf-8")).decode("ascii")
		self._auth = "Basic " + token
		self._opener = urllib.request.build_opener(_NoRedirect)

	def _send(self, method, url, body, headers):
		"""(status, headers, data) for any HTTP status; CalDavError NETWORK when there's no answer."""
		request = urllib.request.Request(url, data=body, method=method)
		request.add_header("User-Agent", USER_AGENT)
		request.add_header("Authorization", self._auth)
		for key, value in (headers or {}).items():
			request.add_header(key, value)
		try:
			response = self._opener.open(request, timeout=REQUEST_TIMEOUT)
		except urllib.error.HTTPError as error:
			try:
				data = error.read(MAX_RESPONSE_BYTES + 1) if error.fp is not None else b""
			except Exception:
				data = b""
			return error.code, error.headers, data
		except urllib.error.URLError as error:
			reason = error.reason
			text = getattr(reason, "strerror", None) or str(reason)
			raise CalDavError("NETWORK", "Cannot reach the server: {}".format(text))
		except (socket.timeout, TimeoutError):
			raise CalDavError("NETWORK", "The server did not answer in time")
		except OSError as error:
			raise CalDavError("NETWORK", "Cannot reach the server: {}".format(error.strerror or error))
		with response:
			try:
				data = response.read(MAX_RESPONSE_BYTES + 1)
			except (socket.timeout, TimeoutError):
				raise CalDavError("NETWORK", "The server did not answer in time")
			except OSError as error:
				raise CalDavError("NETWORK", "Connection failed: {}".format(error.strerror or error))
			return response.status, response.headers, data

	def request(self, method, url, body=None, headers=None, ok=(200, 201, 204, 207)):
		"""(status, headers, data, final_url) following same-server redirects; other statuses raise."""
		url = check_url(url)
		if isinstance(body, str):
			body = body.encode("utf-8")
		for _ in range(MAX_REDIRECTS + 1):
			status, response_headers, data = self._send(method, url, body, headers)
			if status in REDIRECT_CODES:
				location = response_headers.get("Location") if response_headers is not None else None
				if not location:
					raise CalDavError("PROTOCOL", "Redirect without a location for {}".format(url_path(url)))
				new_url = urllib.parse.urljoin(url, location.strip())
				check_redirect(url, new_url)
				url = check_url(new_url)
				continue
			if status not in ok:
				raise error_for_status(status, url)
			if data is not None and len(data) > MAX_RESPONSE_BYTES:
				raise CalDavError("PROTOCOL", "Response exceeds the size limit")
			return status, response_headers, data or b"", url
		raise CalDavError("PROTOCOL", "Too many redirects for {}".format(url_path(url)))

	def propfind(self, url, props, depth):
		_, _, data, final_url = self.request(
			"PROPFIND", url, propfind_body(props),
			{"Depth": str(depth), "Content-Type": "application/xml; charset=utf-8"},
			ok=(207,),
		)
		return parse_multistatus(data, final_url), final_url


#--- XML

def xml_name(ns, name):
	return "{}:{}".format(PREFIXES[ns], name)


def xml_namespaces():
	return " ".join('xmlns:{}="{}"'.format(prefix, ns) for ns, prefix in PREFIXES.items())


def propfind_body(props):
	inner = "".join("<{}/>".format(xml_name(ns, name)) for ns, name in props)
	return '<?xml version="1.0" encoding="utf-8"?>\n<d:propfind {}><d:prop>{}</d:prop></d:propfind>'.format(
		xml_namespaces(), inner)


def utc_stamp(value):
	return value.astimezone(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def calendar_query_body(start_utc, end_utc):
	return (
		'<?xml version="1.0" encoding="utf-8"?>\n'
		'<c:calendar-query {}>'
		'<d:prop><d:getetag/><c:calendar-data/></d:prop>'
		'<c:filter><c:comp-filter name="VCALENDAR"><c:comp-filter name="VEVENT">'
		'<c:time-range start="{}" end="{}"/>'
		'</c:comp-filter></c:comp-filter></c:filter>'
		'</c:calendar-query>'
	).format(xml_namespaces(), utc_stamp(start_utc), utc_stamp(end_utc))


_FORBIDDEN_XML = re.compile(rb"<!\s*(DOCTYPE|ENTITY)", re.IGNORECASE)


def parse_xml(data):
	if not data:
		raise CalDavError("PROTOCOL", "Empty XML response")
	if _FORBIDDEN_XML.search(data):
		raise CalDavError("PROTOCOL", "XML with a DOCTYPE is not accepted")
	try:
		return ET.fromstring(data)
	except ET.ParseError as error:
		raise CalDavError("PROTOCOL", "Invalid XML: {}".format(error))


_OK_STATUS = re.compile(r"\s2\d\d(\s|$)")


def parse_multistatus(data, base_url):
	"""[{"href": absolute url, "props": {tag: element}}] with the 2xx propstats of each response."""
	root = parse_xml(data)
	if root.tag != tag(NS_DAV, "multistatus"):
		raise CalDavError("PROTOCOL", "Expected a multistatus response")
	results = []
	for response in root.findall(tag(NS_DAV, "response")):
		href = response.findtext(tag(NS_DAV, "href"))
		if not href or not href.strip():
			continue
		props = {}
		for propstat in response.findall(tag(NS_DAV, "propstat")):
			status = propstat.findtext(tag(NS_DAV, "status")) or ""
			if not _OK_STATUS.search(" " + status.strip()):
				continue
			prop = propstat.find(tag(NS_DAV, "prop"))
			if prop is None:
				continue
			for child in prop:
				props[child.tag] = child
		results.append({"href": urllib.parse.urljoin(base_url, href.strip()), "props": props})
	return results


def child_href(element, base_url):
	if element is None:
		return ""
	href = element.findtext(tag(NS_DAV, "href"))
	return urllib.parse.urljoin(base_url, href.strip()) if href and href.strip() else ""


def prop_text(props, key):
	element = props.get(key)
	if element is None or element.text is None:
		return ""
	return element.text.strip()


def same_resource(a, b):
	return urllib.parse.urlsplit(a).path.rstrip("/") == urllib.parse.urlsplit(b).path.rstrip("/")


#--- discover

def normalize_color(value):
	value = (value or "").strip()
	if re.fullmatch(r"#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?", value):
		return value[:7].lower()
	if re.fullmatch(r"#[0-9a-fA-F]{3}", value):
		return "#" + "".join(c * 2 for c in value[1:]).lower()
	return ""


def privileges_writable(element):
	"""None when the server didn't say, else whether write / write-content / all is granted."""
	if element is None:
		return None
	writes = {tag(NS_DAV, "write"), tag(NS_DAV, "write-content"), tag(NS_DAV, "all")}
	for privilege in element.iter(tag(NS_DAV, "privilege")):
		for child in privilege:
			if child.tag in writes:
				return True
	return False


def calendar_from_response(entry):
	props = entry["props"]
	resourcetype = props.get(tag(NS_DAV, "resourcetype"))
	if resourcetype is None or resourcetype.find(tag(NS_CALDAV, "calendar")) is None:
		return None
	components = []
	component_set = props.get(tag(NS_CALDAV, "supported-calendar-component-set"))
	if component_set is not None:
		for comp in component_set.findall(tag(NS_CALDAV, "comp")):
			name = (comp.get("name") or "").strip().upper()
			if name:
				components.append(name)
	if components and "VEVENT" not in components:
		return None
	name = prop_text(props, tag(NS_DAV, "displayname"))
	if not name:
		name = urllib.parse.unquote(urllib.parse.urlsplit(entry["href"]).path.rstrip("/").rsplit("/", 1)[-1])
	writable = privileges_writable(props.get(tag(NS_DAV, "current-user-privilege-set")))
	ctag = ctag_of(props)
	return {
		"href": entry["href"],
		"name": name,
		"color": normalize_color(prop_text(props, tag(NS_ICAL, "calendar-color"))),
		"writable": True if writable is None else writable,
		"components": components,
		"ctag": ctag,
	}


CALENDAR_PROPS = [
	(NS_DAV, "resourcetype"),
	(NS_DAV, "displayname"),
	(NS_ICAL, "calendar-color"),
	(NS_CALDAV, "supported-calendar-component-set"),
	(NS_DAV, "current-user-privilege-set"),
	(NS_CS, "getctag"),
	(NS_DAV, "sync-token"),
]


def parse_calendar_list(entries, home_url):
	calendars = []
	for entry in entries:
		if same_resource(entry["href"], home_url):
			continue
		calendar = calendar_from_response(entry)
		if calendar is not None:
			calendars.append(calendar)
	return calendars


def find_principal(client, url):
	first_error = None
	candidates = [url]
	scheme, netloc = urllib.parse.urlsplit(url)[:2]
	well_known = "{}://{}/.well-known/caldav".format(scheme, netloc)
	if not same_resource(url, well_known):
		candidates.append(well_known)
	for candidate in candidates:
		try:
			entries, final_url = client.propfind(candidate, [(NS_DAV, "current-user-principal")], 0)
		except CalDavError as error:
			if error.kind in ("AUTH", "NETWORK"):
				raise
			first_error = first_error or error
			continue
		for entry in entries:
			principal = child_href(entry["props"].get(tag(NS_DAV, "current-user-principal")), final_url)
			if principal:
				return principal
	if first_error is not None and first_error.kind != "NOTFOUND":
		raise first_error
	raise CalDavError("NOTFOUND", "No CalDAV principal found at this address")


def discover(client, url):
	url = check_url(url)
	principal = find_principal(client, url)
	entries, final_url = client.propfind(principal, [(NS_CALDAV, "calendar-home-set")], 0)
	home = ""
	for entry in entries:
		home = child_href(entry["props"].get(tag(NS_CALDAV, "calendar-home-set")), final_url)
		if home:
			break
	if not home:
		raise CalDavError("NOTFOUND", "The principal has no calendar home")
	entries, final_url = client.propfind(home, CALENDAR_PROPS, 1)
	return {"principal": principal, "home": home, "calendars": parse_calendar_list(entries, final_url)}


#--- query

def is_recurring_component(event):
	return any(event.get(key) is not None for key in ("RRULE", "RDATE", "RECURRENCE-ID"))


def resource_is_recurring(cal):
	return any(is_recurring_component(event) for event in cal.walk("VEVENT"))


def resource_occurrences(cal, start, end):
	if icsjson.recurring_ical_events is not None:
		return list(icsjson.recurring_ical_events.of(cal).between(start, end))
	occurrences = []
	for event in cal.walk("VEVENT"):
		if not is_recurring_component(event) and icsjson.event_within(event, start, end):
			occurrences.append(event)
	return occurrences


def resource_items(href, etag, calendar_data, start, end):
	"""The widget's items (icsjson format) for one CalDAV resource's occurrences in [start, end)."""
	try:
		cal = Calendar.from_ical(calendar_data)
	except Exception as error:
		raise CalDavError("PROTOCOL", "Invalid calendar data in {}: {}".format(url_path(href), error))
	recurring = resource_is_recurring(cal)
	items = []
	for occurrence in resource_occurrences(cal, start, end):
		converted = json.loads(icsjson.events_to_json([occurrence], indent=None))["items"]
		for item in converted:
			item["caldavHref"] = href
			item["caldavEtag"] = etag
			item["caldavUid"] = icsjson.stringify(occurrence.get("UID")).strip()
			item["recurring"] = recurring
			if recurring:
				item["recurringEventId"] = item["caldavUid"]
			items.append(item)
	return items


def query_items(entries, start, end):
	items = []
	seen = set()
	for entry in entries:
		data = prop_text(entry["props"], tag(NS_CALDAV, "calendar-data"))
		if not data:
			continue
		etag = prop_text(entry["props"], tag(NS_DAV, "getetag"))
		for item in resource_items(entry["href"], etag, data, start, end):
			if item["id"] in seen:
				continue
			seen.add(item["id"])
			items.append(item)
	return items


def local_midnight_utc(day):
	return datetime.datetime.combine(day, datetime.time.min).astimezone(datetime.timezone.utc)


def ctag_of(props):
	"""A calendar's change tag in its PROPFIND props: CalendarServer's getctag, else the sync-token."""
	return prop_text(props, tag(NS_CS, "getctag")) or prop_text(props, tag(NS_DAV, "sync-token"))


def calendar_ctag(client, url):
	"""The calendar's change tag (CalendarServer's getctag, else the sync-token), "" when the server has
	neither or the request fails: the events are then always fetched."""
	try:
		entries, _ = client.propfind(url, [(NS_CS, "getctag"), (NS_DAV, "sync-token")], 0)
	except CalDavError as err:
		if err.kind in ("AUTH", "NETWORK"): # Not the events either: no second wait for them
			raise
		return ""
	for entry in entries:
		ctag = ctag_of(entry["props"])
		if ctag:
			return ctag
	return ""


def query(client, url, start, end, if_ctag="", probe_ctag=True):
	"""start/end: naive datetimes (local midnight), end exclusive. if_ctag: the calendar's change tag
	at the last fetch of the same range: unchanged, the events aren't downloaded again ({"unchanged":
	true}). The tag is read before the events, so a change meanwhile is seen next time."""
	ctag = calendar_ctag(client, url) if probe_ctag else ""
	if if_ctag and ctag and ctag == if_ctag:
		return {"unchanged": True, "ctag": ctag}
	# One day of margin on both sides: servers compare floating and all-day events in UTC.
	range_start = local_midnight_utc(start.date()) - datetime.timedelta(days=1)
	range_end = local_midnight_utc(end.date()) + datetime.timedelta(days=1)
	_, _, data, final_url = client.request(
		"REPORT", url, calendar_query_body(range_start, range_end),
		{"Depth": "1", "Content-Type": "application/xml; charset=utf-8"},
		ok=(207,),
	)
	return {"items": query_items(parse_multistatus(data, final_url), start, end), "ctag": ctag}


#--- put

def parse_when(value, key):
	if not isinstance(value, dict):
		raise CalDavError("INPUT", "{} must be an object".format(key))
	if "date" in value and value["date"] is not None:
		try:
			return datetime.date.fromisoformat(str(value["date"]))
		except ValueError:
			raise CalDavError("INPUT", "{}.date is not YYYY-MM-DD".format(key))
	if "dateTime" in value and value["dateTime"] is not None:
		text = str(value["dateTime"]).strip()
		if text.endswith("Z") or text.endswith("z"):
			text = text[:-1] + "+00:00"
		try:
			moment = datetime.datetime.fromisoformat(text)
		except ValueError:
			raise CalDavError("INPUT", "{}.dateTime is not an ISO date-time".format(key))
		zone_name = value.get("timeZone")
		if zone_name:
			import zoneinfo
			try:
				zone = zoneinfo.ZoneInfo(str(zone_name))
			except (zoneinfo.ZoneInfoNotFoundError, ValueError):
				raise CalDavError("INPUT", "Unknown time zone: {}".format(zone_name))
			if moment.tzinfo is None:
				return moment.replace(tzinfo=zone)
			return moment.astimezone(zone)
		if moment.tzinfo is not None:
			return moment.astimezone(datetime.timezone.utc)
		return moment  # floating time
	raise CalDavError("INPUT", "{} needs date or dateTime".format(key))


RECURRENCE_PROPS = ("RRULE", "RDATE", "EXDATE")


def parse_recurrence(lines):
	"""Google-style lines ("RRULE:...", "EXDATE;VALUE=DATE:...") as [(name, value)]."""
	if not isinstance(lines, list) or not all(isinstance(line, str) for line in lines):
		raise CalDavError("INPUT", "recurrence must be a list of strings")
	props = []
	for line in lines:
		line = line.strip()
		if not line:
			continue
		name = re.split(r"[:;]", line, maxsplit=1)[0].upper()
		if name not in RECURRENCE_PROPS or "\n" in line or "\r" in line:
			raise CalDavError("INPUT", "recurrence lines must be RRULE, RDATE or EXDATE")
		try:
			parsed = Event.from_ical("BEGIN:VEVENT\r\n{}\r\nEND:VEVENT\r\n".format(line))
			value = parsed.get(name)
		except Exception as error:
			raise CalDavError("INPUT", "Invalid recurrence line: {}".format(error))
		if value is None or getattr(parsed, "errors", None):
			raise CalDavError("INPUT", "Invalid recurrence line: {}".format(line))
		for item in (value if isinstance(value, list) else [value]):
			props.append((name, item))
	return props


def set_recurrence(event, lines):
	"""Replace the event's RRULE / RDATE / EXDATE (an empty list makes it non-recurring)."""
	props = parse_recurrence(lines)
	for name in RECURRENCE_PROPS:
		event.pop(name, None)
	for name, value in props:
		event.add(name, value)


def is_all_day(value):
	return isinstance(value, datetime.date) and not isinstance(value, datetime.datetime)


def set_text(event, key, value):
	if value is None:
		return
	if not isinstance(value, str):
		raise CalDavError("INPUT", "{} must be a string".format(key.lower()))
	event.pop(key, None)
	if value != "" or key == "SUMMARY":
		event.add(key, value)


def set_date(event, key, value):
	event.pop(key, None)
	event.add(key, value)


def apply_event_fields(event, data):
	"""Change only the given fields of a VEVENT (summary, location, description, start, end)."""
	set_text(event, "SUMMARY", data.get("summary"))
	set_text(event, "LOCATION", data.get("location"))
	set_text(event, "DESCRIPTION", data.get("description"))
	if data.get("recurrence") is not None:
		set_recurrence(event, data["recurrence"])
	start = parse_when(data["start"], "start") if data.get("start") is not None else None
	end = parse_when(data["end"], "end") if data.get("end") is not None else None
	if start is not None and end is not None:
		if is_all_day(start) != is_all_day(end):
			raise CalDavError("INPUT", "start and end must both be dates or both date-times")
		if icsjson.ensure_date_time(end) < icsjson.ensure_date_time(start) or (is_all_day(start) and end <= start):
			raise CalDavError("INPUT", "end is before start")
	if start is not None:
		old_start = icsjson.get_event_date(event, "DTSTART")
		if end is None and event.get("DTEND") is not None and old_start is not None:
			# Keep the duration when only the start moves (and the kind of value matches).
			old_end = icsjson.get_event_date(event, "DTEND")
			if is_all_day(old_start) == is_all_day(start) and old_end is not None:
				end = start + (old_end - old_start)
		set_date(event, "DTSTART", start)
	if end is not None:
		event.pop("DURATION", None)
		set_date(event, "DTEND", end)


def now_utc():
	return datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0)


def add_timezones(cal):
	if hasattr(cal, "add_missing_timezones"):
		try:
			cal.add_missing_timezones()
		except Exception:
			pass


def build_new_calendar(data, uid=None, stamp=None):
	for key in ("summary", "start", "end"):
		if data.get(key) is None:
			raise CalDavError("INPUT", "A new event needs {}".format(key))
	uid = uid or str(uuid.uuid4())
	stamp = stamp or now_utc()
	cal = Calendar()
	cal.add("PRODID", PRODID)
	cal.add("VERSION", "2.0")
	event = Event()
	event.add("UID", uid)
	event.add("DTSTAMP", stamp)
	event.add("CREATED", stamp)
	event.add("LAST-MODIFIED", stamp)
	apply_event_fields(event, data)
	cal.add_component(event)
	add_timezones(cal)
	return uid, cal.to_ical()


def master_event(cal):
	for event in cal.walk("VEVENT"):
		if event.get("RECURRENCE-ID") is None:
			return event
	return None


def build_updated_calendar(existing, data, stamp=None):
	try:
		cal = Calendar.from_ical(existing)
	except Exception as error:
		raise CalDavError("PROTOCOL", "Invalid calendar data on the server: {}".format(error))
	event = master_event(cal)
	if event is None:
		raise CalDavError("PROTOCOL", "The resource has no master event")
	stamp = stamp or now_utc()
	apply_event_fields(event, data)
	for key in ("DTSTAMP", "LAST-MODIFIED"):
		event.pop(key, None)
		event.add(key, stamp)
	try:
		sequence = int(str(event.get("SEQUENCE", 0)))
	except ValueError:
		sequence = 0
	event.pop("SEQUENCE", None)
	event.add("SEQUENCE", sequence + 1)
	add_timezones(cal)
	uid = icsjson.stringify(event.get("UID")).strip()
	return uid, cal.to_ical()


def quote_etag(etag):
	etag = (etag or "").strip()
	if not etag:
		raise CalDavError("INPUT", "--etag is empty")
	if etag.startswith('"') or etag.startswith("W/"):
		return etag
	return '"{}"'.format(etag)


def collection_url(url):
	return url if url.endswith("/") else url + "/"


def fetch_etag(client, href):
	entries, _ = client.propfind(href, [(NS_DAV, "getetag")], 0)
	for entry in entries:
		etag = prop_text(entry["props"], tag(NS_DAV, "getetag"))
		if etag:
			return etag
	return ""


def put_calendar(client, href, body, headers):
	headers = dict(headers)
	headers["Content-Type"] = "text/calendar; charset=utf-8"
	_, response_headers, _, final_url = client.request("PUT", href, body, headers, ok=(200, 201, 204))
	etag = (response_headers.get("ETag") or "").strip() if response_headers is not None else ""
	if not etag:
		etag = fetch_etag(client, final_url)
	return final_url, etag


def put_event(client, cal_url, data, href=None, etag=None):
	if not isinstance(data, dict):
		raise CalDavError("INPUT", "The event must be a JSON object")
	cal_url = check_url(cal_url)
	if href:
		href = check_url(urllib.parse.urljoin(collection_url(cal_url), href))
		match = quote_etag(etag)
		_, _, existing, href = client.request("GET", href, ok=(200,))
		uid, body = build_updated_calendar(existing, data)
		final_url, new_etag = put_calendar(client, href, body, {"If-Match": match})
	else:
		uid, body = build_new_calendar(data)
		target = collection_url(cal_url) + resource_name(uid) + ".ics"
		final_url, new_etag = put_calendar(client, target, body, {"If-None-Match": "*"})
	return {"href": final_url, "etag": new_etag, "uid": uid}


def delete_event(client, href, etag):
	client.request("DELETE", href, None, {"If-Match": quote_etag(etag)}, ok=(200, 202, 204))
	return {"ok": True}


#--- import

def resource_name(uid):
	"""A safe file name for a UID ("<name>.ics" on the server)."""
	if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,99}", uid) and not uid.endswith("."):
		return uid
	digest = hashlib.sha1(uid.encode("utf-8", "ignore")).hexdigest()[:12]
	safe = re.sub(r"[^A-Za-z0-9._-]+", "_", uid).strip("._-")[:60]
	return "{}-{}".format(safe, digest) if safe else digest


def used_tzids(component):
	tzids = []
	for part in component.walk():
		for _, value in part.property_items(recursive=False):
			params = getattr(value, "params", None)
			if params is None:
				continue
			tzid = params.get("TZID")
			if tzid and str(tzid) not in tzids:
				tzids.append(str(tzid))
	return tzids


def group_import(cal):
	"""([(uid, Calendar)], failed): one VCALENDAR per UID with its overrides and VTIMEZONEs."""
	timezones = {}
	for tz in cal.walk("VTIMEZONE"):
		timezones[str(tz.get("TZID", ""))] = tz
	groups = {}
	failed = []
	for event in cal.walk("VEVENT"):
		uid = icsjson.stringify(event.get("UID")).strip()
		if not uid:
			start, end = icsjson.get_event_bounds(event)
			if start is None:
				failed.append({"uid": "", "error": "event without UID and DTSTART"})
				continue
			uid = icsjson.build_event_uid(event, start, end)
			event.add("UID", uid)
		groups.setdefault(uid, []).append(event)
	result = []
	for uid, events in groups.items():
		out = Calendar()
		out.add("PRODID", PRODID)
		out.add("VERSION", "2.0")
		if cal.get("CALSCALE") is not None:
			out.add("CALSCALE", cal.get("CALSCALE"))
		tzids = []
		for event in events:
			for tzid in used_tzids(event):
				if tzid not in tzids:
					tzids.append(tzid)
		for tzid in tzids:
			if tzid in timezones:
				out.add_component(timezones[tzid])
		for event in events:
			out.add_component(event)
		add_timezones(out)
		result.append((uid, out))
	return result, failed


def import_file(client, cal_url, path):
	try:
		cal = icsjson.read_import_file(path)
	except ValueError as error:
		raise CalDavError("INPUT", str(error))
	except OSError as error:
		raise CalDavError("INPUT", "Cannot read the file: {}".format(error.strerror or error))
	cal_url = check_url(cal_url)
	groups, failed = group_import(cal)
	imported = 0
	for uid, group in groups:
		target = collection_url(cal_url) + resource_name(uid) + ".ics"
		try:
			client.request("PUT", target, group.to_ical(), {
				"Content-Type": "text/calendar; charset=utf-8",
				"If-None-Match": "*",
			}, ok=(200, 201, 204))
		except CalDavError as error:
			if error.kind in ("AUTH", "NETWORK"):
				raise
			failed.append({"uid": uid, "error": "exists" if error.kind == "CONFLICT" else error.line()})
			continue
		imported += 1
	return {"imported": imported, "failed": failed}


#--- command line

class ArgumentParser(argparse.ArgumentParser):
	def error(self, message):
		raise CalDavError("INPUT", message)


def parse_day(value):
	try:
		return icsjson.parse_date(value)
	except ValueError:
		raise CalDavError("INPUT", "Not a date (YYYY-MM-DD): {}".format(value))


def build_parser():
	parser = ArgumentParser(prog="caldav.py", description="CalDAV helper for Event Calendar NG")
	sub = parser.add_subparsers(dest="command", required=True)

	def common(cmd):
		cmd.add_argument("--account", default="", help="Keyring account id (scope caldav-account, key password)")
		cmd.add_argument("--user", default="", help="User name")
		cmd.add_argument("--password-stdin", action="store_true",
			help="Read the password from the first line of stdin (tests / command-line use)")

	cmd = sub.add_parser("discover")
	cmd.add_argument("--url", required=True)
	common(cmd)

	cmd = sub.add_parser("query")
	cmd.add_argument("--url", required=True)
	cmd.add_argument("--if-ctag", default="", help="The change tag of the last fetch: unchanged, no events are downloaded")
	cmd.add_argument("--no-ctag", action="store_true", help="Don't ask for the change tag (the server has none)")
	cmd.add_argument("start")
	cmd.add_argument("end")
	common(cmd)

	cmd = sub.add_parser("put")
	cmd.add_argument("--url", required=True)
	cmd.add_argument("--href", default="")
	cmd.add_argument("--etag", default="")
	cmd.add_argument("--event-b64", default=None, help="The event JSON as base64 of UTF-8 (else read from stdin)")
	common(cmd)

	cmd = sub.add_parser("delete")
	cmd.add_argument("--href", required=True)
	cmd.add_argument("--etag", required=True)
	common(cmd)

	cmd = sub.add_parser("import")
	cmd.add_argument("--url", required=True)
	cmd.add_argument("--file", required=True)
	common(cmd)
	return parser


def keyring_password(account):
	import secret_store
	attributes = secret_store.build_attributes(argparse.Namespace(scope=SECRET_SCOPE, key=SECRET_KEY, account_id=account))
	found, value, error = secret_store.lookup_secret_detailed(attributes)
	if found and value:
		return value
	if error:
		raise CalDavError("KEYRING", "The keyring could not be read: {}".format(error))
	raise CalDavError("AUTH", "No password stored for this account")


def read_password(args, stdin):
	if args.password_stdin:
		line = stdin.readline()
		return line.rstrip("\r\n")
	if not args.account:
		raise CalDavError("INPUT", "--account is required")
	return keyring_password(args.account)


def run(args, stdin):
	if args.command == "query":
		start = parse_day(args.start)
		end = parse_day(args.end)
		if end <= start:
			raise CalDavError("INPUT", "END must be after START")
	if args.command == "put" and bool(args.href) != bool(args.etag):
		raise CalDavError("INPUT", "--href and --etag go together")
	if not args.user:
		raise CalDavError("INPUT", "--user is required")
	password = read_password(args, stdin)
	run.password = password
	client = Client(args.user, password)

	if args.command == "discover":
		return discover(client, args.url)
	if args.command == "query":
		return query(client, args.url, start, end, args.if_ctag, not args.no_ctag)
	if args.command == "put":
		try:
			if args.event_b64 is not None:
				data = json.loads(base64.b64decode(args.event_b64, validate=True).decode("utf-8"))
			else:
				data = json.loads(stdin.read())
		except (ValueError, UnicodeDecodeError) as error:
			raise CalDavError("INPUT", "The event is not valid (base64) JSON: {}".format(error))
		return put_event(client, args.url, data, args.href or None, args.etag or None)
	if args.command == "delete":
		return delete_event(client, args.href, args.etag)
	if args.command == "import":
		return import_file(client, args.url, args.file)
	raise CalDavError("INPUT", "Unknown command")


run.password = ""


def scrub(text, secrets):
	for secret in secrets:
		if secret:
			text = text.replace(secret, "***")
	return text


def main(argv=None, stdin=None, stdout=None, stderr=None):
	stdin = stdin if stdin is not None else sys.stdin
	stdout = stdout if stdout is not None else sys.stdout
	stderr = stderr if stderr is not None else sys.stderr
	run.password = ""
	if MISSING_MODULE:
		stderr.write("DEPS: The Python module {} is missing (icalendar, recurring-ical-events)\n".format(MISSING_MODULE))
		return 1
	try:
		args = build_parser().parse_args(argv)
		result = run(args, stdin)
	except CalDavError as error:
		line = error.line()
	except KeyboardInterrupt:
		line = "NETWORK: Interrupted"
	except Exception as error:  # never a traceback (it could show request details)
		line = "PROTOCOL: {}: {}".format(type(error).__name__, error)
	else:
		stdout.write(json.dumps(result, indent=None))
		stdout.write("\n")
		return 0
	line = scrub(" ".join(line.split()), [run.password])
	stderr.write(line + "\n")
	return 1


if __name__ == "__main__":
	sys.exit(main())
