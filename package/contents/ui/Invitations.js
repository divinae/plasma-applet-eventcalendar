.pragma library

.import "Shared.js" as Shared

// Invitations to answer: meetings today (not ended, not all-day, not cancelled) where the user's
// own answer is still "needsAction". Each is notified once; the keys of the notified ones are kept
// (in the config, so a restart doesn't repeat them) for the day.

function dayKey(date) {
	return date.getFullYear() + '-' + (date.getMonth() + 1) + '-' + date.getDate()
}

function eventKey(eventItem) {
	return String(eventItem.calendarId || '') + '|' + String(eventItem.id || '') + '|' + new Date(eventItem.startDateTime).getTime()
}

function isAllDay(eventItem) {
	return !!(eventItem.start && eventItem.start.date)
}

// [eventItem] to notify, oldest first. events: plain event items; notified: ["day|key", ...].
function pendingToday(events, now, notified) {
	var today = dayKey(now)
	var seen = {}
	;(notified || []).forEach(function(entry) {
		seen[String(entry)] = true
	})
	var list = []
	;(events || []).forEach(function(eventItem) {
		if (!eventItem || eventItem.kind === 'tasks#task' || eventItem.status === 'cancelled' || isAllDay(eventItem)) {
			return
		}
		var start = new Date(eventItem.startDateTime)
		var end = new Date(eventItem.endDateTime)
		if (!isFinite(start.getTime()) || dayKey(start) !== today || end <= now) {
			return
		}
		if (Shared.myResponse(eventItem) !== 'needsAction') {
			return
		}
		if (seen[today + '|' + eventKey(eventItem)]) {
			return
		}
		list.push(eventItem)
	})
	list.sort(function(a, b) { return a.startDateTime - b.startDateTime })
	return list
}

// The notified list with these events added, and other days' entries dropped.
function markNotified(notified, eventItems, now) {
	var today = dayKey(now)
	var kept = (notified || []).map(String).filter(function(entry) {
		return entry.indexOf(today + '|') === 0
	})
	eventItems.forEach(function(eventItem) {
		var entry = today + '|' + eventKey(eventItem)
		if (kept.indexOf(entry) < 0) {
			kept.push(entry)
		}
	})
	return kept
}
