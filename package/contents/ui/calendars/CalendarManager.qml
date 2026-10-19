import QtQuick

Item {
	id: calendarManager

	property string calendarManagerId: ""
	property var eventsByCalendar: ({}) // { "": { "items": [] } }

	property date dateMin: new Date()
	property date dateMax: new Date()

	property bool clearingData: false
	property int fetchGeneration: 0 // Bumped per fetchAll, lets late responses from older ranges be dropped.
	property int asyncRequests: 0
	property int asyncRequestsDone: 0
	signal refresh()
	signal dataCleared()
	signal fetchingData()
	signal calendarFetched(string calendarId, var data)
	signal allDataFetched()
	signal eventAdded(string calendarId, var data)
	signal eventCreated(string calendarId, var data)
	signal eventRemoved(string calendarId, string eventId, var data)
	signal eventDeleted(string calendarId, string eventId, var data)
	signal eventUpdated(string calendarId, string eventId, var data)
	signal error(string msg, int errorType)

	onAsyncRequestsDoneChanged: checkIfDone()

	function checkIfDone() {
		if (clearingData) {
			return
		}
		if (asyncRequestsDone >= asyncRequests) {
			allDataFetched()
		}
	}

	//--- Calendar
	function getCalendarList() {
		return [] // Function is overloaded
	}

	function getCalendar(calendarId) {
		var calendarList = getCalendarList()
		for (var i = 0; i < calendarList.length; i++) {
			var calendar = calendarList[i]
			if (calendarId === calendar.id) {
				return calendar
			}
		}
		return null
	}

	//--- Calendar data
	function setCalendarData(calendarId, data) {
		calendarParsing(calendarId, data)
		eventsByCalendar[calendarId] = data
		calendarFetched(calendarId, data)
	}

	// Events of the previous fetch, kept so a calendar that fails to fetch (eg: offline) can keep
	// showing what it had.
	property var previousEventsByCalendar: ({})
	function restorePreviousCalendar(calendarId) {
		var previous = previousEventsByCalendar[calendarId]
		if (previous && !eventsByCalendar[calendarId]) {
			eventsByCalendar[calendarId] = previous // Already parsed
			calendarFetched(calendarId, previous)
		}
	}

	function clear() {
		logger.debug(calendarManager, 'clear()')
		calendarManager.clearingData = true
		calendarManager.asyncRequests = 0
		calendarManager.asyncRequestsDone = 0
		calendarManager.eventsByCalendar = {}
		calendarManager.clearingData = false
		dataCleared()
	}

	//--- Event
	// The loaded events of a calendar, [] when it has none.
	function eventItems(calendarId) {
		var calendar = calendarManager.eventsByCalendar[calendarId]
		return calendar && calendar.items ? calendar.items : []
	}
	function indexOfEvent(items, eventId) {
		for (var i = 0; i < items.length; i++) {
			if (items[i].id == eventId) {
				return i
			}
		}
		return -1
	}
	function getEvent(calendarId, eventId) {
		var events = eventItems(calendarId)
		var index = indexOfEvent(events, eventId)
		return index >= 0 ? events[index] : undefined
	}

	// Add to model only
	function addEvent(calendarId, data) {
		calendarManager.eventsByCalendar[calendarId].items.push(data)
		eventAdded(calendarId, data)
	}

	// Remove from model only
	function removeEvent(calendarId, eventId) {
		logger.debug(calendarManager, 'removeEvent', calendarId, eventId)
		var events = eventItems(calendarId)
		var index = indexOfEvent(events, eventId)
		if (index < 0) {
			logger.log(calendarManager, 'removeEvent', 'event didn\'t exist')
			return
		}
		var data = events[index]
		events.splice(index, 1) // Remove item at index
		eventRemoved(calendarId, eventId, data)
	}

	//---
	function fetchAll(dateMin, dateMax) {
		logger.debug(calendarManager, 'fetchAllEvents', dateMin, dateMax)
		fetchingData()
		// Merge, don't replace: a second fetch before the first finished would otherwise
		// keep an empty snapshot.
		var snapshot = {}
		var previous = calendarManager.previousEventsByCalendar
		for (var oldId in previous) {
			snapshot[oldId] = previous[oldId]
		}
		var current = calendarManager.eventsByCalendar
		for (var id in current) {
			snapshot[id] = current[id]
		}
		previousEventsByCalendar = snapshot
		clear()
		calendarManager.fetchGeneration += 1
		if (typeof dateMin !== "undefined") {
			calendarManager.dateMin = dateMin
			calendarManager.dateMax = dateMax
		}
		fetchAllCalendars()
		checkIfDone()
	}

	// Implementation
	signal fetchAllCalendars()
	// Parsing must mutate data in place, so it's done with function calls.
	// Qt 6.12+ copies JS objects passed through `var` signal arguments.
	// Parsing order:
	// CalendarManager.defaultEventParsing
	// SubClass.parseCalendarData
	function calendarParsing(calendarId, data) {
		data.items.forEach(function(event) {
			defaultEventParsing(calendarId, event)
		})
		calendarManager.parseCalendarData(calendarId, data)
	}

	// Overridden by subclasses
	function parseCalendarData(calendarId, data) {
	}

	// To simplify repeated code amongst implementations,
	// we'll put the reused code here.
	function defaultEventParsing(calendarId, event) {
		event.calendarManagerId = calendarManagerId
		event.calendarId = calendarId

		event._summary = event.summary
		event.summary = event.summary || i18nc("event with no summary", "(No title)")

		if (event.start.date) {
			event.startDateTime = new Date(event.start.date + ' 00:00:00')
		} else {
			event.startDateTime = new Date(event.start.dateTime)
		}

		if (event.end.date) {
			event.endDateTime = new Date(event.end.date + ' 00:00:00')
		} else {
			event.endDateTime = new Date(event.end.dateTime)
		}
	}

	function parseSingleEvent(calendarId, event) {
		calendarParsing(calendarId, {
			items: [event],
		})
	}

	//---
	function createEvent(calendarId, date, text) {
		logger.log(calendarManager, 'createEvent(', date, text, ') is not implemented')
	}

	function deleteEvent(calendarId, eventId) {
		logger.log(calendarManager, 'deleteEvent(', calendarId, eventId, ') is not implemented')
	}

	function setEventProperties(calendarId, eventId, args) {
		logger.log(calendarManager, 'setEventProperties(', calendarId, eventId, args, ') is not implemented')
	}
}
