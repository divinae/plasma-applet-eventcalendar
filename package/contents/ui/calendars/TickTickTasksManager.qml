import QtQuick
import org.kde.kirigami as Kirigami

import "../ErrorType.js" as ErrorType
import "../Shared.js" as Shared
import "../TaskLists.js" as TaskLists
import "../Tasks.js" as Tasks
import "../TimeZone.js" as TimeZone
import "../lib"
import "../lib/Async.js" as Async
import "../lib/TickTickAccountState.js" as TickTickAccountState

// TickTick (and Dida365) tasks through the Open API, one account per manager:
// https://developer.ticktick.com/docs/openapi.md
// Same contract as GoogleTasksManager, so the task UI works unchanged: projects are task lists
// (ids accountId::projectId, the Inbox is accountId::inbox), and tasks are event-shaped items
// (kind 'tasks#task') with the Google fields the UI reads (title, notes, due, status, completed,
// see Tasks.fromTickTick), plus dueTime ('HH:mm') for timed tasks and the TickTick fields
// needed to change them in item.tickTick. Changes come in Google shape (Tasks.editBody,
// toggleBody, restoreBody) and go to TickTick as Tasks.toTickTick gives them.
// The API lists only open tasks: done ones show until the next fetch.
CalendarManager {
	id: tickTickManager

	calendarManagerId: "TickTick"

	property var session
	property var accountsStore
	property string accountId: ""
	property string accountLabel: ""

	// The Inbox's real project id ('inbox123...'), learned from its tasks; 'inbox' works in paths.
	property string inboxProjectId: ""

	Logger {
		id: logger
		name: 'eventcalendar-ticktick'
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

	function getProjectIdList() {
		var account = getAccount()
		return account && account.projectIdList ? account.projectIdList : []
	}

	function scopedProjectId(rawId) {
		return accountId ? accountId + "::" + rawId : rawId
	}

	function unscopedProjectId(scopedId) {
		var prefix = accountId + "::"
		if (accountId && String(scopedId).indexOf(prefix) === 0) {
			return String(scopedId).substr(prefix.length)
		}
		return String(scopedId)
	}

	// The project id the API wants for a list: the Inbox's real id when known.
	function apiProjectId(scopedId) {
		var raw = unscopedProjectId(scopedId)
		return raw === 'inbox' && inboxProjectId ? inboxProjectId : raw
	}

	function isProjectSelected(calendarId) {
		return getProjectIdList().indexOf(unscopedProjectId(calendarId)) >= 0
	}

	function decorateProject(project) {
		var label = accountLabel || TickTickAccountState.serverName(getAccount() && getAccount().server)
		return {
			id: scopedProjectId(project.id),
			summary: label + " - " + project.name,
			backgroundColor: project.color || Kirigami.Theme.highlightColor.toString(),
			// Shared projects have a permission: 'write', else read-only ('read', 'comment').
			accessRole: !project.permission ? 'owner' : project.permission === 'write' ? 'writer' : 'reader',
			isTasklist: true,
		}
	}

	onFetchAllCalendars: {
		var account = getAccount()
		if (!account) {
			return
		}
		var idList = getProjectIdList()
		if (idList.length) {
			fetchAccountTasks(idList)
		}
	}

	//--- Requests
	function projectTaskPath(projectId, taskId) {
		return '/project/' + encodeURIComponent(projectId) + '/task/' + encodeURIComponent(taskId)
	}

	//--- Errors
	function showHttpError(httpCode, msg, suggestion, errorType) {
		var errorMessage = i18n("HTTP Error %1: %2", httpCode, msg)
		if (suggestion) {
			errorMessage += '\n' + suggestion
		}
		tickTickManager.error(errorMessage, errorType)
	}
	// err, data, xhr: as session.request gives them.
	function handleError(err, data, xhr) {
		if (!xhr) {
			tickTickManager.error(i18n("TickTick: sign in again"), ErrorType.ClientError) // No token
			return
		}
		var httpCode = xhr.status
		if (httpCode === 0) {
			showHttpError(0, i18n("Could not connect"), i18n("Will try again soon."), ErrorType.NetworkError)
		} else if (httpCode === 401) {
			showHttpError(httpCode, i18n("TickTick: sign in again"), i18n("Connect the account again with a new API token in the Tasks settings."), ErrorType.ClientError)
		} else if (httpCode === 429) {
			showHttpError(httpCode, String(err), i18n("Too many web requests. Will try again soon."), ErrorType.ClientError)
		} else {
			var message = data && typeof data === 'object' && data.errorMessage ? String(data.errorMessage) : String(err)
			showHttpError(httpCode, message, i18n("Will try again soon."), ErrorType.UnknownError)
		}
	}
	// Log a failed request (HTTP status only) and show its error.
	function reportError(what, err, data, xhr) {
		logger.log(calendarManagerId, what + '_err', xhr ? xhr.status : 'no token')
		handleError(err, data, xhr)
	}

	//-------------------------
	// CalendarManager
	function getCalendarList() {
		var account = getAccount()
		if (!account || !account.projectList) {
			return []
		}
		return account.projectList.map(decorateProject)
	}

	// Every task gets its project's color.
	function parseCalendarData(calendarId, data) {
		var calendar = getCalendar(calendarId)
		var color = calendar && calendar.backgroundColor ? calendar.backgroundColor : Kirigami.Theme.highlightColor.toString()
		for (var i = 0; i < data.items.length; i++) {
			data.items[i].backgroundColor = color
		}
	}

	//-------------------------
	// Fetch
	function fetchAccountTasks(projectIdList) {
		tickTickManager.asyncRequests += 1
		var generation = tickTickManager.fetchGeneration
		Async.settleAll(projectIdList.map(function(projectId) {
			return fetchProjectTasks.bind(null, projectId)
		}), function(results) {
			if (generation !== tickTickManager.fetchGeneration) {
				logger.debug('fetchAccountTasks', 'dropping stale response')
				return
			}
			var firstError = null
			for (var i = 0; i < results.length; i++) {
				var scopedId = scopedProjectId(projectIdList[i])
				if (results[i].err) {
					restorePreviousCalendar(scopedId)
					firstError = firstError || results[i].err
				} else {
					setCalendarData(scopedId, parseProjectAsEvents(results[i].data))
				}
			}
			// The error first: a network error counts for this fetch round (Logic's offline banner).
			if (firstError) {
				reportError('fetchAccountTasks', firstError.err, firstError.data, firstError.xhr)
			}
			tickTickManager.asyncRequestsDone += 1
		})
	}

	// callback(errObj, data): errObj is { err, data, xhr } or null. An Inbox the server doesn't
	// have (an HTTP error other than 401) is an empty list.
	function fetchProjectTasks(projectId, callback) {
		session.request('GET', '/project/' + encodeURIComponent(projectId) + '/data', null, function(err, data, xhr) {
			if (!err && data && typeof data === 'object') {
				callback(null, data)
			} else if (projectId === 'inbox' && xhr && xhr.status >= 400 && xhr.status !== 401) {
				logger.debug('fetchProjectTasks', 'no inbox', xhr.status)
				callback(null, { tasks: [] })
			} else {
				callback({ err: err || 'fetchProjectTasks: no data', data: data, xhr: xhr }, null)
			}
		})
	}

	function parseProjectAsEvents(projectData) {
		var tasks = Array.isArray(projectData && projectData.tasks) ? projectData.tasks : []
		var items = []
		for (var i = 0; i < tasks.length; i++) {
			items.push(parseTaskAsEventData(tasks[i]))
		}
		items.sort(function(a, b) { // TickTick's order (sortOrder); AgendaModel sorts again
			var ap = a.position || '', bp = b.position || ''
			return ap < bp ? -1 : ap > bp ? 1 : 0
		})
		return {
			items: items,
		}
	}

	// TickTick's sortOrder (a number, may be negative) as a position string like Google's.
	function positionOf(sortOrder) {
		var n = Number(sortOrder)
		if (!isFinite(n)) {
			return undefined
		}
		var s = String(Math.max(0, Math.round(n + 9007199254740992)))
		while (s.length < 20) {
			s = '0' + s
		}
		return s
	}

	// A TickTick task as an event-shaped item, all-day on the day it's shown on (Tasks.placementDay).
	function parseTaskAsEventData(raw) {
		raw = raw || {}
		if (raw.projectId && String(raw.projectId).indexOf('inbox') === 0) {
			tickTickManager.inboxProjectId = String(raw.projectId)
		}
		var fields = Tasks.fromTickTick(raw, TimeZone.wallClock)
		var eventData = {
			kind: 'tasks#task',
			id: String(raw.id || ''),
			projectId: String(raw.projectId || ''),
			title: fields.title,
			notes: fields.notes,
			status: fields.status,
			// What's needed to change the task (Tasks.toTickTick) and nothing that's shown.
			tickTick: {
				projectId: raw.projectId || '',
				dueDate: raw.dueDate || '',
				startDate: raw.startDate || '',
				isAllDay: raw.isAllDay,
				timeZone: raw.timeZone || '',
				status: raw.status || 0,
				completedTime: raw.completedTime || '',
				sortOrder: raw.sortOrder,
			},
		}
		if (fields.due) {
			eventData.due = fields.due
		}
		if (fields.dueTime) {
			eventData.dueTime = fields.dueTime
		}
		if (fields.completed) {
			eventData.completed = fields.completed
		}
		var position = positionOf(raw.sortOrder)
		if (position) {
			eventData.position = position
		}

		eventData.summary = fields.title
		eventData.description = fields.notes
		eventData.canEdit = true
		var account = getAccount()
		eventData.htmlLink = TickTickAccountState.webUrl(account && account.server)
			+ '#p/' + encodeURIComponent(eventData.projectId) + '/tasks/' + encodeURIComponent(eventData.id)
		eventData.isCompleted = Tasks.isDone(eventData)

		var dueDay = Tasks.dueDay(eventData)
		if (dueDay) {
			eventData.dueDate = dueDay
			eventData.dueDateTime = new Date(dueDay + ' 00:00:00')
			eventData.dueEndTime = new Date(Tasks.addDays(dueDay, 1) + ' 00:00:00')
		}

		var placeOverdueOnToday = typeof plasmoid !== "undefined" && plasmoid && plasmoid.configuration
			? !!plasmoid.configuration.agendaPlaceOverdueTasksOnToday
			: false
		var day = Tasks.placementDay(eventData, new Date(), placeOverdueOnToday)
		eventData.start = {
			date: day,
		}
		eventData.end = {
			date: Tasks.addDays(day, 1),
		}
		return eventData
	}

	// A task of this account parsed as an item of calendarId (scoped project id).
	function parseTaskItem(calendarId, raw) {
		var eventData = parseTaskAsEventData(raw)
		parseSingleEvent(calendarId, eventData)
		return eventData
	}

	// Show a task of a selected project that isn't loaded yet.
	function addTaskItem(calendarId, eventData) {
		if (!isProjectSelected(calendarId)) {
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

	// The TickTick fields of a loaded item with changes (Tasks.toTickTick) applied, as a raw task.
	function rawWith(item, changes) {
		var raw = {}
		var saved = (item && item.tickTick) || {}
		for (var key in saved) {
			raw[key] = saved[key]
		}
		raw.id = item.id
		raw.projectId = item.projectId || saved.projectId
		raw.title = item.title
		raw.content = item.notes
		for (var change in (changes || {})) {
			raw[change] = changes[change]
		}
		return raw
	}

	//--- Create
	// date: the due day (a Date), or null for no due date.
	function createEvent(calendarId, date, text) {
		var body = { title: text }
		if (date) {
			body.due = Tasks.dueValue(Tasks.dayString(date))
		}
		createEventFromData(calendarId, body, null, null)
	}

	// Create a task from a Google-shaped body: { title, notes?, due?, status? } (see Tasks.editBody).
	// done(err, item): optional, always called; item is the new task as shown, or null.
	// params: ignored (Google's parent / previous).
	function createEventFromData(calendarId, body, done, params) {
		var fields = Tasks.toTickTick(body, null, TimeZone.toUtc)
		var wantsDone = fields.status === 2
		delete fields.status
		delete fields.completedTime
		var projectId = apiProjectId(calendarId)
		if (projectId !== 'inbox') {
			fields.projectId = projectId // Without one, TickTick adds it to the Inbox
		}
		var finish = function(err, item) {
			if (done) {
				done(err || (item ? null : 'createEvent: no data'), item)
			}
		}
		session.request('POST', '/task', fields, function(err, data, xhr) {
			if (err || !data || !data.id) {
				reportError('createEvent', err || 'no data', data, xhr)
				finish(err || 'createEvent: no data', null)
				return
			}
			var created = function(raw) {
				var item = parseTaskItem(calendarId, raw)
				if (addTaskItem(calendarId, item)) {
					eventCreated(calendarId, item)
				}
				finish(null, item)
			}
			if (!wantsDone || data.status === 2) {
				created(data)
				return
			}
			// A done task brought back (undo a delete): created open, then completed.
			session.request('POST', projectTaskPath(data.projectId, data.id) + '/complete', null, function(completeErr, completeData, completeXhr) {
				if (completeErr) {
					reportError('createEvent_complete', completeErr, completeData, completeXhr)
				} else {
					data.status = 2
					data.completedTime = Tasks.formatTickTickDate(Date.now())
				}
				created(data)
			})
		})
	}

	//--- Get
	// The server copy of a task, parsed. callback(err, item, xhr), always called.
	function fetchEvent(calendarId, eventId, callback) {
		var loaded = getEvent(calendarId, eventId)
		var projectId = loaded && loaded.projectId ? loaded.projectId : apiProjectId(calendarId)
		session.request('GET', projectTaskPath(projectId, eventId), null, function(err, data, xhr) {
			if (err || !data || !data.id) {
				if (!xhr || xhr.status === 0 || xhr.status === 401) {
					handleError(err, data, xhr)
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
		var event = getEvent(calendarId, eventId)
		if (!event) {
			logger.log(calendarManagerId, 'deleteEvent', 'task not loaded')
			if (done) {
				done('deleteEvent: task not loaded')
			}
			return
		}
		session.request('DELETE', projectTaskPath(event.projectId || apiProjectId(calendarId), eventId), null, function(err, data, xhr) {
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

	// Undo a delete (see EventModel.restoreEvent): the Open API can't bring a deleted task back,
	// so copy (Undo.restoreCopy) is created again: title, notes, due and done state.
	// done(err): optional, always called.
	function restoreEvent(calendarId, eventId, copy, done) {
		if (!copy) {
			logger.log(calendarManagerId, 'restoreEvent', 'no copy')
			if (done) {
				done('restoreEvent: no copy')
			}
			return
		}
		createEventFromData(calendarId, Tasks.restoreBody(copy), function(err, item) {
			if (done) {
				done(err || null)
			}
		}, null)
	}

	//--- Move to another project
	// Within this account only. done(err, item): always called; item is the moved task.
	function moveEvent(calendarId, eventId, destinationCalendarId, done, params) {
		var finish = function(err, item) {
			if (done) {
				done(err || null, item || null)
			}
		}
		if (!accountId || String(destinationCalendarId).indexOf(accountId + "::") !== 0) {
			logger.log(calendarManagerId, 'moveEvent', 'destination is in another account')
			finish('moveEvent: destination is in another account', null)
			return
		}
		var event = getEvent(calendarId, eventId)
		if (!event) {
			logger.log(calendarManagerId, 'moveEvent', 'task not loaded')
			finish('moveEvent: task not loaded', null)
			return
		}
		var fromProjectId = event.projectId || apiProjectId(calendarId)
		var toProjectId = apiProjectId(destinationCalendarId)
		session.request('POST', '/task/move', [{
			fromProjectId: fromProjectId,
			toProjectId: toProjectId,
			taskId: eventId,
		}], function(err, data, xhr) {
			if (err) {
				reportError('moveEvent', err, data, xhr)
				finish(err, null)
				return
			}
			var moved = function(raw) {
				if (getEvent(calendarId, eventId)) {
					removeEvent(calendarId, eventId)
				}
				var item = parseTaskItem(destinationCalendarId, raw)
				addTaskItem(destinationCalendarId, item)
				finish(null, item)
			}
			// The server copy (the Inbox's real id, a new sort order); else the one we had.
			session.request('GET', projectTaskPath(toProjectId, eventId), null, function(getErr, getData, getXhr) {
				if (!getErr && getData && getData.id) {
					moved(getData)
				} else {
					moved(rawWith(event, { projectId: toProjectId }))
				}
			})
		})
	}

	//--- Update
	// args: Google-shaped changes (title, notes, due, status, completed), sent as TickTick fields
	// (id, projectId and what changed). Done (status 'completed' alone) uses the complete
	// endpoint. options: optional { done(err, item) }, always called once the server answered.
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
		var changes = Tasks.toTickTick(args, event.tickTick, TimeZone.toUtc)
		var projectId = event.projectId || apiProjectId(calendarId)
		var onlyCompletes = changes.status === 2 && Object.keys(changes).every(function(key) {
			return key === 'status' || key === 'completedTime'
		})
		var saved = function(err, data, xhr, fallbackRaw) {
			if (err) {
				reportError('setEventProperties', err, data, xhr)
				if (done) {
					done(err, null)
				}
				return
			}
			var raw = data && typeof data === 'object' && data.id ? data : fallbackRaw
			// The task may have been reloaded meanwhile: update the loaded copy.
			var current = getEvent(calendarId, eventId) || event
			var eventData = parseTaskAsEventData(raw)
			Shared.merge(current, eventData)
			Shared.removeMissingKeys(current, eventData) // eg: notes or due cleared
			parseSingleEvent(calendarId, current)
			eventUpdated(calendarId, eventId, current)
			if (done) {
				done(null, current)
			}
		}
		if (onlyCompletes) {
			if (!changes.completedTime) {
				changes.completedTime = Tasks.formatTickTickDate(Date.now())
			}
			session.request('POST', projectTaskPath(projectId, eventId) + '/complete', null, function(err, data, xhr) {
				saved(err, null, xhr, rawWith(event, changes))
			})
			return
		}
		var body = { id: eventId, projectId: projectId }
		for (var key in changes) {
			body[key] = changes[key]
		}
		if (body.status === 0) {
			body.completedTime = null
		}
		session.request('POST', '/task/' + encodeURIComponent(eventId), body, function(err, data, xhr) {
			saved(err, data, xhr, rawWith(event, body))
		})
	}

	//--- Task lists (projects): create, rename, recolor, delete
	// After a change the account's stored projects (projectList, projectIdList) are updated, so the
	// settings and the views show it: a new project is shown, a deleted one leaves the selection.
	// The Inbox can't be changed. No "clear completed": the API lists open tasks only.
	// done(err, ...) is optional and always called. Only the HTTP status is logged.

	// { rename, delete, color, clearCompleted } for a project of this account (TaskLists.capabilities).
	function taskListCapabilities(calendarId) {
		var calendar = getCalendar(calendarId)
		return TaskLists.capabilities(calendarManagerId, unscopedProjectId(calendarId), calendar ? calendar.accessRole : 'none')
	}

	function storedProjects() {
		var account = getAccount()
		return {
			lists: account && Array.isArray(account.projectList) ? account.projectList : [],
			ids: account && Array.isArray(account.projectIdList) ? account.projectIdList : [],
		}
	}
	// next: { lists, ids } (TaskLists.withAdded / withChanged / withRemoved).
	function storeProjects(next) {
		if (getAccount() && typeof accountsStore.updateAccount === 'function') {
			accountsStore.updateAccount(accountId, { projectList: next.lists, projectIdList: next.ids })
		}
	}

	// One project request. onSuccess(data) gives what done gets after err (null).
	function projectRequest(what, method, path, body, done, onSuccess) {
		session.request(method, path, body, function(err, data, xhr) {
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
	// Refuse a change the project can't have (the Inbox, read-only): done(err), no request.
	function refuse(what, calendarId, capability, done) {
		if (taskListCapabilities(calendarId)[capability]) {
			return false
		}
		logger.log(calendarManagerId, what, 'not allowed')
		if (done) {
			done(what + ': not allowed', null)
		}
		return true
	}
	function projectPath(rawId) {
		return '/project/' + encodeURIComponent(rawId)
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
		projectRequest('createTaskList', 'POST', '/project', { name: name }, done, function(data) {
			var rawId = data && data.id ? String(data.id) : ''
			if (!rawId) {
				return null
			}
			var project = TickTickAccountState.taskProjects([data])[0] || { id: rawId, name: name, color: '' }
			var stored = storedProjects()
			storeProjects(TaskLists.withAdded(stored.lists, stored.ids, project))
			return { id: scopedProjectId(rawId), name: project.name || name }
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
		if (refuse('renameTaskList', calendarId, 'rename', done)) {
			return
		}
		var rawId = unscopedProjectId(calendarId)
		projectRequest('renameTaskList', 'POST', projectPath(rawId), { name: name }, done, function(data) {
			var stored = storedProjects()
			storeProjects(TaskLists.withChanged(stored.lists, stored.ids, rawId, { name: String(data && data.name || name) }))
			return null
		})
	}

	// color: '#rrggbb'. done(err)
	function setTaskListColor(calendarId, color, done) {
		var hex = TaskLists.hexColor(color)
		if (!hex) {
			if (done) {
				done('setTaskListColor: not a color', null)
			}
			return
		}
		if (refuse('setTaskListColor', calendarId, 'color', done)) {
			return
		}
		var rawId = unscopedProjectId(calendarId)
		projectRequest('setTaskListColor', 'POST', projectPath(rawId), { color: hex }, done, function() {
			var stored = storedProjects()
			storeProjects(TaskLists.withChanged(stored.lists, stored.ids, rawId, { color: hex }))
			return null
		})
	}

	// The project and its tasks are gone: unloaded here, and it leaves the selection. done(err)
	function deleteTaskList(calendarId, done) {
		if (refuse('deleteTaskList', calendarId, 'delete', done)) {
			return
		}
		var rawId = unscopedProjectId(calendarId)
		projectRequest('deleteTaskList', 'DELETE', projectPath(rawId), null, done, function() {
			delete eventsByCalendar[calendarId]
			delete previousEventsByCalendar[calendarId]
			var stored = storedProjects()
			storeProjects(TaskLists.withRemoved(stored.lists, stored.ids, rawId))
			return null
		})
	}
}
