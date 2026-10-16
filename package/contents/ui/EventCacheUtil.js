// Event cache (instant start): what is kept on disk and how it's read back. Pure functions, no I/O.
// Only Google calendar events (calendar ids "account::calendar"), only the fields the views need:
// no descriptions, no attendee e-mails, never tokens.

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

var PLAIN_FIELDS = ['location', 'colorId', 'backgroundColor', 'recurringEventId', 'status', 'htmlLink', 'hangoutLink']

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
	// Not the whole event: changing it must start from the server copy (GoogleCalendarManager).
	picked.fromCache = true
	return picked
}

function isCacheableEvent(event) {
	return !!event && !!event.id && !!event.start && !!event.end
		&& typeof event.start === 'object' && typeof event.end === 'object'
		&& event.kind !== 'tasks#task'
}

// JSON text for eventsByCalendar ({ calendarId: { items: [...] } }).
function serialize(eventsByCalendar, dateMin, dateMax, now) {
	var calendars = {}
	for (var calendarId in eventsByCalendar) {
		if (!isCacheableCalendarId(calendarId)) {
			continue
		}
		var data = eventsByCalendar[calendarId]
		calendars[calendarId] = toList(data && data.items).filter(isCacheableEvent).map(pickEvent)
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
		calendars[calendarId] = Array.isArray(items) ? items.filter(isCacheableEvent).map(pickEvent) : []
	}
	return { savedAt: data.savedAt, dateMin: data.dateMin, dateMax: data.dateMax, calendars: calendars }
}

// Scoped ids ("account::calendar") of the calendars selected in the Google account settings.
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
	}
	return ids
}

if (typeof module !== 'undefined') {
	module.exports = {
		VERSION: VERSION,
		MAX_AGE_MS: MAX_AGE_MS,
		isCacheableCalendarId: isCacheableCalendarId,
		pickEvent: pickEvent,
		serialize: serialize,
		deserialize: deserialize,
		selectedCalendarIds: selectedCalendarIds,
	}
}
