import QtQuick
import org.kde.kirigami as Kirigami

import "../ErrorType.js" as ErrorType
import "../ScriptPath.js" as ScriptPath
import "../lib"
import "../lib/Base64Compat.js" as Base64Compat

// CalDAV calendars (Nextcloud, Fastmail, iCloud, Radicale, …) through scripts/caldav.py: the
// selected calendars of the accounts in caldavAccounts (Settings > CalDAV), read for the shown
// range, and events created, changed, deleted and imported there. The password stays in the
// keyring (scope caldav-account); the helper reads it there, it's never on a command line.
// Repeating events are read-only here (whole series edits aren't supported yet).
CalendarManager {
	id: caldavManager

	calendarManagerId: "CalDAV"
	property var accounts: [] // caldavAccounts: [{ id, label, url, username, calendars: [{ href, name, color, writable, selected }] }]

	ExecUtil { id: executable }
	Logger {
		id: logger
		name: "eventcalendar-caldav"
		showDebug: plasmoid.configuration.debugging
	}

	property string helperPath: ScriptPath.scriptPath("caldav.py") // (A test harness points it elsewhere)

	// The calendar ids: "caldav-<account>::<calendar url>" (the part before :: is the account).
	function calendarIdOf(account, calendar) {
		return "caldav-" + account.id + "::" + calendar.href
	}

	function getCalendarList() {
		var out = []
		;(accounts || []).forEach(function(account) {
			;(account.calendars || []).forEach(function(calendar) {
				if (calendar.selected === false) {
					return
				}
				out.push({
					id: calendarIdOf(account, calendar),
					summary: String(calendar.name || calendar.href),
					backgroundColor: String(calendar.color || Kirigami.Theme.highlightColor),
					accessRole: calendar.writable === false ? 'reader' : 'owner',
					isTasklist: false,
					accountId: account.id,
					accountLabel: String(account.label || account.username || ""),
					username: String(account.username || ""),
					caldavHref: calendar.href,
				})
			})
		})
		return out
	}

	// The error kind of the helper's message ("AUTH: …"): the message for the user, no URL in it.
	function helperError(stderr, calendarName) {
		var line = String(stderr || "").trim().split("\n").pop()
		var kind = (/^([A-Z]+):/.exec(line) || [])[1] || ""
		var text = line.replace(/^[A-Z]+:\s*/, "").replace(/https?:\/\/\S+/gi, "[URL]")
		if (kind === "AUTH") {
			return { kind: kind, message: i18n("CalDAV: %1 didn't accept the user name or password", calendarName) }
		}
		if (kind === "NETWORK") {
			return { kind: kind, message: i18n("Could not connect") }
		}
		if (kind === "CONFLICT") {
			return { kind: kind, message: i18n("The event was changed elsewhere meanwhile; it's loaded again") }
		}
		return { kind: kind, message: i18n("CalDAV: %1", text || i18n("Unknown error")) }
	}

	// helper(args, calendar, callback(err, data)): runs caldav.py with the calendar's account.
	function helper(args, calendar, callback) {
		var argv = ['python3', helperPath].concat(args).concat(['--account', calendar.accountId, '--user', calendar.username])
		executable.execArgv(argv, function(cmd, exitCode, exitStatus, stdout, stderr) {
			if (exitCode) {
				logger.log('caldav.helperError', args[0], exitCode) // No event data or URLs in logs
				callback(helperError(stderr, calendar.summary), null)
				return
			}
			var data
			try {
				data = JSON.parse(stdout)
			} catch (e) {
				callback({ kind: "PROTOCOL", message: i18n("CalDAV: an unexpected answer") }, null)
				return
			}
			callback(null, data)
		})
	}

	function dayText(d) {
		return d.getFullYear() + '-' + (d.getMonth() + 1) + '-' + d.getDate()
	}
	// The event's fields as the helper takes them (Google style), base64 JSON on its command line.
	function eventArg(fields) {
		var body = {}
		;['summary', 'location', 'description', 'start', 'end', 'recurrence'].forEach(function(key) {
			if (fields && fields[key] !== undefined) {
				body[key] = fields[key]
			}
		})
		return Base64Compat.base64EncodeString(JSON.stringify(body)) // UTF-8
	}

	//--- Reading
	function fetchCalendar(calendar) {
		caldavManager.asyncRequests += 1
		var calendarId = calendar.id
		helper(['query', '--url', calendar.caldavHref, dayText(dateMin), dayText(dateMax)], calendar, function(err, data) {
			try {
				if (err) {
					restorePreviousCalendar(calendarId) // Keep what was shown
					caldavManager.error(err.message, err.kind === "NETWORK" ? ErrorType.NetworkError : ErrorType.UnknownError)
					return
				}
				if (!(data && Array.isArray(data.items))) {
					return
				}
				setCalendarData(calendarId, data) // Parsed by parseCalendarData
			} finally {
				caldavManager.asyncRequestsDone += 1
			}
		})
	}

	onFetchAllCalendars: {
		getCalendarList().forEach(function(calendar) {
			fetchCalendar(calendar)
		})
	}

	function parseCalendarData(calendarId, data) {
		var calendar = getCalendar(calendarId)
		if (!calendar) {
			return
		}
		data.items.forEach(function(event) {
			event.backgroundColor = calendar.backgroundColor
			// Repeating events: read-only for now (a change would need the whole series).
			event.canEdit = calendar.accessRole === 'owner' && !event.recurring
		})
	}

	// After a change: everything read again (the server gives the events their final form).
	function changed() {
		caldavManager.refresh()
	}

	//--- Writing
	function createEventFromData(calendarId, eventData, done) {
		var calendar = getCalendar(calendarId)
		if (!calendar) {
			if (done) done('createEventFromData: unknown calendar')
			return
		}
		helper(['put', '--url', calendar.caldavHref, '--event-b64', eventArg(eventData)], calendar, function(err, data) {
			if (err) {
				caldavManager.error(err.message, ErrorType.UnknownError)
			} else {
				eventCreated(calendarId, eventData)
				changed()
			}
			if (done) {
				done(err ? err.message : null)
			}
		})
	}

	// Quick add: the text as the title, on date (at time for an hour, else all day).
	function createEvent(calendarId, date, text, time) {
		var day = date || new Date()
		var data = { summary: text }
		var pad = function(n) { return (n < 10 ? '0' : '') + n }
		var dayIso = function(d) { return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()) }
		if (time) {
			var parts = String(time).split(':')
			var start = new Date(day.getFullYear(), day.getMonth(), day.getDate(), Number(parts[0]) || 0, Number(parts[1]) || 0)
			var end = new Date(start.getTime() + 3600000)
			data.start = { dateTime: start.toISOString() }
			data.end = { dateTime: end.toISOString() }
		} else {
			var next = new Date(day.getFullYear(), day.getMonth(), day.getDate() + 1)
			data.start = { date: dayIso(day) }
			data.end = { date: dayIso(next) }
		}
		createEventFromData(calendarId, data, null)
	}

	function setEventProperties(calendarId, eventId, args, options) {
		var calendar = getCalendar(calendarId)
		var event = getEvent(calendarId, eventId)
		var done = options && options.done
		if (!calendar || !event || !event.caldavHref) {
			logger.log('caldav.setEventProperties', 'event not loaded')
			if (done) done('setEventProperties: event not loaded', null)
			return
		}
		helper(['put', '--url', calendar.caldavHref, '--href', event.caldavHref, '--etag', String(event.caldavEtag || ''),
			'--event-b64', eventArg(args)], calendar, function(err, data) {
			if (err) {
				caldavManager.error(err.message, ErrorType.UnknownError)
			} else {
				eventUpdated(calendarId, eventId, event)
			}
			changed() // Also after a conflict: the current version
			if (done) done(err ? err.message : null, event)
		})
	}

	// The editor's server-side update (buildArgs(serverEvent) -> args): the loaded copy is it here.
	function updateEventFromServer(calendarId, eventId, buildArgs, done, options) {
		var event = getEvent(calendarId, eventId)
		if (!event) {
			if (done) done('updateEventFromServer: event not loaded')
			return
		}
		setEventProperties(calendarId, eventId, buildArgs(event), { done: function(err) { if (done) done(err) } })
	}

	function deleteEvent(calendarId, eventId, done) {
		var calendar = getCalendar(calendarId)
		var event = getEvent(calendarId, eventId)
		if (!calendar || !event || !event.caldavHref) {
			if (done) done('deleteEvent: event not loaded')
			return
		}
		helper(['delete', '--href', event.caldavHref, '--etag', String(event.caldavEtag || '')], calendar, function(err) {
			if (err) {
				caldavManager.error(err.message, ErrorType.UnknownError)
			} else {
				eventDeleted(calendarId, eventId, event)
				removeEvent(calendarId, eventId)
			}
			changed()
			if (done) done(err ? err.message : null)
		})
	}

	// Import (ImportView, one event at a time, Google-style fields): created as a new event.
	function importEvent(calendarId, eventData, done) {
		var calendar = getCalendar(calendarId)
		if (!calendar) {
			done(i18n("This calendar can't import events"), null)
			return
		}
		helper(['put', '--url', calendar.caldavHref, '--event-b64', eventArg(eventData)], calendar, function(err, data) {
			if (err) {
				done(err.message, null)
				return
			}
			changed()
			done(null, data)
		})
	}
}
