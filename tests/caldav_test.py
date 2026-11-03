from __future__ import annotations

import base64
import datetime
import importlib.util
import io
import json
import pathlib
import sys
import tempfile
import unittest
from unittest import mock

SCRIPTS_DIR = pathlib.Path(__file__).parents[1] / "package/contents/scripts"
sys.path.insert(0, str(SCRIPTS_DIR))
SPEC = importlib.util.spec_from_file_location("eventcalendar_caldav", SCRIPTS_DIR / "caldav.py")
caldav = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(caldav)
icsjson = caldav.icsjson

from icalendar import Calendar  # noqa: E402

HAS_RIE = icsjson.recurring_ical_events is not None
BASE = "https://cloud.example.com"


class FakeClient(caldav.Client):
	"""A Client whose _send answers from a list of (status, headers, body) and records requests."""

	def __init__(self, responses):
		super().__init__("user", "s3cret")
		self.responses = list(responses)
		self.sent = []

	def _send(self, method, url, body, headers):
		self.sent.append((method, url, body, dict(headers or {})))
		status, headers, data = self.responses.pop(0)
		return status, headers, data.encode("utf-8") if isinstance(data, str) else data


def ms(*responses):
	return '<?xml version="1.0"?><d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav" ' \
		'xmlns:cs="http://calendarserver.org/ns/" xmlns:ical="http://apple.com/ns/ical/" ' \
		'xmlns:oc="http://owncloud.org/ns">' + "".join(responses) + "</d:multistatus>"


def resp(href, props, status="HTTP/1.1 200 OK", missing=""):
	extra = ""
	if missing:
		extra = "<d:propstat><d:prop>{}</d:prop><d:status>HTTP/1.1 404 Not Found</d:status></d:propstat>".format(missing)
	return "<d:response><d:href>{}</d:href><d:propstat><d:prop>{}</d:prop><d:status>{}</d:status></d:propstat>{}</d:response>".format(
		href, props, status, extra)


def vcal(body):
	return "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:test\r\n" + body + "END:VCALENDAR\r\n"


def xml_escape(text):
	return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


PUBLIC = [("93.184.216.34",)]


def fake_resolve(host):
	return {
		"cloud.example.com": ["93.184.216.34"],
		"public.example.com": ["93.184.216.34"],
		"nas.lan": ["192.168.1.10"],
		"ula.lan": ["fd00::5"],
		"mixed.example.com": ["192.168.1.10", "93.184.216.34"],
	}.get(host, [host])


NEXTCLOUD_HOME = ms(
	resp("/remote.php/dav/calendars/user/", "<d:resourcetype><d:collection/></d:resourcetype>"),
	resp("/remote.php/dav/calendars/user/personal/",
		"<d:resourcetype><d:collection/><c:calendar/></d:resourcetype>"
		"<d:displayname>Personal</d:displayname>"
		"<ical:calendar-color>#0082C9FF</ical:calendar-color>"
		"<c:supported-calendar-component-set><c:comp name=\"VEVENT\"/><c:comp name=\"VTODO\"/></c:supported-calendar-component-set>"
		"<d:current-user-privilege-set><d:privilege><d:read/></d:privilege><d:privilege><d:write/></d:privilege></d:current-user-privilege-set>"
		"<cs:getctag>http://sabre.io/ns/sync/42</cs:getctag>"),
	resp("/remote.php/dav/calendars/user/tasks/",
		"<d:resourcetype><d:collection/><c:calendar/></d:resourcetype>"
		"<d:displayname>Tasks</d:displayname>"
		"<c:supported-calendar-component-set><c:comp name=\"VTODO\"/></c:supported-calendar-component-set>"),
	resp("/remote.php/dav/calendars/user/shared_by_bob/",
		"<d:resourcetype><d:collection/><c:calendar/></d:resourcetype>"
		"<d:displayname>Bob's</d:displayname>"
		"<ical:calendar-color>#ff0000</ical:calendar-color>"
		"<d:current-user-privilege-set><d:privilege><d:read/></d:privilege><d:privilege><d:read-free-busy/></d:privilege></d:current-user-privilege-set>"),
	resp("/remote.php/dav/calendars/user/inbox/", "<d:resourcetype><d:collection/><c:schedule-inbox/></d:resourcetype>"),
)

RADICALE_HOME = ms(
	resp("/test/", "<d:resourcetype><d:principal/><d:collection/></d:resourcetype>"),
	resp("/test/cal/",
		"<d:resourcetype><c:calendar/><d:collection/></d:resourcetype>"
		"<ical:calendar-color>#ABC</ical:calendar-color>"
		"<d:current-user-privilege-set><d:privilege><d:all/></d:privilege></d:current-user-privilege-set>"
		"<cs:getctag>\"abc\"</cs:getctag>",
		missing="<d:displayname/>"),
)


@mock.patch.object(caldav, "resolve_host", fake_resolve)
class UrlRuleTests(unittest.TestCase):
	def test_https_is_accepted(self):
		self.assertEqual(caldav.check_url("https://cloud.example.com/remote.php/dav"), "https://cloud.example.com/remote.php/dav")

	def test_http_on_loopback_and_private_is_accepted(self):
		self.assertEqual(caldav.check_url("http://127.0.0.1:5232/"), "http://127.0.0.1:5232/")
		self.assertEqual(caldav.check_url("http://nas.lan/dav"), "http://nas.lan/dav")
		self.assertEqual(caldav.check_url("http://ula.lan/dav"), "http://ula.lan/dav")
		self.assertEqual(caldav.check_url("http://[::1]:8080/x"), "http://[::1]:8080/x")

	def test_http_on_public_host_is_refused(self):
		for url in ("http://public.example.com/dav", "http://mixed.example.com/dav"):
			with self.assertRaises(caldav.CalDavError) as ctx:
				caldav.check_url(url)
			self.assertEqual(ctx.exception.kind, "INPUT")
			self.assertIn("http only for local servers", ctx.exception.message)

	def test_other_schemes_and_userinfo(self):
		for url in ("ftp://cloud.example.com/", "file:///etc/passwd", "", "https:///nohost"):
			with self.assertRaises(caldav.CalDavError) as ctx:
				caldav.check_url(url)
			self.assertEqual(ctx.exception.kind, "INPUT")
		self.assertEqual(caldav.check_url("https://me:pw@cloud.example.com/dav"), "https://cloud.example.com/dav")

	def test_redirect_to_other_host_is_refused(self):
		client = FakeClient([(301, {"Location": "https://evil.example.org/dav/"}, "")])
		with self.assertRaises(caldav.CalDavError) as ctx:
			client.request("PROPFIND", BASE + "/dav/", "<x/>", ok=(207,))
		self.assertEqual(ctx.exception.kind, "PROTOCOL")
		self.assertNotIn("evil.example.org", ctx.exception.message)

	def test_redirect_to_other_scheme_is_refused(self):
		client = FakeClient([(301, {"Location": "http://cloud.example.com/dav/"}, "")])
		with self.assertRaises(caldav.CalDavError) as ctx:
			client.request("GET", BASE + "/dav/")
		self.assertEqual(ctx.exception.kind, "PROTOCOL")

	def test_same_host_redirect_keeps_method_and_body(self):
		client = FakeClient([
			(301, {"Location": "/remote.php/dav/"}, ""),
			(308, {"Location": "https://cloud.example.com/remote.php/dav/x/"}, ""),
			(207, {}, ms()),
		])
		_, _, _, final = client.request("PROPFIND", BASE + "/.well-known/caldav", "<body/>", {"Depth": "0"}, ok=(207,))
		self.assertEqual(final, BASE + "/remote.php/dav/x/")
		self.assertEqual([s[0] for s in client.sent], ["PROPFIND"] * 3)
		self.assertTrue(all(s[2] == b"<body/>" for s in client.sent))

	def test_too_many_redirects(self):
		client = FakeClient([(302, {"Location": "/a"}, "")] * 10)
		with self.assertRaises(caldav.CalDavError) as ctx:
			client.request("GET", BASE + "/a")
		self.assertEqual(ctx.exception.kind, "PROTOCOL")
		self.assertEqual(len(client.sent), caldav.MAX_REDIRECTS + 1)


@mock.patch.object(caldav, "resolve_host", fake_resolve)
class ErrorKindTests(unittest.TestCase):
	def test_status_mapping(self):
		for status, kind in ((401, "AUTH"), (403, "AUTH"), (404, "NOTFOUND"), (410, "NOTFOUND"),
				(412, "CONFLICT"), (500, "PROTOCOL"), (409, "PROTOCOL")):
			client = FakeClient([(status, {}, "")])
			with self.assertRaises(caldav.CalDavError) as ctx:
				client.request("GET", BASE + "/dav/x.ics", ok=(200,))
			self.assertEqual(ctx.exception.kind, kind, status)
			self.assertNotIn("cloud.example.com", ctx.exception.message)

	def test_network_errors(self):
		import urllib.error
		client = caldav.Client("u", "p")
		with mock.patch.object(client._opener, "open", side_effect=urllib.error.URLError(ConnectionRefusedError(111, "Connection refused"))):
			with self.assertRaises(caldav.CalDavError) as ctx:
				client.request("GET", BASE + "/")
		self.assertEqual(ctx.exception.kind, "NETWORK")
		with mock.patch.object(client._opener, "open", side_effect=TimeoutError()):
			with self.assertRaises(caldav.CalDavError) as ctx:
				client.request("GET", BASE + "/")
		self.assertEqual(ctx.exception.kind, "NETWORK")

	def test_bad_xml_and_doctype(self):
		for data in (b"not xml", b"<?xml version='1.0'?><!DOCTYPE x [<!ENTITY a 'b'>]><x>&a;</x>", b"", b"<a xmlns='DAV:'/>"):
			with self.assertRaises(caldav.CalDavError) as ctx:
				caldav.parse_multistatus(data, BASE)
			self.assertEqual(ctx.exception.kind, "PROTOCOL")

	def test_cli_errors_are_one_line_and_never_show_the_password(self):
		cases = [
			(["query", "--url", BASE, "--user", "u", "--password-stdin", "2026-01-01"], "INPUT"),
			(["query", "--url", BASE, "--user", "u", "--password-stdin", "2026-13-01", "2026-01-02"], "INPUT"),
			(["nope"], "INPUT"),
			(["discover", "--url", "http://public.example.com/", "--user", "u", "--password-stdin"], "INPUT"),
			(["delete", "--href", BASE + "/x.ics", "--etag", "e", "--user", "u"], "INPUT"),  # no --account
		]
		for argv, kind in cases:
			out, err = io.StringIO(), io.StringIO()
			code = caldav.main(argv, stdin=io.StringIO("hunter2\n"), stdout=out, stderr=err)
			self.assertNotEqual(code, 0)
			self.assertEqual(out.getvalue(), "")
			lines = err.getvalue().splitlines()
			self.assertEqual(len(lines), 1, lines)
			self.assertTrue(lines[0].startswith(kind + ": "), lines[0])

		class Boom(caldav.Client):
			def _send(self, method, url, body, headers):
				raise RuntimeError("leak hunter2 here")
		err = io.StringIO()
		with mock.patch.object(caldav, "Client", Boom):
			code = caldav.main(["discover", "--url", BASE, "--user", "u", "--password-stdin"],
				stdin=io.StringIO("hunter2\n"), stdout=io.StringIO(), stderr=err)
		self.assertEqual(code, 1)
		self.assertNotIn("hunter2", err.getvalue())
		self.assertTrue(err.getvalue().startswith("PROTOCOL: "))

	def test_keyring_lookup_attributes(self):
		with mock.patch("secret_store.lookup_secret_detailed", return_value=(True, "pw", "")) as lookup:
			self.assertEqual(caldav.keyring_password("acc_1"), "pw")
		lookup.assert_called_once_with([
			("app", "plasma-applet-eventcalendar"), ("scope", "caldav-account"),
			("key", "password"), ("account_id", "acc_1"),
		])
		with mock.patch("secret_store.lookup_secret_detailed", return_value=(False, "", "")):
			with self.assertRaises(caldav.CalDavError) as ctx:
				caldav.keyring_password("acc_1")
		self.assertEqual(ctx.exception.kind, "AUTH")


@mock.patch.object(caldav, "resolve_host", fake_resolve)
class DiscoveryTests(unittest.TestCase):
	def test_nextcloud_like_discovery_via_well_known(self):
		client = FakeClient([
			(404, {}, ""),  # the entered URL is not DAV
			(301, {"Location": "/remote.php/dav/"}, ""),
			(207, {}, ms(resp("/remote.php/dav/", "<d:current-user-principal><d:href>/remote.php/dav/principals/users/user/</d:href></d:current-user-principal>"))),
			(207, {}, ms(resp("/remote.php/dav/principals/users/user/", "<c:calendar-home-set><d:href>/remote.php/dav/calendars/user/</d:href></c:calendar-home-set>"))),
			(207, {}, NEXTCLOUD_HOME),
		])
		result = caldav.discover(client, BASE + "/index.php")
		self.assertEqual(result["principal"], BASE + "/remote.php/dav/principals/users/user/")
		self.assertEqual(result["home"], BASE + "/remote.php/dav/calendars/user/")
		self.assertEqual(client.sent[1][1], BASE + "/.well-known/caldav")
		self.assertEqual(client.sent[-1][3]["Depth"], "1")
		self.assertEqual(client.sent[3][3]["Depth"], "0")
		cals = result["calendars"]
		self.assertEqual([c["name"] for c in cals], ["Personal", "Bob's"])
		self.assertEqual(cals[0], {
			"href": BASE + "/remote.php/dav/calendars/user/personal/",
			"name": "Personal",
			"color": "#0082c9",
			"writable": True,
			"components": ["VEVENT", "VTODO"],
			"ctag": "http://sabre.io/ns/sync/42",
		})
		self.assertFalse(cals[1]["writable"])
		self.assertEqual(cals[1]["color"], "#ff0000")
		self.assertEqual(cals[1]["components"], [])

	def test_radicale_like_discovery_on_entered_url(self):
		client = FakeClient([
			(207, {}, ms(resp("/", "<d:current-user-principal><d:href>/test/</d:href></d:current-user-principal>"))),
			(207, {}, ms(resp("/test/", "<c:calendar-home-set><d:href>/test/</d:href></c:calendar-home-set>"))),
			(207, {}, RADICALE_HOME),
		])
		result = caldav.discover(client, "https://dav.example.com/")
		self.assertEqual(len(client.sent), 3)
		cal = result["calendars"][0]
		self.assertEqual(cal["href"], "https://dav.example.com/test/cal/")
		self.assertEqual(cal["name"], "cal")  # no displayname: the last path segment
		self.assertEqual(cal["color"], "#aabbcc")
		self.assertTrue(cal["writable"])
		self.assertEqual(cal["ctag"], '"abc"')

	def test_auth_failure_is_not_retried(self):
		client = FakeClient([(401, {}, "")])
		with self.assertRaises(caldav.CalDavError) as ctx:
			caldav.discover(client, BASE + "/")
		self.assertEqual(ctx.exception.kind, "AUTH")
		self.assertEqual(len(client.sent), 1)

	def test_no_principal(self):
		client = FakeClient([(207, {}, ms(resp("/", "<d:displayname>x</d:displayname>"))), (404, {}, "")])
		with self.assertRaises(caldav.CalDavError) as ctx:
			caldav.discover(client, BASE + "/")
		self.assertEqual(ctx.exception.kind, "NOTFOUND")

	def test_color_normalization(self):
		self.assertEqual(caldav.normalize_color("#FF00AA80"), "#ff00aa")
		self.assertEqual(caldav.normalize_color("#123456"), "#123456")
		self.assertEqual(caldav.normalize_color("red"), "")
		self.assertEqual(caldav.normalize_color(""), "")

	def test_missing_privileges_mean_writable(self):
		entries = caldav.parse_multistatus(ms(resp("/h/c/", "<d:resourcetype><c:calendar/></d:resourcetype>")).encode(), BASE)
		self.assertTrue(caldav.parse_calendar_list(entries, BASE + "/h/")[0]["writable"])
		entries = caldav.parse_multistatus(ms(resp("/h/c/", "<d:resourcetype><c:calendar/></d:resourcetype>"
			"<d:current-user-privilege-set><d:privilege><d:write-content/></d:privilege></d:current-user-privilege-set>")).encode(), BASE)
		self.assertTrue(caldav.parse_calendar_list(entries, BASE + "/h/")[0]["writable"])


SINGLE = vcal(
	"BEGIN:VEVENT\r\nUID:single-1\r\nDTSTAMP:20261101T000000Z\r\nDTSTART:20261103T100000Z\r\n"
	"DTEND:20261103T110000Z\r\nSUMMARY:Standup\r\nLOCATION:Room 1\r\nEND:VEVENT\r\n")
ALLDAY = vcal(
	"BEGIN:VEVENT\r\nUID:allday-1\r\nDTSTAMP:20261101T000000Z\r\nDTSTART;VALUE=DATE:20261104\r\n"
	"DTEND;VALUE=DATE:20261106\r\nSUMMARY:Trip\r\nEND:VEVENT\r\n")
ZONED = vcal(
	"BEGIN:VEVENT\r\nUID:zoned-1\r\nDTSTAMP:20261101T000000Z\r\nDTSTART;TZID=America/New_York:20261105T090000\r\n"
	"DTEND;TZID=America/New_York:20261105T093000\r\nSUMMARY:NY call\r\nEND:VEVENT\r\n")
RECURRING = vcal(
	"BEGIN:VEVENT\r\nUID:weekly-1\r\nDTSTAMP:20261101T000000Z\r\nDTSTART:20261102T080000Z\r\n"
	"DTEND:20261102T090000Z\r\nRRULE:FREQ=DAILY;COUNT=10\r\nEXDATE:20261104T080000Z\r\nSUMMARY:Daily\r\nEND:VEVENT\r\n"
	"BEGIN:VEVENT\r\nUID:weekly-1\r\nDTSTAMP:20261101T000000Z\r\nRECURRENCE-ID:20261103T080000Z\r\n"
	"DTSTART:20261103T120000Z\r\nDTEND:20261103T130000Z\r\nSUMMARY:Daily (moved)\r\nEND:VEVENT\r\n")


def report_response(*resources):
	return ms(*[
		resp(href, "<d:getetag>{}</d:getetag><c:calendar-data>{}</c:calendar-data>".format(etag, xml_escape(data)))
		for href, etag, data in resources
	])


def ctag_response(ctag):
	return ms(resp("/cal/", "<cs:getctag>{}</cs:getctag>".format(xml_escape(ctag))))


@mock.patch.object(caldav, "resolve_host", fake_resolve)
class CtagTests(unittest.TestCase):
	start = datetime.datetime(2026, 11, 2)
	end = datetime.datetime(2026, 11, 9)

	def test_unchanged_skips_the_events(self):
		client = FakeClient([(207, {}, ctag_response("tag-7"))])
		result = caldav.query(client, BASE + "/cal/", self.start, self.end, "tag-7")
		self.assertEqual(result, {"unchanged": True, "ctag": "tag-7"})
		self.assertEqual([m for m, _, _, _ in client.sent], ["PROPFIND"], "no REPORT")

	def test_changed_fetches_with_the_new_tag(self):
		client = FakeClient([(207, {}, ctag_response("tag-8")), (207, {}, report_response(("/cal/single-1.ics", '"e1"', SINGLE)))])
		result = caldav.query(client, BASE + "/cal/", self.start, self.end, "tag-7")
		self.assertEqual(result["ctag"], "tag-8")
		self.assertEqual(len(result["items"]), 1)

	def test_no_tag_on_the_server_always_fetches(self):
		client = FakeClient([(207, {}, ms(resp("/cal/", "<d:displayname>x</d:displayname>"))), (207, {}, report_response())])
		result = caldav.query(client, BASE + "/cal/", self.start, self.end, "")
		self.assertEqual(result["ctag"], "")
		self.assertEqual([m for m, _, _, _ in client.sent], ["PROPFIND", "REPORT"])

	def test_tag_request_failing_still_fetches(self):
		client = FakeClient([(500, {}, "oops"), (207, {}, report_response())])
		result = caldav.query(client, BASE + "/cal/", self.start, self.end, "tag-7")
		self.assertEqual(result, {"items": [], "ctag": ""})


@mock.patch.object(caldav, "resolve_host", fake_resolve)
class QueryTests(unittest.TestCase):
	start = datetime.datetime(2026, 11, 2)
	end = datetime.datetime(2026, 11, 9)

	def run_query(self, *resources):
		client = FakeClient([(207, {}, ctag_response('"c1"')), (207, {}, report_response(*resources))])
		result = caldav.query(client, BASE + "/cal/", self.start, self.end)
		self.assertEqual(result["ctag"], '"c1"')
		method, url, body, headers = client.sent[1]
		self.assertEqual((method, url, headers["Depth"]), ("REPORT", BASE + "/cal/", "1"))
		self.assertIn(b'comp-filter name="VEVENT"', body)
		self.assertIn(b"<c:time-range start=", body)
		return result["items"]

	def test_single_event(self):
		items = self.run_query(("/cal/single-1.ics", '"e1"', SINGLE))
		self.assertEqual(len(items), 1)
		item = items[0]
		expected = json.loads(icsjson.events_to_json(Calendar.from_ical(SINGLE).walk("VEVENT"), indent=None))["items"][0]
		for key, value in expected.items():
			self.assertEqual(item[key], value)
		self.assertEqual(item["summary"], "Standup")
		self.assertEqual(item["location"], "Room 1")
		self.assertEqual(item["caldavHref"], BASE + "/cal/single-1.ics")
		self.assertEqual(item["caldavEtag"], '"e1"')
		self.assertEqual(item["caldavUid"], "single-1")
		self.assertFalse(item["recurring"])
		self.assertNotIn("recurringEventId", item)

	def test_all_day_event(self):
		item = self.run_query(("/cal/allday-1.ics", '"e2"', ALLDAY))[0]
		self.assertEqual(item["start"], {"date": "2026-11-04"})
		self.assertEqual(item["end"], {"date": "2026-11-06"})

	def test_timezone_event(self):
		item = self.run_query(("/cal/zoned-1.ics", '"e3"', ZONED))[0]
		self.assertEqual(item["start"], {"dateTime": "2026-11-05T09:00:00-05:00"})
		self.assertEqual(item["end"], {"dateTime": "2026-11-05T09:30:00-05:00"})

	def test_out_of_range_event_is_dropped(self):
		later = SINGLE.replace("20261103", "20261203")
		self.assertEqual(self.run_query(("/cal/single-1.ics", '"e1"', later)), [])

	@unittest.skipUnless(HAS_RIE, "recurring-ical-events is not installed")
	def test_recurring_expansion(self):
		items = self.run_query(("/cal/weekly-1.ics", '"e4"', RECURRING))
		starts = [i["start"]["dateTime"] for i in items]
		# 2..8 Nov, minus the EXDATE on the 4th; the 3rd moved to 12:00.
		self.assertEqual(len(items), 6, starts)
		self.assertIn("2026-11-03T12:00:00+00:00", starts)
		self.assertNotIn("2026-11-04T08:00:00+00:00", starts)
		self.assertEqual(len({i["id"] for i in items}), 6)
		for item in items:
			self.assertTrue(item["recurring"])
			self.assertEqual(item["caldavUid"], "weekly-1")
			self.assertEqual(item["recurringEventId"], "weekly-1")
			self.assertEqual(item["caldavHref"], BASE + "/cal/weekly-1.ics")
		moved = [i for i in items if i["start"]["dateTime"].startswith("2026-11-03")][0]
		self.assertEqual(moved["summary"], "Daily (moved)")
		# Stable ids: the same query gives the same ids.
		again = self.run_query(("/cal/weekly-1.ics", '"e4"', RECURRING))
		self.assertEqual([i["id"] for i in items], [i["id"] for i in again])

	def test_without_recurring_ical_events_only_plain_events(self):
		with mock.patch.object(icsjson, "recurring_ical_events", None):
			items = self.run_query(("/cal/weekly-1.ics", '"e4"', RECURRING), ("/cal/single-1.ics", '"e1"', SINGLE))
		self.assertEqual([i["caldavUid"] for i in items], ["single-1"])


@mock.patch.object(caldav, "resolve_host", fake_resolve)
class PutTests(unittest.TestCase):
	stamp = datetime.datetime(2026, 11, 2, 12, 0, tzinfo=datetime.timezone.utc)

	def test_create_timed_with_time_zone(self):
		uid, body = caldav.build_new_calendar({
			"summary": "Lunch", "location": "Cafe",
			"start": {"dateTime": "2026-11-05T12:00:00", "timeZone": "Europe/Oslo"},
			"end": {"dateTime": "2026-11-05T13:00:00+01:00", "timeZone": "Europe/Oslo"},
		}, uid="u-1", stamp=self.stamp)
		event = Calendar.from_ical(body).walk("VEVENT")[0]
		self.assertEqual(str(event["UID"]), "u-1")
		self.assertIn("DTSTAMP", event)
		self.assertEqual(str(event["DTSTART"].params["TZID"]), "Europe/Oslo")
		self.assertEqual(event["DTSTART"].dt.isoformat(), "2026-11-05T12:00:00+01:00")
		self.assertEqual(event["DTEND"].dt.isoformat(), "2026-11-05T13:00:00+01:00")
		self.assertEqual(str(event["LOCATION"]), "Cafe")
		self.assertIn(b"BEGIN:VTIMEZONE", body)

	def test_create_all_day_and_utc(self):
		_, body = caldav.build_new_calendar({"summary": "Off", "start": {"date": "2026-11-05"}, "end": {"date": "2026-11-06"}})
		event = Calendar.from_ical(body).walk("VEVENT")[0]
		self.assertEqual(event["DTSTART"].dt, datetime.date(2026, 11, 5))
		self.assertIn(b"DTSTART;VALUE=DATE:20261105", body)
		_, body = caldav.build_new_calendar({"summary": "Z", "start": {"dateTime": "2026-11-05T10:00:00Z"},
			"end": {"dateTime": "2026-11-05T11:00:00+01:00"}})
		self.assertIn(b"DTSTART:20261105T100000Z", body)
		self.assertIn(b"DTEND:20261105T100000Z", body)

	def test_create_with_recurrence(self):
		_, body = caldav.build_new_calendar({"summary": "Weekly", "start": {"date": "2026-11-02"}, "end": {"date": "2026-11-03"},
			"recurrence": ["RRULE:FREQ=WEEKLY;BYDAY=MO", "EXDATE;VALUE=DATE:20261109", "RDATE;VALUE=DATE:20261111"]})
		event = Calendar.from_ical(body).walk("VEVENT")[0]
		self.assertEqual(event["RRULE"]["FREQ"], ["WEEKLY"])
		self.assertIn(b"EXDATE;VALUE=DATE:20261109", body)
		self.assertIn(b"RDATE;VALUE=DATE:20261111", body)

	def test_create_validation(self):
		bad = [
			{"start": {"date": "2026-11-05"}, "end": {"date": "2026-11-06"}},
			{"summary": "x", "start": {"date": "2026-11-05"}, "end": {"dateTime": "2026-11-06T10:00:00"}},
			{"summary": "x", "start": {"date": "2026-11-05"}, "end": {"date": "2026-11-05"}},
			{"summary": "x", "start": {"dateTime": "nope"}, "end": {"date": "2026-11-06"}},
			{"summary": "x", "start": {"dateTime": "2026-11-05T10:00", "timeZone": "Mars/Base"}, "end": {"dateTime": "2026-11-05T11:00"}},
			{"summary": "x", "start": {"date": "2026-11-05"}, "end": {"date": "2026-11-06"}, "recurrence": ["SUMMARY:evil"]},
			{"summary": "x", "start": {"date": "2026-11-05"}, "end": {"date": "2026-11-06"}, "recurrence": "RRULE:FREQ=DAILY"},
		]
		for data in bad:
			with self.assertRaises(caldav.CalDavError) as ctx:
				caldav.build_new_calendar(data)
			self.assertEqual(ctx.exception.kind, "INPUT", data)

	EXISTING = vcal(
		"BEGIN:VEVENT\r\nUID:ex-1\r\nDTSTAMP:20261001T000000Z\r\nDTSTART:20261102T080000Z\r\n"
		"DTEND:20261102T090000Z\r\nRRULE:FREQ=WEEKLY\r\nSUMMARY:Old\r\nLOCATION:Here\r\nDESCRIPTION:Keep me\r\n"
		"SEQUENCE:2\r\nATTENDEE;CN=Bob:mailto:bob@example.com\r\nX-CUSTOM:yes\r\n"
		"BEGIN:VALARM\r\nACTION:DISPLAY\r\nTRIGGER:-PT15M\r\nDESCRIPTION:Reminder\r\nEND:VALARM\r\nEND:VEVENT\r\n"
		"BEGIN:VEVENT\r\nUID:ex-1\r\nRECURRENCE-ID:20261109T080000Z\r\nDTSTART:20261109T100000Z\r\n"
		"DTEND:20261109T110000Z\r\nSUMMARY:Override\r\nEND:VEVENT\r\n")

	def test_update_keeps_unchanged_properties(self):
		uid, body = caldav.build_updated_calendar(self.EXISTING, {"summary": "New", "location": ""}, stamp=self.stamp)
		self.assertEqual(uid, "ex-1")
		cal = Calendar.from_ical(body)
		master, override = cal.walk("VEVENT")
		self.assertEqual(str(master["SUMMARY"]), "New")
		self.assertNotIn("LOCATION", master)
		self.assertEqual(str(master["DESCRIPTION"]), "Keep me")
		self.assertEqual(master["RRULE"]["FREQ"], ["WEEKLY"])
		self.assertIn("ATTENDEE", master)
		self.assertEqual(str(master["X-CUSTOM"]), "yes")
		self.assertEqual(len(master.walk("VALARM")), 1)
		self.assertEqual(int(master["SEQUENCE"]), 3)
		self.assertEqual(master["DTSTART"].dt.isoformat(), "2026-11-02T08:00:00+00:00")
		self.assertEqual(str(override["SUMMARY"]), "Override")

	def test_update_start_keeps_duration_and_recurrence_replacement(self):
		_, body = caldav.build_updated_calendar(self.EXISTING, {"start": {"dateTime": "2026-11-02T10:00:00Z"}})
		master = Calendar.from_ical(body).walk("VEVENT")[0]
		self.assertEqual(master["DTEND"].dt.isoformat(), "2026-11-02T11:00:00+00:00")
		self.assertIn("RRULE", master)  # recurrence absent: kept
		_, body = caldav.build_updated_calendar(self.EXISTING, {"recurrence": ["RRULE:FREQ=DAILY;COUNT=3", "EXDATE:20261103T080000Z"]})
		master = Calendar.from_ical(body).walk("VEVENT")[0]
		self.assertEqual(master["RRULE"]["FREQ"], ["DAILY"])
		self.assertIn(b"EXDATE:20261103T080000Z", body)
		_, body = caldav.build_updated_calendar(self.EXISTING, {"recurrence": []})
		master = Calendar.from_ical(body).walk("VEVENT")[0]
		self.assertNotIn("RRULE", master)
		self.assertNotIn("EXDATE", master)

	def test_put_create_and_update_requests(self):
		client = FakeClient([(201, {"ETag": '"new"'}, "")])
		result = caldav.put_event(client, BASE + "/cal", {"summary": "A", "start": {"date": "2026-11-05"}, "end": {"date": "2026-11-06"}})
		method, url, body, headers = client.sent[0]
		self.assertEqual(method, "PUT")
		self.assertEqual(url, BASE + "/cal/" + result["uid"] + ".ics")
		self.assertEqual(headers["If-None-Match"], "*")
		self.assertEqual(result, {"href": url, "etag": '"new"', "uid": result["uid"]})

		client = FakeClient([
			(200, {"ETag": '"v1"'}, self.EXISTING),
			(204, {}, ""),
			(207, {}, ms(resp("/cal/ex-1.ics", '<d:getetag>"v2"</d:getetag>'))),
		])
		result = caldav.put_event(client, BASE + "/cal/", {"summary": "B"}, href="/cal/ex-1.ics", etag='"v1"')
		self.assertEqual([s[0] for s in client.sent], ["GET", "PUT", "PROPFIND"])
		self.assertEqual(client.sent[1][3]["If-Match"], '"v1"')
		self.assertEqual(result, {"href": BASE + "/cal/ex-1.ics", "etag": '"v2"', "uid": "ex-1"})

	def test_put_stale_etag_is_conflict(self):
		client = FakeClient([(200, {}, self.EXISTING), (412, {}, "")])
		with self.assertRaises(caldav.CalDavError) as ctx:
			caldav.put_event(client, BASE + "/cal/", {"summary": "B"}, href=BASE + "/cal/ex-1.ics", etag="v0")
		self.assertEqual(ctx.exception.kind, "CONFLICT")
		self.assertEqual(client.sent[1][3]["If-Match"], '"v0"')

	def test_event_b64_on_command_line(self):
		event = {"summary": "Æ b64", "start": {"date": "2026-11-05"}, "end": {"date": "2026-11-06"}}
		encoded = base64.b64encode(json.dumps(event).encode("utf-8")).decode("ascii")
		sent = []

		class Recorder(FakeClient):
			def __init__(self, user, password):
				super().__init__([(201, {"ETag": '"x"'}, "")])
				sent.append(self)
		out = io.StringIO()
		with mock.patch.object(caldav, "Client", Recorder):
			code = caldav.main(["put", "--url", BASE + "/cal/", "--user", "u", "--password-stdin", "--event-b64", encoded],
				stdin=io.StringIO("pw\n"), stdout=out, stderr=io.StringIO())
		self.assertEqual(code, 0)
		self.assertIn("SUMMARY:Æ b64", sent[0].sent[0][2].decode("utf-8"))
		self.assertEqual(json.loads(out.getvalue())["etag"], '"x"')
		err = io.StringIO()
		code = caldav.main(["put", "--url", BASE + "/cal/", "--user", "u", "--password-stdin", "--event-b64", "!!"],
			stdin=io.StringIO("pw\n"), stdout=io.StringIO(), stderr=err)
		self.assertEqual(code, 1)
		self.assertTrue(err.getvalue().startswith("INPUT: "))

	def test_delete(self):
		client = FakeClient([(204, {}, "")])
		self.assertEqual(caldav.delete_event(client, BASE + "/cal/x.ics", '"e"'), {"ok": True})
		self.assertEqual(client.sent[0][:2], ("DELETE", BASE + "/cal/x.ics"))
		self.assertEqual(client.sent[0][3]["If-Match"], '"e"')


IMPORT_ICS = (
	"BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:x\r\nMETHOD:PUBLISH\r\n"
	"BEGIN:VTIMEZONE\r\nTZID:Custom/Zone\r\nBEGIN:STANDARD\r\nDTSTART:19700101T000000\r\nTZOFFSETFROM:+0100\r\n"
	"TZOFFSETTO:+0100\r\nEND:STANDARD\r\nEND:VTIMEZONE\r\n"
	"BEGIN:VTIMEZONE\r\nTZID:Unused/Zone\r\nBEGIN:STANDARD\r\nDTSTART:19700101T000000\r\nTZOFFSETFROM:+0300\r\n"
	"TZOFFSETTO:+0300\r\nEND:STANDARD\r\nEND:VTIMEZONE\r\n"
	"BEGIN:VEVENT\r\nUID:rec@example.com\r\nDTSTART;TZID=Custom/Zone:20261102T090000\r\nDTEND;TZID=Custom/Zone:20261102T100000\r\n"
	"RRULE:FREQ=DAILY;COUNT=5\r\nSUMMARY:Series\r\nEND:VEVENT\r\n"
	"BEGIN:VEVENT\r\nUID:plain-1\r\nDTSTART;VALUE=DATE:20261110\r\nSUMMARY:Plain\r\nEND:VEVENT\r\n"
	"BEGIN:VEVENT\r\nUID:rec@example.com\r\nRECURRENCE-ID;TZID=Custom/Zone:20261103T090000\r\n"
	"DTSTART;TZID=Custom/Zone:20261103T150000\r\nDTEND;TZID=Custom/Zone:20261103T160000\r\nSUMMARY:Series moved\r\nEND:VEVENT\r\n"
	"BEGIN:VEVENT\r\nUID:dup\r\nDTSTART:20261105T100000Z\r\nSUMMARY:Exists\r\nEND:VEVENT\r\n"
	"END:VCALENDAR\r\n"
)


@mock.patch.object(caldav, "resolve_host", fake_resolve)
class ImportTests(unittest.TestCase):
	def test_grouping_by_uid_with_overrides_and_timezones(self):
		groups, failed = caldav.group_import(Calendar.from_ical(IMPORT_ICS))
		self.assertEqual(failed, [])
		self.assertEqual([uid for uid, _ in groups], ["rec@example.com", "plain-1", "dup"])
		series = groups[0][1]
		self.assertEqual(len(series.walk("VEVENT")), 2)
		self.assertEqual([str(tz["TZID"]) for tz in series.walk("VTIMEZONE")], ["Custom/Zone"])
		self.assertNotIn("METHOD", series)
		self.assertEqual(groups[1][1].walk("VTIMEZONE"), [])

	def test_resource_names(self):
		self.assertEqual(caldav.resource_name("plain-1"), "plain-1")
		name = caldav.resource_name("rec@example.com")
		self.assertRegex(name, r"^rec_example\.com-[0-9a-f]{12}$")
		self.assertNotEqual(caldav.resource_name("a/b"), caldav.resource_name("a_b"))
		self.assertRegex(caldav.resource_name("../../etc"), r"^[A-Za-z0-9._-]+$")
		self.assertNotIn("/", caldav.resource_name("../../etc"))

	def test_import_puts_each_uid_and_reports_existing(self):
		with tempfile.TemporaryDirectory() as tmp:
			path = pathlib.Path(tmp) / "in.ics"
			path.write_text(IMPORT_ICS)
			client = FakeClient([(201, {}, ""), (201, {}, ""), (412, {}, "")])
			result = caldav.import_file(client, BASE + "/cal/", "file://" + str(path))
		self.assertEqual(result, {"imported": 2, "failed": [{"uid": "dup", "error": "exists"}]})
		self.assertTrue(all(s[0] == "PUT" and s[3]["If-None-Match"] == "*" for s in client.sent))
		self.assertEqual(client.sent[1][1], BASE + "/cal/plain-1.ics")
		self.assertEqual(client.sent[0][2].count(b"BEGIN:VEVENT"), 2)

	def test_import_bad_file(self):
		client = FakeClient([])
		for path in ("/nonexistent/x.ics", "/etc/hostname"):
			with self.assertRaises(caldav.CalDavError) as ctx:
				caldav.import_file(client, BASE + "/cal/", path)
			self.assertEqual(ctx.exception.kind, "INPUT")

	def test_import_stops_on_auth_error(self):
		with tempfile.TemporaryDirectory() as tmp:
			path = pathlib.Path(tmp) / "in.ics"
			path.write_text(IMPORT_ICS)
			client = FakeClient([(401, {}, "")])
			with self.assertRaises(caldav.CalDavError) as ctx:
				caldav.import_file(client, BASE + "/cal/", str(path))
		self.assertEqual(ctx.exception.kind, "AUTH")


if __name__ == "__main__":
	unittest.main()
