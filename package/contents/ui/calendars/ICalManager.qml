import QtQuick

import "../ErrorType.js" as ErrorType
import "../ScriptPath.js" as ScriptPath
import "../lib"

CalendarManager {
	id: icalManager

	calendarManagerId: "ical"
	ExecUtil { id: executable }
	Logger {
		id: logger
		name: "eventcalendar-ical"
		showDebug: plasmoid.configuration.debugging
	}

	property var calendarList: [
	]

	function localFilePath(url) {
		var path = String(url)
		return path.indexOf("file://") === 0 ? path.slice(7) : path
	}

	function getCalendar(calendarId) {
		for (var i = 0; i < calendarList.length; i++) {
			var calendarData = calendarList[i]
			if (calendarData && calendarData.url == calendarId) {
				return calendarData
			}
		}
		return null
	}

	function calendarLabel(calendarData) {
		return String(calendarData && calendarData.name || i18n("iCalendar"))
	}

	function safeProcessError(stderr) {
		var message = String(stderr || i18n("Unknown iCalendar helper error")).trim()
		return message.replace(/https?:\/\/\S+/gi, "[redacted URL]")
	}

	function fetchEvents(calendarData, startTime, endTime, callback) {
		logger.debug('ical.fetchEvents', calendarLabel(calendarData))
		var startDate = startTime.getFullYear() + '-' + (startTime.getMonth() + 1) + '-' + startTime.getDate()
		var endDate = endTime.getFullYear() + '-' + (endTime.getMonth() + 1) + '-' + endTime.getDate()
		var cmd = [
			'python3',
			ScriptPath.scriptPath("icsjson.py"),
			'--url',
			calendarData.url,
			'query',
			startDate,
			endDate,
		]
		executable.execArgv(cmd, function(cmd, exitCode, exitStatus, stdout, stderr) {
			if (exitCode) {
				logger.log('ical.fetchError', calendarLabel(calendarData), exitCode, exitStatus)
				return callback(safeProcessError(stderr || stdout))
			}
			var parsed
			try {
				parsed = JSON.parse(stdout)
				if (!(parsed && Array.isArray(parsed.items))) {
					throw new Error("iCalendar helper returned an invalid event list")
				}
			} catch (err) {
				logger.log('ical.parseError', calendarLabel(calendarData), err)
				return callback(err.toString())
			}
			callback(null, parsed)
		})
	}

	function fetchCalendar(calendarData) {
		icalManager.asyncRequests += 1
		fetchEvents(calendarData, dateMin, dateMax, function(err, data) {
			try {
				if (err) {
					// Keep the previous events; connection problems are retried like Google's.
					restorePreviousCalendar(calendarData.url)
					var isNetwork = /URLError|timed out|Name or service|Temporary failure|Connection|Network is unreachable/i.test(String(err))
					icalManager.error(
						isNetwork ? i18n("Could not connect") : i18n("Could not load %1: %2", calendarLabel(calendarData), err),
						isNetwork ? ErrorType.NetworkError : ErrorType.UnknownError
					)
					return
				}
				var currentCalendar = getCalendar(calendarData.url)
				if (!currentCalendar || currentCalendar.show === false) {
					return
				}
				setCalendarData(calendarData.url, data) // Parsed by parseCalendarData
			} finally {
				icalManager.asyncRequestsDone += 1
			}
		})
	}

	onFetchAllCalendars: {
		for (var i = 0; i < calendarList.length; i++) {
			var calendarData = calendarList[i]
			if (calendarData && calendarData.show !== false && String(calendarData.url || "").trim()) {
				fetchCalendar(calendarData)
			}
		}
	}

	function parseCalendarData(calendarId, data) {
		var calendar = getCalendar(calendarId)
		if (calendar) {
			parseEventList(calendar, data.items)
		}
	}

	function parseEvent(calendar, event) {
		event.backgroundColor = calendar.backgroundColor
		event.canEdit = false
	}

	function parseEventList(calendar, eventList) {
		if (!calendar || !Array.isArray(eventList)) {
			return
		}
		eventList.forEach(function(event) {
			parseEvent(calendar, event)
		})
	}
}
