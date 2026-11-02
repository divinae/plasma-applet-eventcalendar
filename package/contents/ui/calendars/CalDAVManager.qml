import QtQuick
import org.kde.kirigami as Kirigami

import "../ErrorType.js" as ErrorType
import "../ScriptPath.js" as ScriptPath
import "../lib"
import "../lib/Base64Compat.js" as Base64Compat
import "../Shared.js" as Shared
import "CalDAVErrors.js" as CalDAVErrors

// CalDAV calendars (Nextcloud, Fastmail, iCloud, Radicale, …) through scripts/caldav.py: the
// selected calendars of the accounts in caldavAccounts (Settings > Calendars > CalDAV), read for the shown
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

	// The helper's error (CalDAVErrors.parse) as a message for the user.
	function helperError(stderr, calendarName) {
		var parsed = CalDAVErrors.parse(stderr)
		var kind = parsed.kind
		var text = parsed.text
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
		helper(['query', '--url', calendar.caldavHref, Shared.localDateString(dateMin), Shared.localDateString(dateMax)], calendar, function(err, data) {
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

	//--- Writing
	// write(calendar, args, ok(data), done(err message or null)): the helper, then on success ok;
	// errors are reported. Afterwards everything is read again (the server gives the events their
	// final form, and a conflict shows the current version).
	function write(calendar, args, ok, done) {
		helper(args, calendar, function(err, data) {
			if (err) {
				caldavManager.error(err.message, ErrorType.UnknownError)
			} else if (ok) {
				ok(data)
			}
			caldavManager.refresh()
			if (done) {
				done(err ? err.message : null)
			}
		})
	}

	function createEventFromData(calendarId, eventData, done) {
		var calendar = getCalendar(calendarId)
		if (!calendar) {
			if (done) done('createEventFromData: unknown calendar')
			return
		}
		write(calendar, ['put', '--url', calendar.caldavHref, '--event-b64', eventArg(eventData)], function() {
			eventCreated(calendarId, eventData)
		}, done)
	}

	// Quick add: the text as the title, on date (at time for an hour, else all day).
	function createEvent(calendarId, date, text, time) {
		var day = date || new Date()
		var data = { summary: text }
		if (time) {
			var parts = String(time).split(':')
			var start = new Date(day.getFullYear(), day.getMonth(), day.getDate(), Number(parts[0]) || 0, Number(parts[1]) || 0)
			data.start = { dateTime: start.toISOString() }
			data.end = { dateTime: new Date(start.getTime() + 3600000).toISOString() }
		} else {
			data.start = { date: Shared.localDateString(day) }
			data.end = { date: Shared.localDateString(Shared.addDays(day, 1)) }
		}
		createEventFromData(calendarId, data, null)
	}

	// The loaded event and its calendar, or null (with done told) when it isn't loaded.
	function loadedEvent(calendarId, eventId, done, what) {
		var calendar = getCalendar(calendarId)
		var event = getEvent(calendarId, eventId)
		if (!calendar || !event || !event.caldavHref) {
			logger.log('caldav.' + what, 'event not loaded')
			if (done) done(what + ': event not loaded')
			return null
		}
		return { calendar: calendar, event: event }
	}

	function setEventProperties(calendarId, eventId, args, options) {
		var done = options && options.done
		var loaded = loadedEvent(calendarId, eventId, done, 'setEventProperties')
		if (!loaded) {
			return
		}
		write(loaded.calendar, ['put', '--url', loaded.calendar.caldavHref, '--href', loaded.event.caldavHref,
			'--etag', String(loaded.event.caldavEtag || ''), '--event-b64', eventArg(args)], function() {
			eventUpdated(calendarId, eventId, loaded.event)
		}, done)
	}

	// The editor's server-side update (buildArgs(serverEvent) -> args): the loaded copy is it here.
	function updateEventFromServer(calendarId, eventId, buildArgs, done, options) {
		var event = getEvent(calendarId, eventId)
		if (!event) {
			if (done) done('updateEventFromServer: event not loaded')
			return
		}
		setEventProperties(calendarId, eventId, buildArgs(event), { done: done })
	}

	function deleteEvent(calendarId, eventId, done) {
		var loaded = loadedEvent(calendarId, eventId, done, 'deleteEvent')
		if (!loaded) {
			return
		}
		write(loaded.calendar, ['delete', '--href', loaded.event.caldavHref, '--etag', String(loaded.event.caldavEtag || '')], function() {
			eventDeleted(calendarId, eventId, loaded.event)
			removeEvent(calendarId, eventId)
		}, done)
	}

	// Import (ImportView, one event at a time, Google-style fields): created as a new event. Not
	// read again after each: the import card refreshes once at its end.
	function importEvent(calendarId, eventData, done) {
		var calendar = getCalendar(calendarId)
		if (!calendar) {
			done(i18n("This calendar can't import events"), null)
			return
		}
		helper(['put', '--url', calendar.caldavHref, '--event-b64', eventArg(eventData)], calendar, function(err, data) {
			done(err ? err.message : null, err ? null : data)
		})
	}
}
