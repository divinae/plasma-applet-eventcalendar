import QtQuick

import "./calendars"
import "./lib"
import "./lib/Async.js" as Async
import "LocaleFuncs.js" as LocaleFuncs
import "Shared.js" as Shared
import "EventCacheUtil.js" as EventCacheUtil
import "Guests.js" as Guests
import "Conflicts.js" as Conflicts
import "EventTypes.js" as EventTypes
import "TaskLists.js" as TaskLists
import "Tasks.js" as Tasks

CalendarManager {
	id: eventModel

	property var calendarManagerList: []
	property var calendarPluginMap: ({}) // Empty Map
	property var eventsData: { "items": [] }
	// Google working locations, not shown as events: { Shared.dayKey(day): "Home" / "Office" / ... }
	// for the day headers. Only your own (calendars you can edit), not hidden ones.
	property var workingLocations: ({})

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

	// The manager of calendarId when it can do fnName (has that function), else null.
	function managerWith(calendarId, fnName) {
		var calendarManager = getCalendarManager(calendarId)
		return calendarManager && typeof calendarManager[fnName] === 'function' ? calendarManager : null
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

	//--- TickTick: one session and tasks manager per account with a token (from the keyring).
	TickTickAccountsStore {
		id: tickTickAccountsStore
	}

	Repeater {
		id: tickTickAccountsRepeater
		model: tickTickAccountsStore.fetchableAccounts
		delegate: Item {
			id: tickTickAccountItem
			property string accountId: modelData.id

			TickTickApiSession {
				id: tickTickApiSession
				server: modelData.server
				token: modelData.token
			}
			TickTickTasksManager {
				id: tickTickTasksManager
				session: tickTickApiSession
				accountsStore: tickTickAccountsStore
				accountId: tickTickAccountItem.accountId
				accountLabel: modelData.label || "TickTick"
			}

			Component.onCompleted: {
				eventModel.bindSignals(tickTickTasksManager)
			}
			Component.onDestruction: {
				eventModel.unbindSignals(tickTickTasksManager)
			}
		}
	}

	Connections {
		target: tickTickAccountsStore
		function onFetchableAccountsChanged() {
			eventModel.clear()
			deferredUpdate.restart()
		}
	}

	PlasmaCalendarManager {
		id: plasmaCalendarManager
	}

	// Tasks are placed on their day when parsed (Tasks.placementDay): place them again.
	Connections {
		target: plasmoid.configuration
		function onAgendaPlaceOverdueTasksOnTodayChanged() {
			deferredUpdate.restart()
		}
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
			shown[calendarId] = EventTypes.splitWorkingLocations({ items: items })
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
		if (Tasks.isTask(eventItem)) {
			return taskDetailsText(eventItem)
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

	// Tooltip text for a task: due date, list, start of the notes.
	function taskDetailsText(task) {
		var lines = []
		var dueDay = Tasks.dueDay(task)
		if (dueDay) {
			var due = Qt.formatDateTime(new Date(dueDay + ' 00:00:00'), i18nc("short month+date format", "MMM d"))
			if (task.dueTime) { // Timed TickTick tasks
				var parts = String(task.dueTime).split(':')
				var time = new Date(2000, 0, 1, Number(parts[0]), Number(parts[1]))
				due = i18nc("date (%1) with time (%2)", "%1, %2", due, Qt.formatTime(time, appletConfig.timeFormat))
			}
			lines.push(i18nc("%1 = date", "Due %1", due))
		} else {
			lines.push(i18n("No due date"))
		}
		var list = getCalendar(task.calendarId)
		if (list && list.summary) {
			lines.push(list.summary)
		}
		var notes = Shared.plainText(task.notes || task.description)
		if (notes) {
			lines.push('')
			lines.push(notes.length > 300 ? notes.substr(0, 300) + '…' : notes)
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
		// Declined events and calendars hidden in the header's calendar menu may be left out;
		// eventsByCalendar keeps them (lookups, undo, cache).
		var showDeclined = plasmoid.configuration.showDeclinedEvents
		var hiddenCalendarIds = plasmoid.configuration.hiddenCalendarIds
		var all = []
		var inHiddenCalendar = [] // Per item of all
		var workingLocationItems = []
		for (var calendarId in eventModel.eventsByCalendar) {
			var calendarData = eventModel.eventsByCalendar[calendarId]
			var calendarItems = calendarData.items
			var calendarHidden = Shared.isHiddenCalendar(calendarId, hiddenCalendarIds)
			for (var j = 0; j < calendarItems.length; j++) {
				all.push(calendarItems[j])
				inHiddenCalendar.push(calendarHidden)
			}
			// Working locations (kept apart when parsed, see EventTypes.splitWorkingLocations): a
			// label in the day headers, your own only.
			var locations = calendarHidden ? [] : Shared.toArray(calendarData.workingLocations)
			for (var k = 0; k < locations.length; k++) {
				if (locations[k].canEdit) {
					workingLocationItems.push(locations[k])
				}
			}
		}
		// Overlapping meetings, as { summary } objects (see Shared.conflictTitles). Not cached on
		// disk, and removed before an event is sent back to Google.
		// Only your own time counts: calendars you can edit, and meetings you're invited to. Others'
		// calendars you only follow (a colleague's, holidays) would show false conflicts.
		// Calendars hidden from the views don't count either: their events can't be seen.
		var hiddenCalendars = Shared.toArray(plasmoid.configuration.hiddenCalendarIds)
		var conflicts = Conflicts.find(all.filter(function(eventItem) {
			return (!!eventItem.canEdit || !!Shared.myResponse(eventItem))
				&& !Shared.isHiddenCalendar(eventItem.calendarId, hiddenCalendars)
		}))
		var items = []
		for (var i = 0; i < all.length; i++) {
			var titles = conflicts[Conflicts.eventKey(all[i])] || []
			all[i].conflictsWith = titles.map(function(title) { return { summary: title } })
			if (!inHiddenCalendar[i] && !Shared.isHiddenDeclined(all[i], showDeclined)) {
				items.push(all[i])
			}
		}
		eventModel.workingLocations = EventTypes.workingLocationMap(workingLocationItems, {
			home: i18nc("working location", "Home"),
			office: i18nc("working location", "Office"),
			custom: i18nc("working location", "Elsewhere"),
		})
		eventModel.eventsData = { items: items }
	}

	//--- CalendarManager: Event
	// The calendar new events start in (agendaNewEventRememberCalendar); not a task list, so a new
	// task doesn't make events default to it.
	function rememberNewEventCalendar(calendarId) {
		var calendar = getCalendar(calendarId)
		if (plasmoid.configuration.agendaNewEventRememberCalendar && !(calendar && calendar.isTasklist)) {
			plasmoid.configuration.agendaNewEventLastCalendarId = calendarId
		}
	}
	function createEvent(calendarId, date, text) {
		rememberNewEventCalendar(calendarId)

		var calendarManager = managerWith(calendarId, 'createEvent')
		if (calendarManager) {
			calendarManager.createEvent(calendarId, date, text)
		} else {
			logger.log('Could not createEvent: no calendar manager')
		}
	}

	// Search the calendars that support it (Google) between timeMin and timeMax.
	// callback(err, items) once all of them answered.
	function searchEvents(query, timeMin, timeMax, callback) {
		var managers = calendarManagerList.filter(function(m) {
			return typeof m.searchEvents === 'function'
		})
		Async.settleAll(managers.map(function(m) {
			return m.searchEvents.bind(m, query, timeMin, timeMax)
		}), function(results) {
			var found = []
			var firstError = null
			results.forEach(function(result) {
				firstError = firstError || result.err
				found = found.concat(result.data || [])
			})
			callback(found.length ? null : firstError, found)
		})
	}

	// params: optional query params (Google), eg: { sendUpdates: 'all', conferenceDataVersion: 1 }.
	function createEventFromData(calendarId, eventData, done, params) {
		rememberNewEventCalendar(calendarId)
		var calendarManager = managerWith(calendarId, 'createEventFromData')
		if (calendarManager) {
			calendarManager.createEventFromData(calendarId, eventData, done, params)
		} else {
			logger.log('Could not createEventFromData: no calendar manager')
		}
	}

	// done(err): optional, called once the server answered (Google).
	function deleteEvent(calendarId, eventId, done) {
		var calendarManager = managerWith(calendarId, 'deleteEvent')
		if (calendarManager) {
			calendarManager.deleteEvent(calendarId, eventId, done)
		} else {
			logger.log('Could not deleteEvent: no calendar manager')
		}
	}

	// Whole recurring series (Google): seriesId is an occurrence's recurringEventId.
	function deleteSeries(calendarId, seriesId, done) {
		var calendarManager = managerWith(calendarId, 'deleteSeries')
		if (calendarManager) {
			calendarManager.deleteSeries(calendarId, seriesId, done)
		} else {
			logger.log('Could not deleteSeries: no calendar manager')
		}
	}

	// Deleted events can be brought back (Google): see restoreEvent.
	function canRestore(calendarId) {
		return !!managerWith(calendarId, 'restoreEvent')
	}

	// Undo a delete. eventId: the event, the occurrence or the series (recurringEventId).
	// copy: Undo.restoreCopy of a single event, created again if it can't be restored, or null.
	function restoreEvent(calendarId, eventId, copy, done) {
		var calendarManager = managerWith(calendarId, 'restoreEvent')
		if (calendarManager) {
			calendarManager.restoreEvent(calendarId, eventId, copy, done)
		} else {
			logger.log('Could not restoreEvent: no calendar manager')
		}
	}

	// RSVP (Google): set only the signed-in user's own attendee responseStatus ('accepted',
	// 'tentative', 'declined'), on the occurrence or, with series, the whole recurring series.
	// done: by default a refetch (the response, and for a series every occurrence, comes back with it).
	function respondToEvent(eventItem, status, series, done) {
		if (!eventItem || ['accepted', 'tentative', 'declined'].indexOf(status) < 0) {
			return
		}
		if (!done) {
			done = function() { logic.update() }
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

	// The signed-in user can answer the invitation: invited (not organizing) on a Google calendar
	// they can write to.
	function canRespond(eventItem) {
		return !!selfAttendee(eventItem) && !!eventItem.canEdit && supportsRecurrence(eventItem.calendarId)
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

	// Guests of the loaded events, for suggestions in the editor: [{ email, name }]. Built from
	// memory each time, never stored (the event cache keeps no guests).
	function knownGuestEmails() {
		return Guests.knownGuests(eventModel.eventsData.items)
	}

	// options: optional { params } with query params for the update (Google Calendar), or
	// { done(err, item) } for tasks.
	function setEventProperties(calendarId, eventId, args, options) {
		var calendarManager = managerWith(calendarId, 'setEventProperties')
		if (calendarManager) {
			calendarManager.setEventProperties(calendarId, eventId, args, options)
		} else {
			logger.log('Could not setEventProperties: no calendar manager')
		}
	}

	//--- Tasks (see Tasks.js)
	function isTask(item) {
		return Tasks.isTask(item)
	}

	// Check (done) or uncheck a task. cb(err, item): optional, always called once saved or failed.
	function toggleTask(item, done, cb) {
		if (!Tasks.isTask(item) || !managerWith(item.calendarId, 'setEventProperties')) {
			if (cb) {
				cb('toggleTask: not a task', null)
			}
			return
		}
		setEventProperties(item.calendarId, item.id, Tasks.toggleBody(done), { done: cb })
	}

	// Check (done) or uncheck a subtask of a task: a TickTick checklist item (subtaskId: its id in
	// item.subtasks), else a task of the same list (Google: subtasks are tasks with a parent).
	// cb(err, item): optional, always called; item is the task that was saved.
	function toggleSubtask(item, subtaskId, done, cb) {
		var calendarManager = Tasks.isTask(item) ? managerWith(item.calendarId, 'toggleSubtask') : null
		if (calendarManager) {
			calendarManager.toggleSubtask(item.calendarId, item.id, subtaskId, done, cb)
			return
		}
		var subtask = Tasks.isTask(item) ? getEvent(item.calendarId, subtaskId) : null
		if (!subtask) {
			if (cb) {
				cb('toggleSubtask: no such subtask', null)
			}
			return
		}
		toggleTask(subtask, done, cb)
	}

	// Tasks can be put in another order within the list (Google; TickTick's API can't).
	function supportsReorder(listId) {
		return !!managerWith(listId, 'reorderTask')
	}

	// Put a task right after previousTaskId ('' : first) in its list, among its siblings (see
	// GoogleTasksManager.reorderTask). cb(err, item): optional, always called.
	function reorderTask(item, previousTaskId, cb) {
		var calendarManager = Tasks.isTask(item) ? managerWith(item.calendarId, 'reorderTask') : null
		if (!calendarManager) {
			logger.log('Could not reorderTask: not supported')
			if (cb) {
				cb('reorderTask not supported', null)
			}
			return
		}
		calendarManager.reorderTask(item.calendarId, item.id, previousTaskId || '', cb)
	}

	// The task lists tasks can be added to or moved to: [{ id, summary, backgroundColor }].
	// accountPrefix: optional, only that account's lists (the part of the ids before '::').
	function getTaskLists(accountPrefix) {
		var prefix = accountPrefix ? accountPrefix + '::' : ''
		return getCalendarList().filter(function(c) {
			return c.isTasklist === true
				&& (!c.accessRole || c.accessRole === 'owner' || c.accessRole === 'writer')
				&& (!prefix || String(c.id).indexOf(prefix) === 0)
		}).map(function(c) {
			return { id: c.id, summary: c.summary, backgroundColor: c.backgroundColor }
		})
	}

	// The task lists selected in settings (their tasks are loaded), for the Tasks view:
	// [{ id, name, color, group }], group: the account label (else the service's name).
	function getSelectedTaskLists() {
		var out = []
		for (var i = 0; i < calendarManagerList.length; i++) {
			var calendarManager = calendarManagerList[i]
			var label = String(calendarManager.accountLabel || "")
			var group = label || (calendarManager.calendarManagerId === 'TickTick' ? "TickTick" : "Google")
			var list = calendarManager.getCalendarList()
			for (var j = 0; j < list.length; j++) {
				var calendar = list[j]
				if (!calendar || !calendar.id || calendar.isTasklist !== true) {
					continue
				}
				var selected = typeof calendarManager.isTasklistSelected === 'function' ? calendarManager.isTasklistSelected(calendar.id)
					: typeof calendarManager.isProjectSelected === 'function' ? calendarManager.isProjectSelected(calendar.id)
					: !!eventModel.eventsByCalendar[calendar.id]
				if (!selected) {
					continue
				}
				var entry = selectedCalendarEntry(calendar.id, calendar, label)
				entry.group = group
				out.push(entry)
			}
		}
		return out
	}

	//--- Task lists: create, rename, delete, color, clear completed (see TaskLists.js)
	// Emitted after a list changed (the Tasks view builds its rows again).
	signal taskListsChanged()

	// The accounts lists can be created in, for a "New list in…" picker:
	// [{ id (the account prefix of its list ids), label, provider (calendarManagerId) }].
	function getTaskAccounts() {
		var out = []
		for (var i = 0; i < calendarManagerList.length; i++) {
			var calendarManager = calendarManagerList[i]
			if (typeof calendarManager.createTaskList !== 'function' || !calendarManager.accountId) {
				continue
			}
			var provider = String(calendarManager.calendarManagerId)
			out.push({
				id: String(calendarManager.accountId),
				label: String(calendarManager.accountLabel || (provider === 'TickTick' ? "TickTick" : "Google")),
				provider: provider,
			})
		}
		return out
	}
	function taskListAccountManager(accountPrefix) {
		for (var i = 0; i < calendarManagerList.length; i++) {
			var calendarManager = calendarManagerList[i]
			if (calendarManager.accountId === accountPrefix && typeof calendarManager.createTaskList === 'function') {
				return calendarManager
			}
		}
		return null
	}

	// { rename, delete, color, clearCompleted }: what can be done with the list.
	function taskListCapabilities(listId) {
		var calendarManager = managerWith(listId, 'taskListCapabilities')
		return calendarManager ? calendarManager.taskListCapabilities(listId)
			: { rename: false, delete: false, color: false, clearCompleted: false }
	}
	function supportsListEdit(listId) {
		return TaskLists.hasAny(taskListCapabilities(listId))
	}

	// done(err, result) once the server answered, always called. removedListId: a deleted list,
	// unloaded here (its tasks leave the views).
	function taskListDone(done, removedListId) {
		return function(err, result) {
			if (!err) {
				if (removedListId) {
					delete eventModel.eventsByCalendar[removedListId]
					delete eventModel.calendarPluginMap[removedListId]
					mergeEvents()
				}
				taskListsChanged()
			}
			if (done) {
				done(err || null, result || null)
			}
		}
	}
	// Call fnName(listId, args..., done) on the list's manager, else done(err).
	function forwardTaskList(fnName, listId, args, done, removedListId) {
		var calendarManager = managerWith(listId, fnName)
		if (!calendarManager) {
			logger.log('Could not ' + fnName + ': not supported')
			if (done) {
				done(fnName + ' not supported', null)
			}
			return
		}
		calendarManager[fnName].apply(calendarManager, [listId].concat(args, [taskListDone(done, removedListId)]))
	}

	// A new list in an account (accountPrefix: see getTaskAccounts), shown right away.
	// done(err, list): list is { id, name }.
	function createTaskList(accountPrefix, title, done) {
		var calendarManager = taskListAccountManager(accountPrefix)
		if (!calendarManager) {
			logger.log('Could not createTaskList: no account')
			if (done) {
				done('createTaskList: no account', null)
			}
			return
		}
		calendarManager.createTaskList(title, taskListDone(done, ''))
	}
	function renameTaskList(listId, title, done) {
		forwardTaskList('renameTaskList', listId, [title], done, '')
	}
	// The list and its tasks are deleted.
	function deleteTaskList(listId, done) {
		forwardTaskList('deleteTaskList', listId, [], done, listId)
	}
	// color: '#rrggbb' (TickTick).
	function setTaskListColor(listId, color, done) {
		forwardTaskList('setTaskListColor', listId, [color], done, '')
	}
	// The list's completed tasks are cleared (Google).
	function clearCompleted(listId, done) {
		forwardTaskList('clearCompleted', listId, [], done, '')
	}

	// Repeat rules can be edited (Google Calendar).
	function supportsRecurrence(calendarId) {
		return !!managerWith(calendarId, 'updateEventFromServer')
	}

	// Server copy of an event, eg: the series of a recurring event. callback(err, event)
	function fetchEvent(calendarId, eventId, callback) {
		var calendarManager = managerWith(calendarId, 'fetchEvent')
		if (calendarManager) {
			calendarManager.fetchEvent(calendarId, eventId, callback)
		} else {
			callback('fetchEvent not supported', null)
		}
	}

	// See GoogleCalendarManager.updateEventFromServer.
	function updateEventFromServer(calendarId, eventId, buildArgs, done, options, failed) {
		var calendarManager = managerWith(calendarId, 'updateEventFromServer')
		if (calendarManager) {
			calendarManager.updateEventFromServer(calendarId, eventId, buildArgs, done, options, failed)
		} else {
			logger.log('Could not updateEventFromServer: no calendar manager')
		}
	}

	// Events can move to another calendar of the same account (Google): see moveEvent.
	function supportsMove(calendarId) {
		return !!managerWith(calendarId, 'moveEvent')
	}

	// Move an event, or a series (eventId = recurringEventId), to destinationCalendarId (same
	// account). See GoogleCalendarManager.moveEvent. done(err, movedEvent)
	function moveEvent(calendarId, eventId, destinationCalendarId, done, params) {
		var calendarManager = managerWith(calendarId, 'moveEvent')
		if (calendarManager) {
			calendarManager.moveEvent(calendarId, eventId, destinationCalendarId, done, params)
		} else {
			logger.log('Could not moveEvent: no calendar manager')
			if (done) {
				done('moveEvent not supported', null)
			}
		}
	}

	// Events can be imported from .ics files (Google Calendar).
	function supportsImport(calendarId) {
		return !!managerWith(calendarId, 'importEvent')
	}

	// See GoogleCalendarManager.importEvent. done(err, data)
	function importEvent(calendarId, eventData, done) {
		var calendarManager = managerWith(calendarId, 'importEvent')
		if (calendarManager) {
			calendarManager.importEvent(calendarId, eventData, done)
		} else {
			done(i18n("This calendar can't import events"), null)
		}
	}

	// Find a time: busy times of people (Google freeBusy, through the calendar's account).
	function supportsFreeBusy(calendarId) {
		return !!managerWith(calendarId, 'freeBusy')
	}
	// You in freeBusy: the id of the primary calendar of the account of calendarId, else 'primary'.
	function ownFreeBusyId(calendarId) {
		var calendarManager = managerWith(calendarId, 'ownFreeBusyId')
		if (calendarManager) {
			return calendarManager.ownFreeBusyId()
		}
		return 'primary'
	}
	// See GoogleCalendarManager.freeBusy. done(err, data)
	function freeBusy(calendarId, ids, from, to, done) {
		var calendarManager = managerWith(calendarId, 'freeBusy')
		if (calendarManager) {
			calendarManager.freeBusy(calendarId, ids, from, to, done)
		} else {
			done(i18n("This calendar can't show free / busy times"), null)
		}
	}

	//--- CalendarManager: Calendar
	// The calendars selected in settings (those with events loaded), for the popup header's
	// calendar toggles: [{ id, name, color, group }], grouped by account (group = account label).
	function getSelectedCalendars() {
		var out = []
		var listed = {}
		for (var i = 0; i < calendarManagerList.length; i++) {
			var calendarManager = calendarManagerList[i]
			var group = String(calendarManager.accountLabel || "")
			var list = calendarManager.getCalendarList()
			for (var j = 0; j < list.length; j++) {
				var calendar = list[j]
				if (!calendar || !calendar.id || listed[calendar.id] || !eventModel.eventsByCalendar[calendar.id]) {
					continue
				}
				listed[calendar.id] = true
				out.push(selectedCalendarEntry(calendar.id, calendar, group))
			}
		}
		// Calendars a manager doesn't list (iCalendar files): look them up by id.
		for (var calendarId in eventModel.eventsByCalendar) {
			if (listed[calendarId]) {
				continue
			}
			var manager = eventModel.calendarPluginMap[calendarId]
			var data = manager && typeof manager.getCalendar === 'function' ? manager.getCalendar(calendarId) : null
			out.push(selectedCalendarEntry(calendarId, data || {}, ""))
		}
		return out
	}
	function selectedCalendarEntry(calendarId, calendar, group) {
		var name = String(calendar.summary || calendar.name || "")
		if (group && name.indexOf(group + " - ") === 0) {
			name = name.substr(group.length + 3) // The account is the group heading
		}
		if (!name) {
			name = calendarId === "plasma_Holidays" ? i18n("Holidays") : calendarId
		}
		return {
			id: calendarId,
			name: name,
			color: String(calendar.backgroundColor || calendar.color || ""), // Empty: the theme's highlight
			group: group,
		}
	}

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
