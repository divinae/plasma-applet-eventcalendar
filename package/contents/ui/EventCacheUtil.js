// Event cache (instant start): what is kept on disk and how it's read back. Pure functions, no I/O.
// Only Google calendar events and tasks (Google Tasks, TickTick) of accounts (calendar / list ids
// "account::calendar"), only the fields the views need: no descriptions or task notes, no
// attendee e-mails, never tokens.

var VERSION = 1
var MAX_AGE_MS = 14 * 24 * 60 * 60 * 1000

function isCacheableCalendarId(calendarId) {
	return typeof calendarId === 'string' && calendarId.indexOf('::') > 0
}

function toList(value) {
	if (!value) {
		return []
	}
	if (typeof value.length === 'number' && typeof value !== 'string') {
		return Array.prototype.slice.call(value)
	}
	if (typeof value.count === 'number' && typeof value.get === 'function') {
		var list = []
		for (var i = 0; i < value.count; i++) {
			list.push(value.get(i))
		}
		return list
	}
	return []
}

function copyDate(obj) {
	var result = {}
	if (obj.date) result.date = String(obj.date)
	if (obj.dateTime) result.dateTime = String(obj.dateTime)
	if (obj.timeZone) result.timeZone = String(obj.timeZone)
	return result
}

var PLAIN_FIELDS = ['location', 'colorId', 'backgroundColor', 'recurringEventId', 'status', 'htmlLink', 'hangoutLink', 'transparency', 'visibility', 'eventType']

// Working location (day header label): its type and office / custom label only (no building,
// floor or desk ids).
function copyWorkingLocation(props) {
	var result = {}
	if (props.type) result.type = String(props.type)
	if (props.homeOffice) result.homeOffice = {}
	var places = ['officeLocation', 'customLocation']
	for (var i = 0; i < places.length; i++) {
		var place = props[places[i]]
		if (place) {
			result[places[i]] = place.label ? { label: String(place.label) } : {}
		}
	}
	return result
}

// The cached copy of one event (whitelisted fields only).
function pickEvent(event) {
	var picked = {
		id: String(event.id),
		summary: String(typeof event._summary !== 'undefined' ? event._summary : (event.summary || '')),
		start: copyDate(event.start),
		end: copyDate(event.end),
	}
	for (var i = 0; i < PLAIN_FIELDS.length; i++) {
		var key = PLAIN_FIELDS[i]
		if (event[key] !== undefined && event[key] !== null && event[key] !== '') {
			picked[key] = String(event[key])
		}
	}
	if (typeof event.canEdit === 'boolean') {
		picked.canEdit = event.canEdit
	}
	// Google popup reminders, so a cached event doesn't fall back to the widget's default reminder.
	if (event.reminderMinutes) {
		picked.reminderMinutes = toList(event.reminderMinutes).map(Number).filter(function(minutes) { return isFinite(minutes) })
	}
	if (event.reminderOwn) {
		picked.reminderOwn = true
	}
	// Only your own response (to skip events you declined): no other guests, no e-mails.
	var attendees = toList(event.attendees)
	for (var a = 0; a < attendees.length; a++) {
		if (attendees[a] && attendees[a].self) {
			picked.attendees = [{ self: true, responseStatus: String(attendees[a].responseStatus || '') }]
			break
		}
	}
	// Meeting link (Join buttons): the solution name and the entry point URIs only.
	var conference = event.conferenceData
	if (conference) {
		var entryPoints = toList(conference.entryPoints).map(function(entryPoint) {
			return { entryPointType: String(entryPoint.entryPointType || ''), uri: String(entryPoint.uri || '') }
		}).filter(function(entryPoint) { return !!entryPoint.uri })
		var name = conference.conferenceSolution && conference.conferenceSolution.name
		if (entryPoints.length || name) {
			picked.conferenceData = { entryPoints: entryPoints }
			if (name) {
				picked.conferenceData.conferenceSolution = { name: String(name) }
			}
		}
	}
	if (event.workingLocationProperties && typeof event.workingLocationProperties === 'object') {
		picked.workingLocationProperties = copyWorkingLocation(event.workingLocationProperties)
	}
	// Not the whole event: changing it must start from the server copy (GoogleCalendarManager).
	picked.fromCache = true
	return picked
}

// A task's reminders (minutes before due) as stored: whole numbers only, no repeats, at most 20.
function taskReminderMinutes(list) {
	var out = []
	var items = toList(list)
	for (var i = 0; i < items.length && out.length < 20; i++) {
		var minutes = items[i]
		if (typeof minutes === 'number' && isFinite(minutes) && out.indexOf(Math.round(minutes)) < 0) {
			out.push(Math.round(minutes))
		}
	}
	return out
}

// The cached copy of one task (whitelisted fields only): no notes, no checklist. Its reminders as
// minutes only (reminderMinutes, from task.reminders), so a task started offline still reminds.
var TASK_TEXT_FIELDS = ['due', 'dueTime', 'status', 'completed', 'parentId', 'repeatRule', 'projectId', 'backgroundColor']

function pickTask(task) {
	var picked = {
		kind: 'tasks#task',
		id: String(task.id),
		title: String(typeof task._summary !== 'undefined' ? task._summary : (task.title || task.summary || '')),
		start: copyDate(task.start),
		end: copyDate(task.end),
	}
	picked.summary = picked.title
	for (var i = 0; i < TASK_TEXT_FIELDS.length; i++) {
		var key = TASK_TEXT_FIELDS[i]
		var value = task[key]
		if (value !== undefined && value !== null && value !== '' && typeof value !== 'object') {
			picked[key] = String(value)
		}
	}
	var priority = Number(task.priority)
	if (isFinite(priority) && priority > 0) {
		picked.priority = priority
	}
	// task.reminders when loaded; reminderMinutes when read back from the file.
	var reminders = taskReminderMinutes(task.reminders !== undefined ? task.reminders : task.reminderMinutes)
	if (reminders.length) {
		picked.reminderMinutes = reminders
	}
	// Not the whole task: changing it must start from the server copy (the tasks managers).
	picked.fromCache = true
	return picked
}

function isTask(event) {
	return !!event && event.kind === 'tasks#task'
}

function isCacheableEvent(event) {
	return !!event && !!event.id && !!event.start && !!event.end
		&& typeof event.start === 'object' && typeof event.end === 'object'
}

function pickItem(event) {
	return isTask(event) ? pickTask(event) : pickEvent(event)
}

// JSON text for eventsByCalendar ({ calendarId: { items: [...] } }).
function serialize(eventsByCalendar, dateMin, dateMax, now) {
	var calendars = {}
	for (var calendarId in eventsByCalendar) {
		if (!isCacheableCalendarId(calendarId)) {
			continue
		}
		var data = eventsByCalendar[calendarId]
		// Working locations (kept apart, see EventTypes.splitWorkingLocations) are stored with the
		// events and split again when read (EventModel.showCachedEvents).
		var events = toList(data && data.items).concat(toList(data && data.workingLocations))
		calendars[calendarId] = events.filter(isCacheableEvent).map(pickItem)
	}
	return JSON.stringify({
		version: VERSION,
		savedAt: (now || new Date()).getTime(),
		dateMin: dateMin ? new Date(dateMin).getTime() : 0,
		dateMax: dateMax ? new Date(dateMax).getTime() : 0,
		calendars: calendars,
	})
}

// { savedAt, dateMin, dateMax, calendars: { calendarId: [event] } } or null (missing, broken,
// another version, too old). isSelected(calendarId) keeps only calendars that are still selected.
function deserialize(text, now, isSelected) {
	if (!text || typeof text !== 'string') {
		return null
	}
	var data = null
	try {
		data = JSON.parse(text)
	} catch (e) {
		return null
	}
	if (!data || data.version !== VERSION || !data.calendars || typeof data.calendars !== 'object') {
		return null
	}
	var age = (now || new Date()).getTime() - (data.savedAt || 0)
	if (!(age >= 0 && age <= MAX_AGE_MS)) {
		return null
	}
	var calendars = {}
	for (var calendarId in data.calendars) {
		if (!isCacheableCalendarId(calendarId) || (isSelected && !isSelected(calendarId))) {
			continue
		}
		var items = data.calendars[calendarId]
		// Re-pick on read too, so an old or hand-edited file can't bring in more than the whitelist.
		calendars[calendarId] = Array.isArray(items) ? items.filter(isCacheableEvent).map(pickItem) : []
	}
	return { savedAt: data.savedAt, dateMin: data.dateMin, dateMax: data.dateMax, calendars: calendars }
}

// The account of a scoped calendar id ('account::calendar'), '' when it has none.
function accountOf(calendarId) {
	var index = typeof calendarId === 'string' ? calendarId.indexOf('::') : -1
	return index > 0 ? calendarId.slice(0, index) : ''
}

// Cache text without the calendars of accounts that are gone (accountIds: the ones still there):
// '' when nothing is left or the text can't be read (missing, broken, too old). The rest is kept
// as it was (savedAt too).
function pruneText(text, accountIds, now) {
	var keep = {}
	toList(accountIds).forEach(function(id) {
		if (id) {
			keep[String(id)] = true
		}
	})
	var cached = deserialize(text, now, function(calendarId) { return !!keep[accountOf(calendarId)] })
	if (!cached || !Object.keys(cached.calendars).length) {
		return ''
	}
	var byCalendar = {}
	for (var calendarId in cached.calendars) {
		byCalendar[calendarId] = { items: cached.calendars[calendarId] }
	}
	return serialize(byCalendar, cached.dateMin, cached.dateMax, new Date(cached.savedAt))
}

// Scoped ids ("account::calendar") of the calendars and task lists selected in the account
// settings: Google (calendarIdList, tasklistIdList) and TickTick (projectIdList) accounts.
function selectedCalendarIds(accounts) {
	var ids = {}
	var list = toList(accounts)
	for (var i = 0; i < list.length; i++) {
		var account = list[i]
		if (!account || !account.id) {
			continue
		}
		var primaryId = ''
		var calendarList = toList(account.calendarList)
		for (var c = 0; c < calendarList.length; c++) {
			if (calendarList[c] && calendarList[c].primary) {
				primaryId = calendarList[c].id
			}
		}
		var selected = toList(account.calendarIdList)
		for (var s = 0; s < selected.length; s++) {
			var rawId = selected[s] === 'primary' && primaryId ? primaryId : selected[s]
			ids[account.id + '::' + rawId] = true
			if (selected[s] === 'primary') {
				ids[account.id + '::primary'] = true
			}
		}
		var lists = toList(account.tasklistIdList).concat(toList(account.projectIdList))
		for (var l = 0; l < lists.length; l++) {
			if (lists[l]) {
				ids[account.id + '::' + lists[l]] = true
			}
		}
	}
	return ids
}

if (typeof module !== 'undefined') {
	module.exports = {
		VERSION: VERSION,
		MAX_AGE_MS: MAX_AGE_MS,
		isCacheableCalendarId: isCacheableCalendarId,
		pickEvent: pickEvent,
		pickTask: pickTask,
		serialize: serialize,
		deserialize: deserialize,
		selectedCalendarIds: selectedCalendarIds,
		accountOf: accountOf,
		pruneText: pruneText,
	}
}
