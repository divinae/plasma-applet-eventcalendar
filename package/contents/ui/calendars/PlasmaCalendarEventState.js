function comparableDateValue(value) {
	if (value instanceof Date) {
		return value.getTime()
	}
	return value === undefined || value === null ? "" : String(value)
}

function sameEventTime(left, right) {
	left = left || {}
	right = right || {}
	return comparableDateValue(left.date) === comparableDateValue(right.date)
		&& comparableDateValue(left.dateTime) === comparableDateValue(right.dateTime)
}

function parsedEventId(event) {
	return event && (event.id || event.eventId || "")
}

function isSameParsedEvent(left, right) {
	return !!parsedEventId(left)
		&& parsedEventId(left) === parsedEventId(right)
		&& sameEventTime(left && left.start, right && right.start)
		&& sameEventTime(left && left.end, right && right.end)
		&& (left && left.summary || "") === (right && right.summary || "")
}

function dedupeParsedEvents(events) {
	if (!Array.isArray(events)) {
		return []
	}
	var deduped = []
	for (var i = 0; i < events.length; i++) {
		var event = events[i]
		var duplicate = false
		for (var j = 0; j < deduped.length; j++) {
			if (isSameParsedEvent(event, deduped[j])) {
				duplicate = true
				break
			}
		}
		if (!duplicate) {
			deduped.push(event)
		}
	}
	return deduped
}

// An Akonadi event (KDE PIM through the Plasma calendar plugin), as opposed to holidays and other
// plugins, and to calendars the widget reads itself (Google, iCalendar, ...).
function isPimEvent(event) {
	return !!event && String(event.calendarId || "").indexOf("plasma_Events") === 0
}

// The same event from two sources, eg: a Google calendar synced by Akonadi and signed in to
// directly. Plasma doesn't give an event's UID, so: the same title, start and end.
function sourceDuplicateKey(event) {
	if (!event || !(event.startDateTime instanceof Date) || !(event.endDateTime instanceof Date)) {
		return ""
	}
	return String(event.summary || "").trim() + "\n" + event.startDateTime.getTime() + "\n" + event.endDateTime.getTime()
}

// The Akonadi events that a directly read calendar also has: { event index: true }. The direct
// copy is the one kept, it can be edited and answered. Only the user's own direct events count
// (isOwn(event): a calendar they can edit, or an invitation), never another Plasma plugin's
// (holidays) or a calendar they only follow: a shared meeting would otherwise be left only in a
// colleague's calendar, in its color and with their answer.
function pimDuplicates(events, isOwn) {
	var directKeys = {}
	for (var i = 0; i < events.length; i++) {
		var calendarId = String(events[i] && events[i].calendarId || "")
		if (calendarId.indexOf("plasma_") !== 0 && (!isOwn || isOwn(events[i]))) {
			var key = sourceDuplicateKey(events[i])
			if (key) {
				directKeys[key] = true
			}
		}
	}
	var duplicates = {}
	for (var j = 0; j < events.length; j++) {
		if (isPimEvent(events[j]) && directKeys[sourceDuplicateKey(events[j])]) {
			duplicates[j] = true
		}
	}
	return duplicates
}

if (typeof module !== "undefined") {
	module.exports = {
		comparableDateValue: comparableDateValue,
		dedupeParsedEvents: dedupeParsedEvents,
		isPimEvent: isPimEvent,
		pimDuplicates: pimDuplicates,
		sourceDuplicateKey: sourceDuplicateKey,
		isSameParsedEvent: isSameParsedEvent,
		parsedEventId: parsedEventId,
		sameEventTime: sameEventTime,
	}
}
