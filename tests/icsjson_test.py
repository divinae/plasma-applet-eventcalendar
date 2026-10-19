from __future__ import annotations

import datetime
import importlib.util
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

from icalendar import Calendar


SCRIPT_PATH = pathlib.Path(__file__).parents[1] / "package/contents/scripts/icsjson.py"
SPEC = importlib.util.spec_from_file_location("eventcalendar_icsjson", SCRIPT_PATH)
icsjson = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(icsjson)


def parse_calendar(events: str) -> Calendar:
	return Calendar.from_ical(
		("BEGIN:VCALENDAR\r\nVERSION:2.0\r\n" + events + "END:VCALENDAR\r\n").encode()
	)


class IcsJsonTests(unittest.TestCase):
	def test_timezone_aware_values_are_normalized_to_local_naive_time(self):
		aware = datetime.datetime(2026, 7, 3, 0, 30, tzinfo=datetime.timezone.utc)
		expected = aware.astimezone().replace(tzinfo=None)

		self.assertEqual(icsjson.ensure_date_time(aware), expected)

	def test_event_filter_uses_half_open_bounds(self):
		calendar = parse_calendar(
			"BEGIN:VEVENT\r\n"
			"UID:boundary-test\r\n"
			"DTSTART:20260703T100000Z\r\n"
			"DTEND:20260703T110000Z\r\n"
			"SUMMARY:Boundary test\r\n"
			"END:VEVENT\r\n"
		)
		event = calendar.walk("vevent")[0]
		start = icsjson.ensure_date_time(event["DTSTART"].dt)
		end = icsjson.ensure_date_time(event["DTEND"].dt)

		self.assertTrue(icsjson.event_within(event, start, end))
		self.assertFalse(icsjson.event_within(event, end, end + datetime.timedelta(hours=1)))
		self.assertFalse(icsjson.event_within(event, start - datetime.timedelta(hours=1), start))

	def test_zero_duration_event_is_included_at_its_start(self):
		calendar = parse_calendar(
			"BEGIN:VEVENT\r\n"
			"UID:instant-test\r\n"
			"DTSTART:20260703T100000Z\r\n"
			"SUMMARY:Instant test\r\n"
			"END:VEVENT\r\n"
		)
		event = calendar.walk("vevent")[0]
		start = icsjson.ensure_date_time(event["DTSTART"].dt)

		self.assertTrue(
			icsjson.event_within(event, start, start + datetime.timedelta(seconds=1))
		)

	def test_all_day_event_without_end_defaults_to_one_day(self):
		calendar = parse_calendar(
			"BEGIN:VEVENT\r\n"
			"UID:all-day-test\r\n"
			"DTSTART;VALUE=DATE:20260703\r\n"
			"SUMMARY:All-day test\r\n"
			"END:VEVENT\r\n"
		)
		event = calendar.walk("vevent")[0]
		payload = json.loads(icsjson.events_to_json([event]))

		self.assertEqual(payload["items"][0]["start"], {"date": "2026-07-03"})
		self.assertEqual(payload["items"][0]["end"], {"date": "2026-07-04"})

	def test_duration_description_and_cancelled_status_are_respected(self):
		calendar = parse_calendar(
			"BEGIN:VEVENT\r\n"
			"UID:duration-test\r\n"
			"DTSTART:20260703T100000Z\r\n"
			"DURATION:PT90M\r\n"
			"DESCRIPTION:Useful details\r\n"
			"SUMMARY:Duration test\r\n"
			"END:VEVENT\r\n"
			"BEGIN:VEVENT\r\n"
			"UID:cancelled-test\r\n"
			"DTSTART:20260703T120000Z\r\n"
			"DTEND:20260703T130000Z\r\n"
			"STATUS:CANCELLED\r\n"
			"SUMMARY:Cancelled test\r\n"
			"END:VEVENT\r\n"
		)
		payload = json.loads(icsjson.events_to_json(calendar.walk("vevent")))

		self.assertEqual(len(payload["items"]), 1)
		self.assertEqual(payload["items"][0]["end"], {"dateTime": "2026-07-03T11:30:00+00:00"})
		self.assertEqual(payload["items"][0]["description"], "Useful details")

	def test_query_delegates_expansion_to_recurring_ical_events(self):
		calendar = parse_calendar(
			"BEGIN:VEVENT\r\n"
			"UID:delegation-test\r\n"
			"DTSTART:20260703T100000Z\r\n"
			"DTEND:20260703T110000Z\r\n"
			"SUMMARY:Delegation test\r\n"
			"END:VEVENT\r\n"
		)
		event = calendar.walk("vevent")[0]
		start = datetime.datetime(2026, 7, 1)
		end = datetime.datetime(2026, 7, 5)
		query = mock.Mock()
		query.between.return_value = [event]
		dependency = mock.Mock()
		dependency.of.return_value = query
		manager = icsjson.CalendarManager("unused")
		manager.cal = calendar

		with mock.patch.object(icsjson, "recurring_ical_events", dependency):
			self.assertEqual(list(manager.query(start, end)), [event])

		dependency.of.assert_called_once_with(calendar)
		query.between.assert_called_once_with(start, end)

	@unittest.skipUnless(
		icsjson.recurring_ical_events is not None,
		"recurring-ical-events is not installed",
	)
	def test_recurring_events_apply_exdates_and_overrides(self):
		calendar = parse_calendar(
			"BEGIN:VEVENT\r\n"
			"UID:daily-test\r\n"
			"DTSTART:20260701T100000Z\r\n"
			"DTEND:20260701T110000Z\r\n"
			"RRULE:FREQ=DAILY;COUNT=4\r\n"
			"EXDATE:20260702T100000Z\r\n"
			"SUMMARY:Daily test\r\n"
			"END:VEVENT\r\n"
			"BEGIN:VEVENT\r\n"
			"UID:daily-test\r\n"
			"RECURRENCE-ID:20260703T100000Z\r\n"
			"DTSTART:20260703T120000Z\r\n"
			"DTEND:20260703T130000Z\r\n"
			"SUMMARY:Moved occurrence\r\n"
			"END:VEVENT\r\n"
		)
		manager = icsjson.CalendarManager("unused")
		manager.cal = calendar

		events = list(manager.query(
			datetime.datetime(2026, 7, 1),
			datetime.datetime(2026, 7, 5),
		))
		payload = json.loads(icsjson.events_to_json(events))

		self.assertEqual(len(events), 3)
		self.assertEqual(
			[item["summary"] for item in payload["items"]],
			["Daily test", "Moved occurrence", "Daily test"],
		)
		self.assertEqual(len({item["id"] for item in payload["items"]}), 3)

	def test_raw_events_keep_recurrence_rules_and_time_zones(self):
		calendar = parse_calendar(
			"BEGIN:VEVENT\r\n"
			"UID:series-test\r\n"
			"DTSTART;TZID=America/New_York:20261005T093000\r\n"
			"DTEND;TZID=America/New_York:20261005T100000\r\n"
			"RRULE:FREQ=WEEKLY;BYDAY=MO,WE;UNTIL=20261231T235959Z\r\n"
			"EXDATE;TZID=America/New_York:20261012T093000,20261014T093000\r\n"
			"EXDATE;TZID=America/New_York:20261026T093000\r\n"
			"SUMMARY:Series test\r\n"
			"CLASS:PRIVATE\r\n"
			"ATTENDEE:mailto:a@example.com\r\n"
			"ATTENDEE:mailto:b@example.com\r\n"
			"END:VEVENT\r\n"
			"BEGIN:VEVENT\r\n"
			"UID:series-test\r\n"
			"RECURRENCE-ID;TZID=America/New_York:20261019T093000\r\n"
			"DTSTART;TZID=America/New_York:20261019T110000\r\n"
			"DTEND;TZID=America/New_York:20261019T113000\r\n"
			"SUMMARY:Moved\r\n"
			"END:VEVENT\r\n"
		)
		payload = json.loads(icsjson.raw_events_to_json(calendar))

		self.assertEqual(len(payload["items"]), 2)  # Not expanded into occurrences
		series, moved = payload["items"]
		self.assertEqual(series["iCalUID"], "series-test")
		self.assertEqual(series["start"], {
			"dateTime": "2026-10-05T09:30:00-04:00",
			"timeZone": "America/New_York",
		})
		self.assertFalse(series["allDay"])
		self.assertEqual(series["class"], "PRIVATE")
		self.assertEqual(series["attendeeCount"], 2)
		self.assertEqual(series["recurrence"][0], "RRULE:FREQ=WEEKLY;UNTIL=20261231T235959Z;BYDAY=MO,WE")
		# EXDATEs in UTC: no TZID (which may be a Windows zone name Google doesn't know).
		self.assertEqual(series["recurrence"][1], "EXDATE:20261012T133000Z,20261014T133000Z,20261026T133000Z")
		self.assertNotIn("recurrence", moved)
		self.assertEqual(moved["recurrenceId"], {
			"dateTime": "2026-10-19T09:30:00-04:00",
			"timeZone": "America/New_York",
		})

	def test_raw_all_day_floating_and_cancelled_events(self):
		calendar = parse_calendar(
			"METHOD:REQUEST\r\n"
			"BEGIN:VEVENT\r\n"
			"UID:all-day-raw\r\n"
			"DTSTART;VALUE=DATE:20261102\r\n"
			"RRULE:FREQ=YEARLY\r\n"
			"EXDATE;VALUE=DATE:20271102\r\n"
			"TRANSP:TRANSPARENT\r\n"
			"SUMMARY:All day\r\n"
			"END:VEVENT\r\n"
			"BEGIN:VEVENT\r\n"
			"UID:floating-raw\r\n"
			"DTSTART:20261103T090000\r\n"
			"DURATION:PT30M\r\n"
			"SUMMARY:Floating\r\n"
			"END:VEVENT\r\n"
			"BEGIN:VEVENT\r\n"
			"UID:utc-raw\r\n"
			"DTSTART:20261104T090000Z\r\n"
			"DTEND:20261104T100000Z\r\n"
			"SUMMARY:UTC\r\n"
			"END:VEVENT\r\n"
			"BEGIN:VEVENT\r\n"
			"UID:cancelled-raw\r\n"
			"DTSTART:20261105T090000Z\r\n"
			"STATUS:CANCELLED\r\n"
			"SUMMARY:Cancelled\r\n"
			"END:VEVENT\r\n"
		)
		payload = json.loads(icsjson.raw_events_to_json(calendar))

		self.assertEqual(payload["method"], "REQUEST")
		self.assertEqual(payload["skipped"], 1)
		all_day, floating, utc = payload["items"]
		self.assertEqual(all_day["start"], {"date": "2026-11-02"})
		self.assertEqual(all_day["end"], {"date": "2026-11-03"})
		self.assertTrue(all_day["allDay"])
		self.assertEqual(all_day["transp"], "TRANSPARENT")
		self.assertEqual(all_day["recurrence"], ["RRULE:FREQ=YEARLY", "EXDATE;VALUE=DATE:20271102"])
		self.assertEqual(floating["start"], {"dateTime": "2026-11-03T09:00:00"})
		self.assertEqual(floating["end"], {"dateTime": "2026-11-03T09:30:00"})
		self.assertEqual(utc["start"]["timeZone"], "UTC")

	def test_import_file_must_be_an_existing_ics_file(self):
		with tempfile.TemporaryDirectory() as folder:
			other = pathlib.Path(folder) / "notes.txt"
			other.write_text("BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n")
			with self.assertRaises(ValueError):
				icsjson.read_import_file(str(other))
			with self.assertRaises(ValueError):
				icsjson.read_import_file(str(pathlib.Path(folder) / "missing.ics"))

	def test_events_command_prints_raw_events(self):
		with tempfile.TemporaryDirectory() as folder:
			path = pathlib.Path(folder) / "invite.ics"
			path.write_bytes(
				b"BEGIN:VCALENDAR\r\nVERSION:2.0\r\n"
				b"BEGIN:VEVENT\r\nUID:cli-test\r\nDTSTART:20261104T090000Z\r\n"
				b"DTEND:20261104T100000Z\r\nRRULE:FREQ=DAILY;COUNT=3\r\nSUMMARY:CLI\r\nEND:VEVENT\r\n"
				b"END:VCALENDAR\r\n"
			)
			for arg in (str(path), path.as_uri()):
				result = subprocess.run(
					[sys.executable, str(SCRIPT_PATH), "events", arg],
					capture_output=True, text=True, check=True,
				)
				payload = json.loads(result.stdout)
				self.assertEqual(len(payload["items"]), 1)
				self.assertEqual(payload["items"][0]["recurrence"], ["RRULE:FREQ=DAILY;COUNT=3"])

			result = subprocess.run(
				[sys.executable, str(SCRIPT_PATH), "events", str(pathlib.Path(folder) / "x.txt")],
				capture_output=True, text=True,
			)
			self.assertEqual(result.returncode, 1)
			self.assertIn("ValueError", result.stderr)


if __name__ == "__main__":
	unittest.main()
