import QtQuick
import org.kde.kirigami as Kirigami

import "../ErrorType.js" as ErrorType
import "../Shared.js" as Shared
import "../TaskLists.js" as TaskLists
import "../Tasks.js" as Tasks
import "../lib"
import "../lib/Async.js" as Async
import "../lib/GoogleError.js" as GoogleError
import "../lib/Requests.js" as Requests

// Google Tasks API
// https://developers.google.com/tasks/reference/rest/v1/tasks

// You can view Google Tasks with this URL:
// https://tasks.google.com/embed/?origin=https%3A%2F%2Fcalendar.google.com&fullWidth=1
// Note that it redirects to /embed/list/~default which you cannot bookmark, as it'll 404.

// Tasks are event-shaped items (kind 'tasks#task'), see Tasks.js: an all-day event on the day
// it's shown on (Tasks.placementDay), with the raw due, status, completed, notes, position and
// parent kept, and notes as the description.

CalendarManager {
	id: googleTasksManager

	calendarManagerId: "GoogleTasks"

	property var session
	property var accountsStore
	property string accountId: ""
	property string accountLabel: ""

	Logger {
		id: logger
		name: 'eventcalendar-google-tasks'
		// The settings page uses this manager too, where there may be no plasmoid.
		showDebug: typeof plasmoid !== "undefined" && plasmoid && plasmoid.configuration
			? !!plasmoid.configuration.debugging
			: false
	}

	function getAccount() {
		if (!accountsStore || !accountId) {
			return null
		}
		return accountsStore.getAccount(accountId)
	}

	function getTasklistIdList() {
		var account = getAccount()
		return account && account.tasklistIdList ? account.tasklistIdList : []
	}

	function scopedTasklistId(rawId) {
		if (!accountId) {
			return rawId
		}
		return accountId + "::" + rawId
	}

	function unscopedTasklistId(scopedId) {
		if (!accountId) {
			return scopedId
		}
		var prefix = accountId + "::"
		if (scopedId.indexOf(prefix) === 0) {
			return scopedId.substr(prefix.length)
		}
		return scopedId
	}

	// The list's tasks are loaded (selected in settings).
	function isTasklistSelected(calendarId) {
		return getTasklistIdList().indexOf(unscopedTasklistId(calendarId)) >= 0
	}

	function formatTasklistSummary(tasklist) {
		if (accountLabel) {
			return accountLabel + " - " + tasklist.title
		}
		return tasklist.title
	}

	function decorateTasklist(tasklist) {
		return {
			id: scopedTasklistId(tasklist.id),
			summary: formatTasklistSummary(tasklist),
			backgroundColor: Kirigami.Theme.highlightColor.toString(),
			accessRole: 'owner',
			isTasklist: true,
		}
	}

	onFetchAllCalendars: {
		fetchGoogleAccountData()
	}

	function fetchGoogleAccountData() {
		// Tokens may live in the system keyring: an account is enough to start.
		var account = getAccount()
		if (!account) {
			return
		}
		var idList = getTasklistIdList()
		if (idList.length) { // Avoid a token refresh when nothing is selected.
			fetchGoogleAccountTasks(idList)
		}
	}

	//--- Requests
	property string apiUrl: 'https://www.googleapis.com/tasks/v1' // Not readonly: tests point it at a mock

	// action() once the session has a valid access token (refreshed when needed), else
	// fail(err, isNetworkError).
	function withToken(action, fail) {
		session.checkAccessToken(function(err, isNetworkError) {
			if (err) {
				fail(err, !!isNetworkError)
				return
			}
			action()
		})
	}

	// One Tasks API request, like GoogleCalendarManager.googleRequest. path: after /tasks/v1, ids
	// encoded (see taskPath). query: optional params. body: the JSON body (not for GET).
	// callback(err, data, xhr), always called: err is Google's error body when it sent one. When no
	// token could be had, xhr is null (auth error) or { status: 0, noToken: true } (offline).
	// Only the HTTP status is logged: no ids, titles, notes or bodies.
	function tasksRequest(method, path, query, body, callback) {
		withToken(function() {
			var opt = {
				method: method,
				url: apiUrl + path + queryString(query),
				headers: {
					"Authorization": "Bearer " + session.accessToken,
				},
			}
			var send = Requests.getJSON
			if (method !== 'GET') {
				opt.data = body
				send = Requests.postJSON
			}
			send(opt, function(err, data, xhr) {
				logger.debug(calendarManagerId, method, 'response', xhr && xhr.status)
				if (!err && data && data.error) {
					err = data
				}
				callback(err, data, xhr)
			})
		}, function(err, isNetworkError) {
			callback(err, null, isNetworkError ? { status: 0, noToken: true } : null)
		})
	}

	function queryString(params) {
		var parts = []
		for (var key in (params || {})) {
			var value = params[key]
			if (typeof value !== 'undefined' && value !== null && value !== '') {
				parts.push(encodeURIComponent(key) + '=' + encodeURIComponent(value))
			}
		}
		return parts.length ? '?' + parts.join('&') : ''
	}

	// '/lists/{tasklistId}/tasks[/{taskId}]' for a raw (unscoped) task list id.
	function taskPath(rawTasklistId, taskId) {
		var path = '/lists/' + encodeURIComponent(rawTasklistId) + '/tasks'
		if (taskId) {
			path += '/' + encodeURIComponent(taskId)
		}
		return path
	}

	//--- Errors
	function showHttpError(httpCode, msg, suggestion, errorType) {
		var errorMessage = i18n("HTTP Error %1: %2", httpCode, msg)
		if (suggestion) {
			errorMessage += '\n' + suggestion
		}
		googleTasksManager.error(errorMessage, errorType)
	}
	// err, data, xhr: as tasksRequest gives them.
	function handleError(err, data, xhr) {
		if (!xhr) {
			handleAuthError(err, false, false) // No access token
			return
		}
		var httpCode = xhr.status
		if (httpCode === 0) {
			var msg = i18n("Could not connect")
			var suggestion = i18n("Will try again soon.")
			showHttpError(httpCode, msg, suggestion, ErrorType.NetworkError)
			return
		}

		// https://developers.google.com/tasks/reference/rest/errors
		var body = GoogleError.googleErrorBody(err, data)
		if (body && body.error.errors && body.error.errors.length >= 1) {
			httpCode = body.error.code
			var err0 = body.error.errors[0]

			if (httpCode === 401 && err0.reason === 'authError') {
				var suggestion = i18n("Widget has been updated. Please logout and login to Google Calendar again.")
				showHttpError(httpCode, err0.message, suggestion, ErrorType.ClientError)
			} else if (httpCode === 403 && err0.domain === 'usageLimits') {
				var suggestion = i18n("Too many web requests. Will try again soon.")
				showHttpError(httpCode, err0.message, suggestion, ErrorType.ClientError)
			} else {
				var suggestion = i18n("Will try again soon.")
				showHttpError(httpCode, err0.message, suggestion, ErrorType.UnknownError)
			}
			return
		}

		showHttpError(httpCode, String(err), i18n("Will try again soon."), ErrorType.UnknownError)
	}
	function handleAuthError(err, markDone, isNetworkError) {
		if (markDone) {
			googleTasksManager.asyncRequestsDone += 1
		}
		if (isNetworkError) {
			// The token couldn't be refreshed because we're offline.
			showHttpError(0, i18n("Could not connect"), i18n("Will try again soon."), ErrorType.NetworkError)
			return
		}
		var message = i18n("Google authentication failed: %1", err)
		googleTasksManager.error(message, ErrorType.ClientError)
	}
	// Log a failed request (HTTP status only) and show its error.
	function reportError(what, err, data, xhr) {
		logger.log(calendarManagerId, what + '_err', xhr && xhr.status)
		handleError(err, data, xhr)
	}
	// A whole account failed to fetch: keep showing its previous events.
	function restorePrevious(idList) {
		for (var i = 0; i < idList.length; i++) {
			restorePreviousCalendar(scopedTasklistId(idList[i]))
		}
	}

	//-------------------------
	// CalendarManager
	function getCalendarList() {
		var account = getAccount()
		if (!account || !account.tasklistList) {
			return []
		}
		var tasklistList = account.tasklistList
		var calendarList = []
		for (var i = 0; i < tasklistList.length; i++) {
			calendarList.push(decorateTasklist(tasklistList[i]))
		}
		return calendarList
	}

	// Every task gets its list's color (the theme's highlight).
	function parseCalendarData(calendarId, data) {
		var calendar = getCalendar(calendarId)
		var color = calendar && calendar.backgroundColor ? calendar.backgroundColor : Kirigami.Theme.highlightColor.toString()
		for (var i = 0; i < data.items.length; i++) {
			data.items[i].backgroundColor = color
		}
	}

	//-------------------------
	// Tasks
	function fetchGoogleAccountTasks(tasklistIdList) {
		googleTasksManager.asyncRequests += 1
		var generation = googleTasksManager.fetchGeneration
		withToken(function() {
			var tasks = tasklistIdList.map(function(tasklistId) {
				return fetchGoogleTasks.bind(this, tasklistId)
			})
			Async.parallel(tasks, function(errObj, results) {
				if (generation !== googleTasksManager.fetchGeneration) {
					logger.debug('fetchGoogleAccountTasks', 'dropping stale response')
					return
				}
				if (errObj) {
					restorePrevious(tasklistIdList)
					googleTasksManager.asyncRequestsDone += 1
					reportError('fetchGoogleAccountTasks', errObj.err, errObj.data, errObj.xhr)
				} else {
					fetchGoogleAccountTasks_done(results)
				}
			})
		}, function(err, isNetworkError) {
			restorePrevious(tasklistIdList)
			handleAuthError(err, true, isNetworkError)
		})
	}
	function fetchGoogleAccountTasks_done(results) {
		for (var i = 0; i < results.length; i++) {
			var eventList = parseTasklistAsEvents(results[i].data)
			setCalendarData(results[i].scopedTasklistId, eventList)
		}
		googleTasksManager.asyncRequestsDone += 1
	}

	// Google's order of a list (position), tasks without one first.
	function sortTasklist(tasklist) {
		tasklist.sort(function(a, b) {
			var aHas = typeof a.position !== 'undefined'
			var bHas = typeof b.position !== 'undefined'
			if (aHas && bHas) {
				return a.position < b.position ? -1 : a.position > b.position ? 1 : 0
			}
			return aHas ? 1 : bHas ? -1 : 0
		})
	}

	function parseTasklistAsEvents(tasklistData) {
		var eventList = []
		var items = (tasklistData && tasklistData.items) || [] // Google leaves items out of empty lists
		for (var i = 0; i < items.length; i++) {
			eventList.push(parseTaskAsEventData(items[i]))
		}
		sortTasklist(eventList) // AgendaModel sorts again, by position too.
		return {
			items: eventList,
		}
	}

	// A task as an all-day event on the day it's shown on (Tasks.placementDay), so the month, week
	// and agenda views agree. Mutates and returns taskData.
	function parseTaskAsEventData(taskData) {
		var eventData = taskData

		eventData.summary = taskData.title
		eventData.description = taskData.notes || ''
		eventData.canEdit = true

		var editTasksUrl = 'https://tasks.google.com/embed/?origin=' + encodeURIComponent('https://calendar.google.com') + '&fullWidth=1'
		eventData.htmlLink = editTasksUrl

		eventData.isCompleted = Tasks.isDone(taskData)

		// The due date only records date information: the time portion is always dropped.
		var dueDay = Tasks.dueDay(taskData)
		if (dueDay) {
			eventData.dueDate = dueDay
			// Local time zone, like CalendarManager.defaultEventParsing. Due at the end of the day.
			eventData.dueDateTime = new Date(dueDay + ' 00:00:00')
			eventData.dueEndTime = new Date(Tasks.addDays(dueDay, 1) + ' 00:00:00')
		} else {
			delete eventData.dueDate
			delete eventData.dueDateTime
			delete eventData.dueEndTime
		}

		var day = Tasks.placementDay(taskData, new Date(), !!plasmoid.configuration.agendaPlaceOverdueTasksOnToday)
		eventData.start = {
			date: day,
		}
		eventData.end = {
			date: Tasks.addDays(day, 1),
		}
		return eventData
	}

	// callback(errObj, { scopedTasklistId, data }): errObj is { err, data, xhr } or null.
	function fetchGoogleTasks(tasklistId, callback) {
		fetchTasklistPages(tasklistId, null, null, function(err, data, xhr) {
			if (err) {
				return callback({ err: err, data: data, xhr: xhr }, null)
			}
			callback(null, {
				scopedTasklistId: scopedTasklistId(tasklistId),
				data: data,
			})
		})
	}

	// Every page of a list, done and hidden tasks too. callback(err, data, xhr): data.items is all of them.
	function fetchTasklistPages(tasklistId, pageToken, allItems, callback) {
		tasksRequest('GET', taskPath(tasklistId), {
			showCompleted: true,
			showHidden: true,
			maxResults: 100, // API max. Default 20 means many sequential pages.
			pageToken: pageToken,
		}, null, function(err, data, xhr) {
			if (err || !data) {
				return callback(err || 'fetchTasklistPages: no data', data, xhr)
			}
			var items = (allItems || []).concat(data.items || [])
			if (data.nextPageToken) {
				fetchTasklistPages(tasklistId, data.nextPageToken, items, callback)
			} else {
				data.items = items
				callback(null, data, xhr)
			}
		})
	}

	// A task of this account parsed as an item of calendarId (scoped list id).
	function parseTaskItem(calendarId, data) {
		var eventData = parseTaskAsEventData(data)
		parseSingleEvent(calendarId, eventData)
		return eventData
	}

	// Show a task of a selected list that isn't loaded yet.
	function addTaskItem(calendarId, eventData) {
		if (!isTasklistSelected(calendarId)) {
			return false
		}
		if (!eventsByCalendar[calendarId]) {
			eventsByCalendar[calendarId] = { items: [] }
		}
		if (getEvent(calendarId, eventData.id)) {
			return false
		}
		addEvent(calendarId, eventData)
		return true
	}

	//--- Create
	// date: the due day (a Date), or null for no due date.
	function createEvent(calendarId, date, text) {
		var body = { title: text }
		if (date) {
			body.due = Tasks.dayString(date) + 'T00:00:00.000Z'
		}
		createEventFromData(calendarId, body, null, null)
	}

	// Create a task from a body: { title, notes?, due?, status? } (see Tasks.editBody).
	// done(err, item): optional, always called; item is the new task as shown, or null.
	// params: optional query params of tasks.insert, eg: { parent, previous }.
	function createEventFromData(calendarId, body, done, params) {
		tasksRequest('POST', taskPath(unscopedTasklistId(calendarId)), params, body, function(err, data, xhr) {
			var item = null
			if (err || !data) {
				reportError('createEvent', err, data, xhr)
			} else {
				item = parseTaskItem(calendarId, data)
				if (addTaskItem(calendarId, item)) {
					eventCreated(calendarId, item)
				}
			}
			if (done) {
				done(err || (item ? null : 'createEvent: no data'), item)
			}
		})
	}

	//--- Get
	// The server copy of a task, parsed. callback(err, item, xhr), always called.
	function fetchEvent(calendarId, eventId, callback) {
		tasksRequest('GET', taskPath(unscopedTasklistId(calendarId), eventId), null, null, function(err, data, xhr) {
			if (err || !data) {
				if (!xhr || xhr.noToken) {
					handleError(err, data, xhr) // No access token: say so, as for the other requests
				}
				callback(err || 'fetchEvent: no data', null, xhr)
				return
			}
			callback(null, parseTaskItem(calendarId, data), xhr)
		})
	}

	//--- Delete
	// done(err): optional, always called.
	function deleteEvent(calendarId, eventId, done) {
		if (!getEvent(calendarId, eventId)) {
			logger.log(calendarManagerId, 'deleteEvent', 'task not loaded')
			if (done) {
				done('deleteEvent: task not loaded')
			}
			return
		}
		// Success is 204 (No Content).
		tasksRequest('DELETE', taskPath(unscopedTasklistId(calendarId), eventId), null, undefined, function(err, data, xhr) {
			if (err) {
				reportError('deleteEvent', err, data, xhr)
			} else {
				var deleted = getEvent(calendarId, eventId)
				if (deleted) {
					removeEvent(calendarId, eventId)
					eventDeleted(calendarId, eventId, deleted)
				}
			}
			if (done) {
				done(err || null)
			}
		})
	}

	// Undo a delete (see EventModel.restoreEvent): Google keeps a deleted task, so it's marked
	// not deleted again (same id, position and parent). If that fails, copy (Undo.restoreCopy) is
	// created again: title, notes, due and done state. done(err): optional, always called.
	function restoreEvent(calendarId, eventId, copy, done) {
		var finish = function(err, item) {
			if (done) {
				done(err || null)
			}
		}
		tasksRequest('PATCH', taskPath(unscopedTasklistId(calendarId), eventId), null, { deleted: false }, function(err, data, xhr) {
			if (!err && data && !data.deleted) {
				addTaskItem(calendarId, parseTaskItem(calendarId, data))
				finish(null)
			} else if (copy) {
				createEventFromData(calendarId, Tasks.restoreBody(copy), finish, null)
			} else {
				reportError('restoreEvent', err || 'still deleted', data, xhr)
				finish(err || 'restoreEvent: still deleted')
			}
		})
	}

	//--- Move to another list
	// Move a task to another list of the same account (tasks.move with destinationTasklist).
	// The task leaves the source list here and, when the destination is loaded, shows there.
	// Its subtasks move with it on the server: done(err, item) should refetch to show them.
	// done is always called. params: optional query params, eg: { parent, previous }.
	function moveEvent(calendarId, eventId, destinationCalendarId, done, params) {
		// Only within this account: the scoped id of another account isn't one of our lists.
		if (accountId && destinationCalendarId.indexOf(accountId + "::") !== 0) {
			logger.log(calendarManagerId, 'moveEvent', 'destination is in another account')
			if (done) {
				done('moveEvent: destination is in another account', null)
			}
			return
		}
		var query = { destinationTasklist: unscopedTasklistId(destinationCalendarId) }
		for (var key in (params || {})) {
			query[key] = params[key]
		}
		tasksRequest('POST', taskPath(unscopedTasklistId(calendarId), eventId) + '/move', query, "", function(err, data, xhr) {
			var item = null
			if (err) {
				reportError('moveEvent', err, data, xhr)
			} else {
				if (getEvent(calendarId, eventId)) {
					removeEvent(calendarId, eventId)
				}
				if (data && data.id) {
					item = parseTaskItem(destinationCalendarId, data)
					addTaskItem(destinationCalendarId, item)
				}
			}
			if (done) {
				done(err || null, item)
			}
		})
	}

	//--- Update
	// PATCH only the changed fields (args, Google names: title, notes, due, status, completed).
	// A field set to undefined is cleared (sent as null).
	// options: optional { done(err, item) }, always called once the server answered.
	function setEventProperties(calendarId, eventId, args, options) {
		var done = options && options.done
		var event = getEvent(calendarId, eventId)
		if (!event) {
			logger.log(calendarManagerId, 'setEventProperties', 'task not loaded')
			if (done) {
				done('setEventProperties: task not loaded', null)
			}
			return
		}
		var body = {}
		for (var key in (args || {})) {
			body[key] = typeof args[key] === 'undefined' ? null : args[key]
		}
		tasksRequest('PATCH', taskPath(unscopedTasklistId(calendarId), eventId), null, body, function(err, data, xhr) {
			if (err || !data) {
				reportError('setEventProperties', err, data, xhr)
				if (done) {
					done(err || 'setEventProperties: no data', null)
				}
				return
			}
			// The task may have been reloaded meanwhile: update the loaded copy.
			var current = getEvent(calendarId, eventId) || event
			var eventData = parseTaskAsEventData(data)
			Shared.merge(current, eventData)
			Shared.removeMissingKeys(current, eventData) // eg: notes or due cleared
			parseSingleEvent(calendarId, current)
			eventUpdated(calendarId, eventId, current)
			if (done) {
				done(null, current)
			}
		})
	}

	//--- Task lists (users/@me/lists): create, rename, delete, clear completed
	// https://developers.google.com/tasks/reference/rest/v1/tasklists
	// After a change the account's stored lists (tasklistList, tasklistIdList) are updated, so the
	// settings and the views show it: a new list is shown, a deleted one leaves the selection.
	// done(err, ...) is optional and always called. Only the HTTP status is logged.

	// { rename, delete, color, clearCompleted } for a list of this account (TaskLists.capabilities).
	function taskListCapabilities(calendarId) {
		var calendar = getCalendar(calendarId)
		return TaskLists.capabilities(calendarManagerId, unscopedTasklistId(calendarId), calendar ? calendar.accessRole : 'none')
	}

	function storedTasklists() {
		var account = getAccount()
		return {
			lists: account && Array.isArray(account.tasklistList) ? account.tasklistList : [],
			ids: account && Array.isArray(account.tasklistIdList) ? account.tasklistIdList : [],
		}
	}
	// next: { lists, ids } (TaskLists.withAdded / withChanged / withRemoved).
	function storeTasklists(next) {
		if (getAccount() && typeof accountsStore.updateAccount === 'function') {
			accountsStore.updateAccount(accountId, { tasklistList: next.lists, tasklistIdList: next.ids })
		}
	}

	// One task list request. onSuccess(data) gives what done gets after err (null).
	function tasklistRequest(what, method, path, body, done, onSuccess) {
		tasksRequest(method, path, null, body, function(err, data, xhr) {
			var result = null
			if (err) {
				logger.log(calendarManagerId, what + '_err', xhr ? xhr.status : 'no token')
			} else {
				result = onSuccess(data)
			}
			if (done) {
				done(err || null, result)
			}
		})
	}
	function tasklistPath(rawTasklistId) {
		return '/users/@me/lists/' + encodeURIComponent(rawTasklistId)
	}

	// done(err, list): list is { id (scoped), name }.
	function createTaskList(title, done) {
		var name = TaskLists.cleanTitle(title)
		if (!name) {
			if (done) {
				done('createTaskList: no title', null)
			}
			return
		}
		tasklistRequest('createTaskList', 'POST', '/users/@me/lists', { title: name }, done, function(data) {
			var rawId = data && data.id ? String(data.id) : ''
			var created = String(data && data.title || name)
			if (!rawId) {
				return null
			}
			var stored = storedTasklists()
			storeTasklists(TaskLists.withAdded(stored.lists, stored.ids, { id: rawId, title: created }))
			return { id: scopedTasklistId(rawId), name: created }
		})
	}

	// done(err)
	function renameTaskList(calendarId, title, done) {
		var name = TaskLists.cleanTitle(title)
		if (!name) {
			if (done) {
				done('renameTaskList: no title', null)
			}
			return
		}
		var rawId = unscopedTasklistId(calendarId)
		tasklistRequest('renameTaskList', 'PATCH', tasklistPath(rawId), { title: name }, done, function(data) {
			var stored = storedTasklists()
			storeTasklists(TaskLists.withChanged(stored.lists, stored.ids, rawId, { title: String(data && data.title || name) }))
			return null
		})
	}

	// The list and its tasks are gone: unloaded here, and it leaves the selection. done(err)
	function deleteTaskList(calendarId, done) {
		var rawId = unscopedTasklistId(calendarId)
		tasklistRequest('deleteTaskList', 'DELETE', tasklistPath(rawId), "", done, function() {
			delete eventsByCalendar[calendarId]
			delete previousEventsByCalendar[calendarId]
			var stored = storedTasklists()
			storeTasklists(TaskLists.withRemoved(stored.lists, stored.ids, rawId))
			return null
		})
	}

	// Google marks the list's completed tasks hidden (lists/{id}/clear); they leave the view.
	// done(err)
	function clearCompleted(calendarId, done) {
		var rawId = unscopedTasklistId(calendarId)
		tasklistRequest('clearCompleted', 'POST', '/lists/' + encodeURIComponent(rawId) + '/clear', "", done, function() {
			var completed = eventItems(calendarId).filter(function(item) { return Tasks.isDone(item) })
			for (var i = 0; i < completed.length; i++) {
				removeEvent(calendarId, completed[i].id)
			}
			return null
		})
	}
}
