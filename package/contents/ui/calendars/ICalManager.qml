import QtQuick

import "../ErrorType.js" as ErrorType

import "../lib"

CalendarManager {
	id: icalManager

	calendarManagerId: "ical"
	ExecUtil { id: executable }

	property var calendarList: [
		{
			url: "/home/chris/Code/icsjson/basic.ics",
			backgroundColor: '#ff0',
			isTasklist: false,
		}
	]

	function localFilePath(url) {
		var path = String(url)
		return path.indexOf("file://") === 0 ? path.slice(7) : path
	}

	function getCalendar(calendarId) {
		for (var i = 0; i < calendarList.length; i++) {
			var calendarData = calendarList[i]
			if (calendarData.url == calendarId) {
				return calendarData
			}
		}
		return null
	}

	function fetchEvents(calendarData, startTime, endTime, callback) {
		logger.debug('ical.fetchEvents', calendarData.url)
		var startDate = startTime.getFullYear() + '-' + (startTime.getMonth() + 1) + '-' + startTime.getDate()
		var endDate = endTime.getFullYear() + '-' + (endTime.getMonth() + 1) + '-' + endTime.getDate()
		var cmd = [
			'python3',
			localFilePath(Qt.resolvedUrl("../../scripts/icsjson.py")),
			'--url',
			calendarData.url,
			'query',
			startDate,
			endDate,
		]
		executable.exec(cmd, function(cmd, exitCode, exitStatus, stdout, stderr) {
			if (exitCode) {
				logger.log('ical.stderr', stderr)
				return callback(stderr)
			}
			var data = null
			try {
				data = JSON.parse(stdout)
			} catch (e) {
				return callback('Invalid calendar data')
			}
			callback(null, data)
		})
	}

	function fetchCalendar(calendarData) {
		icalManager.asyncRequests += 1
		fetchEvents(calendarData, dateMin, dateMax, function(err, data) {
			if (err || !data) {
				// Keep the previous events; connection problems are retried like Google's.
				restorePreviousCalendar(calendarData.url)
				var isNetwork = /URLError|timed out|Name or service|Temporary failure|Connection|Network is unreachable/i.test(String(err))
				icalManager.error(isNetwork ? i18n("Could not connect") : i18n("Error fetching calendar: %1", calendarData.url),
					isNetwork ? ErrorType.NetworkError : ErrorType.UnknownError)
			} else {
				parseEventList(calendarData, data.items)
				setCalendarData(calendarData.url, data)
			}
			icalManager.asyncRequestsDone += 1
		})
	}

	onFetchAllCalendars: {
		for (var i = 0; i < calendarList.length; i++) {
			var calendarData = calendarList[i]
			fetchCalendar(calendarData)
		}
	}

	function parseCalendarData(calendarId, data) {
		var calendar = getCalendar(calendarId)
		parseEventList(calendar, data.items)
	}

	function parseEvent(calendar, event) {
		event.backgroundColor = calendar.backgroundColor
		event.canEdit = false
	}

	function parseEventList(calendar, eventList) {
		eventList.forEach(function(event) {
			parseEvent(calendar, event)
		})
	}
}
