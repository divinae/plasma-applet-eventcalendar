.pragma library

// Google event types (event.eventType): 'default', 'birthday', 'fromGmail', 'focusTime',
// 'outOfOffice' and 'workingLocation'. Out of office and focus time are shown as events with an
// icon; working locations ("Home", "Office", ...) are not drawn as events but as a label on their
// days. Pure functions, tested in tests/event_types.test.js.

// The types fetched (events.list eventTypes). Listed explicitly: Google's guide asks for it to get
// working locations.
var FETCHED_TYPES = ['default', 'birthday', 'focusTime', 'fromGmail', 'outOfOffice', 'workingLocation']

function eventType(event) {
	return event && event.eventType ? String(event.eventType) : 'default'
}
function isOutOfOffice(event) {
	return eventType(event) === 'outOfOffice'
}
function isFocusTime(event) {
	return eventType(event) === 'focusTime'
}
function isWorkingLocation(event) {
	return eventType(event) === 'workingLocation'
}

// { type: 'home' | 'office' | 'custom' | '', label } of a working location event. label is the
// office or custom location name ('' when not set).
function workingLocation(event) {
	var props = event && event.workingLocationProperties || {}
	var type = String(props.type || '')
	if (type === 'homeOffice' || (!type && props.homeOffice)) {
		return { type: 'home', label: '' }
	}
	if (type === 'officeLocation' || (!type && props.officeLocation)) {
		return { type: 'office', label: String(props.officeLocation && props.officeLocation.label || '').trim() }
	}
	if (type === 'customLocation' || (!type && props.customLocation)) {
		return { type: 'custom', label: String(props.customLocation && props.customLocation.label || '').trim() }
	}
	return { type: '', label: '' }
}

// Text for a working location. words: { home, office, custom } (translated by the caller): the
// office or custom label when set, else the word for its type, else the event title.
function workingLocationText(event, words) {
	var location = workingLocation(event)
	words = words || {}
	if (location.type === 'home') {
		return words.home || 'Home'
	}
	if (location.label) {
		return location.label
	}
	if (location.type === 'office') {
		return words.office || 'Office'
	}
	if (location.type === 'custom') {
		return words.custom || 'Elsewhere'
	}
	return String(event && (event._summary || event.summary) || '').trim()
}

function dayKey(d) {
	return d.getFullYear() * 10000 + d.getMonth() * 100 + d.getDate()
}

// Day keys ('Shared.dayKey') an event covers: all-day events end at midnight (exclusive), timed
// ones count every day they touch.
function coveredDayKeys(event) {
	var start = new Date(event.startDateTime)
	var end = new Date(event.endDateTime)
	if (isNaN(start.getTime()) || isNaN(end.getTime())) {
		return []
	}
	var keys = []
	var day = new Date(start.getFullYear(), start.getMonth(), start.getDate())
	do {
		keys.push(dayKey(day))
		day = new Date(day.getFullYear(), day.getMonth(), day.getDate() + 1)
	} while (day < end && keys.length < 366)
	return keys
}

// { dayKey: text } of the working locations in events (other events are ignored). Several on one
// day (eg: home in the morning, office after lunch) are joined in start order with " / ". Like
// Google Calendar, a single (non-recurring) entry for a day replaces the recurring ones.
function workingLocationMap(events, words) {
	var list = []
	for (var i = 0; events && i < events.length; i++) {
		if (isWorkingLocation(events[i]) && events[i].status !== 'cancelled') {
			list.push(events[i])
		}
	}
	list.sort(function(a, b) {
		return new Date(a.startDateTime) - new Date(b.startDateTime)
	})
	var byDay = {} // dayKey -> { single: [texts], recurring: [texts] }
	list.forEach(function(event) {
		var text = workingLocationText(event, words)
		if (!text) {
			return
		}
		var group = event.recurringEventId ? 'recurring' : 'single'
		coveredDayKeys(event).forEach(function(key) {
			var entry = byDay[key] || (byDay[key] = { single: [], recurring: [] })
			if (entry[group].indexOf(text) < 0) {
				entry[group].push(text)
			}
		})
	})
	var map = {}
	for (var key in byDay) {
		var entry = byDay[key]
		map[key] = (entry.single.length ? entry.single : entry.recurring).join(' / ')
	}
	return map
}

// Auto-decline of an out of office or focus time event: { declines: 'all' | 'new' | '', message }.
// '' when it doesn't decline (or isn't such an event).
function autoDecline(event) {
	var props = isOutOfOffice(event) ? event.outOfOfficeProperties
		: isFocusTime(event) ? event.focusTimeProperties
		: null
	if (!props) {
		return { declines: '', message: '' }
	}
	var mode = String(props.autoDeclineMode || '')
	var declines = mode === 'declineAllConflictingInvitations' ? 'all'
		: mode === 'declineOnlyNewConflictingInvitations' ? 'new'
		: ''
	return { declines: declines, message: declines ? String(props.declineMessage || '').trim() : '' }
}
