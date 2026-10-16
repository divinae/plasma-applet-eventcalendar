import QtQuick

import "./calendars"
import "./lib"
import "LocaleFuncs.js" as LocaleFuncs
import "Shared.js" as Shared
import "EventCacheUtil.js" as EventCacheUtil

CalendarManager {
	id: eventModel

	property var calendarManagerList: []
	property var calendarPluginMap: ({}) // Empty Map
	property var eventsData: { "items": [] }

	Component.onCompleted: {
		bindSignals(plasmaCalendarManager)
		bindSignals(icalManager)
	}

	//---
	function fetchingDataListener() { eventModel.asyncRequests += 1 }
	function allDataFetchedListener() { eventModel.asyncRequestsDone += 1 }
	function calendarFetchedListener(calendarId, data) {
		// Already parsed by the child manager. Skip calendarParsing.
		eventModel.eventsByCalendar[calendarId] = data
		eventModel.calendarFetched(calendarId, data)
	}
	// Child managers change their own event lists. Ours holds copies (Qt 6.12+ copies JS objects
	// passed through var signal arguments), so mirror adds, removes and updates here.
	function ownEventList(calendarId) {
		var calendar = eventModel.eventsByCalendar[calendarId]
		if (!calendar) {
			calendar = { items: [] }
			eventModel.eventsByCalendar[calendarId] = calendar
		}
		return calendar.items
	}
	function indexOfEvent(items, eventId) {
		for (var i = 0; i < items.length; i++) {
			if (items[i].id == eventId) {
				return i
			}
		}
		return -1
	}
	function eventAddedListener(calendarId, data) {
		var items = ownEventList(calendarId)
		if (indexOfEvent(items, data.id) < 0) {
			items.push(data)
		}
		eventModel.mergeEvents()
		eventModel.eventAdded(calendarId, data)
	}
	function eventCreatedListener(calendarId, data) {
		eventModel.eventCreated(calendarId, data)
	}
	function eventRemovedListener(calendarId, eventId, data) {
		var items = ownEventList(calendarId)
		var index = indexOfEvent(items, eventId)
		if (index >= 0) {
			items.splice(index, 1)
		}
		eventModel.mergeEvents()
		eventModel.eventRemoved(calendarId, eventId, data)
	}
	function eventDeletedListener(calendarId, eventId, data) {
		eventModel.eventDeleted(calendarId, eventId, data)
	}
	function eventUpdatedListener(calendarId, eventId, data) {
		var items = ownEventList(calendarId)
		var index = indexOfEvent(items, eventId)
		if (index >= 0) {
			items[index] = data
		} else {
			items.push(data)
		}
		eventModel.mergeEvents()
		eventModel.eventUpdated(calendarId, eventId, data)
	}

	function bindSignals(calendarManager) {
		logger.debug('bindSignals', calendarManager)
		calendarManager.fetchingData.connect(fetchingDataListener)
		calendarManager.allDataFetched.connect(allDataFetchedListener)
		calendarManager.calendarFetched.connect(calendarFetchedListener)

		calendarManager.calendarFetched.connect(function(calendarId, data){
			eventModel.calendarPluginMap[calendarId] = calendarManager
		})

		calendarManager.eventAdded.connect(eventAddedListener)
		calendarManager.eventCreated.connect(eventCreatedListener)
		calendarManager.eventRemoved.connect(eventRemovedListener)
		calendarManager.eventDeleted.connect(eventDeletedListener)
		calendarManager.eventUpdated.connect(eventUpdatedListener)
		calendarManager.refresh.connect(deferredUpdate.restart)

		calendarManager.error.connect(error)

		calendarManagerList.push(calendarManager)
	}

	function unbindSignals(calendarManager) {
		var index = calendarManagerList.indexOf(calendarManager)
		if (index >= 0) {
			calendarManagerList.splice(index, 1)
		}
		for (var calendarId in eventModel.calendarPluginMap) {
			if (eventModel.calendarPluginMap[calendarId] === calendarManager) {
				delete eventModel.calendarPluginMap[calendarId]
			}
		}
	}

	function getCalendarManager(calendarId) {
		var calendarKey = calendarId ? "" + calendarId : ""
		var manager = eventModel.calendarPluginMap[calendarKey]
		if (manager) {
			return manager
		}
		for (var i = 0; i < calendarManagerList.length; i++) {
			var calendarManager = calendarManagerList[i]
			if (calendarManager && calendarManager.getCalendar && calendarManager.getCalendar(calendarKey)) {
				eventModel.calendarPluginMap[calendarKey] = calendarManager
				return calendarManager
			}
		}
		if (!calendarKey || calendarKey.indexOf("::") < 0) {
			return null
		}
		var splitIndex = calendarKey.indexOf("::")
		var accountPrefix = calendarKey.slice(0, splitIndex)
		var rawId = calendarKey.slice(splitIndex + 2)
		var calendarCandidate = null
		var taskCandidate = null
		for (var j = 0; j < calendarManagerList.length; j++) {
			var googleManager = calendarManagerList[j]
			if (!googleManager || googleManager.accountId !== accountPrefix || !googleManager.getAccount) {
				continue
			}
			if (googleManager.calendarManagerId === "GoogleCalendar") {
				calendarCandidate = googleManager
			} else if (googleManager.calendarManagerId === "GoogleTasks") {
				taskCandidate = googleManager
			}
			var account = googleManager.getAccount()
			if (googleManager.calendarManagerId === "GoogleCalendar" && account && Array.isArray(account.calendarList)) {
				for (var c = 0; c < account.calendarList.length; c++) {
					var calendar = account.calendarList[c]
					if (rawId === calendar.id || (rawId === "primary" && calendar.primary)) {
						eventModel.calendarPluginMap[calendarKey] = googleManager
						return googleManager
					}
				}
			}
			if (googleManager.calendarManagerId === "GoogleTasks" && account && Array.isArray(account.tasklistList)) {
				for (var t = 0; t < account.tasklistList.length; t++) {
					var tasklist = account.tasklistList[t]
					if (rawId === tasklist.id) {
						eventModel.calendarPluginMap[calendarKey] = googleManager
						return googleManager
					}
				}
			}
		}
		if (calendarCandidate || taskCandidate) {
			var looksLikeCalendar = rawId === "primary" || rawId.indexOf("@") >= 0
			var fallbackManager = looksLikeCalendar ? (calendarCandidate || taskCandidate) : (taskCandidate || calendarCandidate)
			if (fallbackManager) {
				eventModel.calendarPluginMap[calendarKey] = fallbackManager
				return fallbackManager
			}
		}
		return null
	}

	//---
	GoogleAccountsStore {
		id: googleAccountsStore
	}

	ICalManager {
		id: icalManager
		calendarList: appletConfig.icalCalendarList.value
	}

	Repeater {
		id: googleAccountsRepeater
		model: googleAccountsStore.fetchableAccounts
		delegate: Item {
			id: googleAccountItem
			property string accountId: modelData.id
			property string accountLabel: modelData.label || ""

			GoogleApiSession {
				id: googleApiSession
				accountsStore: googleAccountsStore
				accountId: googleAccountItem.accountId
			}
			GoogleCalendarManager {
				id: googleCalendarManager
				session: googleApiSession
				accountsStore: googleAccountsStore
				accountId: googleAccountItem.accountId
				accountLabel: googleAccountItem.accountLabel
			}
			GoogleTasksManager {
				id: googleTasksManager
				session: googleApiSession
				accountsStore: googleAccountsStore
				accountId: googleAccountItem.accountId
				accountLabel: googleAccountItem.accountLabel
			}

			Connections {
				target: googleAccountsStore
				function onAccountUpdated(updatedId) {
					if (updatedId === googleAccountItem.accountId) {
						var account = googleAccountsStore.getAccount(updatedId)
						googleAccountItem.accountLabel = account && account.label ? account.label : ""
					}
				}
			}

			Component.onCompleted: {
				eventModel.bindSignals(googleCalendarManager)
				eventModel.bindSignals(googleTasksManager)
			}
			Component.onDestruction: {
				eventModel.unbindSignals(googleCalendarManager)
				eventModel.unbindSignals(googleTasksManager)
			}
		}
	}

	Connections {
		target: googleAccountsStore
		function onAccountsChanged() {
			eventModel.clear()
			deferredUpdate.restart()
		}
		function onSecretsLoadedChanged() {
			if (googleAccountsStore.secretsLoaded) {
				eventModel.clear()
				deferredUpdate.restart()
			}
		}
	}

	PlasmaCalendarManager {
		id: plasmaCalendarManager
	}

	//---
	property var deferredUpdate: Timer {
		id: deferredUpdate
		interval: 200
		onTriggered: eventModel.update()
	}
	function update() {
		// dateMin/dateMax are unset until Logic requests the first range.
		if (dateMin >= dateMax) {
			return
		}
		fetchAll()
	}

	onFetchAllCalendars: {
		// Suppress checkIfDone while children start, otherwise children that
		// finish synchronously trigger allDataFetched before the rest register.
		eventModel.clearingData = true
		for (var i = 0; i < calendarManagerList.length; i++) {
			var calendarManager = calendarManagerList[i]
			calendarManager.fetchAll(dateMin, dateMax)
		}
		eventModel.clearingData = false
	}

	onAllDataFetched: {
		restoreCachedCalendars()
		mergeEvents()
	}

	//--- Event cache (EventCache.qml): shown on start until the first fetch round brings them in.
	property var cachedEventsByCalendar: ({}) // { calendarId: { items: [...] } }, Google calendars only

	// Events from the disk cache: parsed like fetched ones, shown right away.
	function showCachedEvents(calendars) {
		var shown = {}
		for (var calendarId in calendars) {
			var items = calendars[calendarId]
			for (var i = 0; i < items.length; i++) {
				defaultEventParsing(calendarId, items[i])
				items[i].calendarManagerId = 'GoogleCalendar'
				items[i].description = ''
			}
			shown[calendarId] = { items: items }
			eventModel.eventsByCalendar[calendarId] = shown[calendarId]
		}
		eventModel.cachedEventsByCalendar = shown
		mergeEvents()
	}

	// A fetch round that couldn't load a cached calendar (offline right after boot, keyring still
	// locked) keeps showing the cached events instead of an empty calendar.
	function restoreCachedCalendars() {
		var selected = EventCacheUtil.selectedCalendarIds(googleAccountsStore.accounts)
		for (var calendarId in eventModel.cachedEventsByCalendar) {
			if (!eventModel.eventsByCalendar[calendarId] && selected[calendarId]) {
				eventModel.eventsByCalendar[calendarId] = eventModel.cachedEventsByCalendar[calendarId]
			}
		}
	}

	// After a fetch round without network errors: calendars that were fetched no longer need the
	// cached copy, nor do ones whose account can't be fetched (signed out). Until the keyring gave
	// the tokens, nothing Google was fetched yet, so everything stays.
	function settleCachedCalendars() {
		if (!googleAccountsStore.secretsLoaded) {
			return
		}
		var fetchable = {}
		var accounts = googleAccountsStore.fetchableAccounts
		for (var i = 0; i < accounts.length; i++) {
			fetchable[accounts[i].id] = true
		}
		var remaining = {}
		var removed = false
		for (var calendarId in eventModel.cachedEventsByCalendar) {
			var cached = eventModel.cachedEventsByCalendar[calendarId]
			var accountId = calendarId.slice(0, calendarId.indexOf('::'))
			if (eventModel.eventsByCalendar[calendarId] !== cached) {
				continue // Fetched
			}
			if (!fetchable[accountId]) {
				delete eventModel.eventsByCalendar[calendarId]
				removed = true
				continue
			}
			remaining[calendarId] = cached
		}
		eventModel.cachedEventsByCalendar = remaining
		if (removed) {
			mergeEvents()
		}
	}

	// Tooltip text for an event: time, location, calendar, start of the description.
	function eventDetailsText(eventItem) {
		if (!eventItem) {
			return ''
		}
		var lines = []
		lines.push(LocaleFuncs.formatEventDuration(eventItem, {
			relativeDate: timeModel.currentTime,
			clock24h: appletConfig.clock24h,
		}))
		if (eventItem.location) {
			lines.push(eventItem.location)
		}
		var calendar = getCalendar(eventItem.calendarId)
		if (calendar && calendar.summary) {
			lines.push(calendar.summary)
		}
		var description = Shared.plainText(eventItem.description)
		if (description) {
			lines.push('')
			lines.push(description.length > 300 ? description.substr(0, 300) + '…' : description)
		}
		return lines.join('\n')
	}

	// Event color palette changed: recolor what's loaded (Google), then rebuild the merged list.
	function recolorEvents() {
		for (var i = 0; i < calendarManagerList.length; i++) {
			if (typeof calendarManagerList[i].recolorEvents === 'function') {
				calendarManagerList[i].recolorEvents()
			}
		}
		mergeEvents()
	}

	function mergeEvents() {
		logger.debug('eventModel.mergeEvents')
		// Build the list first and assign once: bindings on eventsData must not see it half-filled.
		var items = []
		for (var calendarId in eventModel.eventsByCalendar) {
			items = items.concat(eventModel.eventsByCalendar[calendarId].items)
		}
		eventModel.eventsData = { items: items }
	}

	//--- CalendarManager: Event
	function createEvent(calendarId, date, text) {
		if (plasmoid.configuration.agendaNewEventRememberCalendar) {
			plasmoid.configuration.agendaNewEventLastCalendarId = calendarId
		}

		var calendarManager = getCalendarManager(calendarId)
		if (calendarManager) {
			calendarManager.createEvent(calendarId, date, text)
		} else {
			logger.log('Could not createEvent. Could not find calendarManager for calendarId = ', calendarId)
		}
	}

	function createEventFromData(calendarId, eventData, done) {
		if (plasmoid.configuration.agendaNewEventRememberCalendar) {
			plasmoid.configuration.agendaNewEventLastCalendarId = calendarId
		}
		var calendarManager = getCalendarManager(calendarId)
		if (calendarManager && typeof calendarManager.createEventFromData === 'function') {
			calendarManager.createEventFromData(calendarId, eventData, done)
		} else {
			logger.log('Could not createEventFromData for calendarId = ', calendarId)
		}
	}

	function deleteEvent(calendarId, eventId) {
		var calendarManager = getCalendarManager(calendarId)
		if (calendarManager) {
			calendarManager.deleteEvent(calendarId, eventId)
		} else {
			logger.log('Could not deleteEvent. Could not find calendarManager for calendarId = ', calendarId)
		}
	}

	// Whole recurring series (Google): seriesId is an occurrence's recurringEventId.
	function deleteSeries(calendarId, seriesId, done) {
		var calendarManager = getCalendarManager(calendarId)
		if (calendarManager && typeof calendarManager.deleteSeries === 'function') {
			calendarManager.deleteSeries(calendarId, seriesId, done)
		} else {
			logger.log('Could not deleteSeries for calendarId = ', calendarId)
		}
	}

	// RSVP (Google): set only the signed-in user's own attendee responseStatus ('accepted',
	// 'tentative', 'declined'), on the occurrence or, with series, the whole recurring series.
	function respondToEvent(eventItem, status, series, done) {
		if (!eventItem || ['accepted', 'tentative', 'declined'].indexOf(status) < 0) {
			return
		}
		var eventId = series && eventItem.recurringEventId ? eventItem.recurringEventId : eventItem.id
		updateEventFromServer(eventItem.calendarId, eventId, function(serverEvent) {
			var attendees = Shared.toArray(serverEvent.attendees).map(function(a) {
				var copy = {}
				for (var key in a) {
					copy[key] = a[key]
				}
				if (copy.self) {
					copy.responseStatus = status
				}
				return copy
			})
			return { attendees: attendees }
		}, done)
	}

	// The signed-in user's attendee entry when invited (not when organizing), else null.
	function selfAttendee(eventItem) {
		var attendees = eventItem ? Shared.toArray(eventItem.attendees) : []
		for (var i = 0; i < attendees.length; i++) {
			if (attendees[i].self) {
				return attendees[i].organizer ? null : attendees[i]
			}
		}
		return null
	}

	function setEventProperty(calendarId, eventId, key, value) {
		logger.debug('eventModel.setEventProperty', calendarId, eventId, key, value)
		var calendarManager = getCalendarManager(calendarId)
		if (calendarManager) {
			calendarManager.setEventProperty(calendarId, eventId, key, value)
		} else {
			logger.log('Could not setEventProperty. Could not find calendarManager for calendarId = ', calendarId)
		}
	}

	function setEventProperties(calendarId, eventId, args) {
		logger.debugJSON('eventModel.setEventProperties', calendarId, eventId, args)
		var calendarManager = getCalendarManager(calendarId)
		if (calendarManager) {
			calendarManager.setEventProperties(calendarId, eventId, args)
		} else {
			logger.log('Could not setEventProperties. Could not find calendarManager for calendarId = ', calendarId)
		}
	}

	// Repeat rules can be edited (Google Calendar).
	function supportsRecurrence(calendarId) {
		var calendarManager = getCalendarManager(calendarId)
		return !!calendarManager && typeof calendarManager.updateEventFromServer === 'function'
	}

	// Server copy of an event, eg: the series of a recurring event. callback(err, event)
	function fetchEvent(calendarId, eventId, callback) {
		var calendarManager = getCalendarManager(calendarId)
		if (calendarManager && typeof calendarManager.fetchEvent === 'function') {
			calendarManager.fetchEvent(calendarId, eventId, callback)
		} else {
			callback('fetchEvent not supported', null)
		}
	}

	// See GoogleCalendarManager.updateEventFromServer.
	function updateEventFromServer(calendarId, eventId, buildArgs, done) {
		var calendarManager = getCalendarManager(calendarId)
		if (calendarManager && typeof calendarManager.updateEventFromServer === 'function') {
			calendarManager.updateEventFromServer(calendarId, eventId, buildArgs, done)
		} else {
			logger.log('Could not updateEventFromServer for calendarId = ', calendarId)
		}
	}

	//--- CalendarManager: Calendar
	function getCalendarList() {
		var calendarList = []
		for (var i = 0; i < calendarManagerList.length; i++) {
			var calendarManager = calendarManagerList[i]
			var list = calendarManager.getCalendarList()
			for (var j = 0; j < list.length; j++) {
				if (list[j] && list[j].id) {
					eventModel.calendarPluginMap[list[j].id] = calendarManager
				}
			}
			calendarList = calendarList.concat(list)
		}
		return calendarList
	}
}
