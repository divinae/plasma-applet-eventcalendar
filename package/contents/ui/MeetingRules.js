.pragma library

.import "Shared.js" as Shared
.import "Guests.js" as Guests

// Which meetings open their link at the start (auto-join) and turn on Do Not Disturb, and the
// Do Not Disturb end time as Plasma keeps it (plasmanotifyrc [DoNotDisturb] Until). Pure
// functions, tested in tests/meeting_rules.test.js.

function isTimedEvent(eventItem) {
	return !!eventItem
		&& eventItem.kind !== 'tasks#task'
		&& eventItem.status !== 'cancelled'
		&& !(eventItem.start && eventItem.start.date)
}

// Auto-join: a timed event with a meeting link (hasLink: MeetingLink.find found one) that the
// user accepted or organizes (or that has no guests).
function canAutoJoin(eventItem, hasLink) {
	if (!isTimedEvent(eventItem) || !hasLink) {
		return false
	}
	var response = Shared.myResponse(eventItem)
	return response === 'accepted' || response === ''
}

// Do Not Disturb: a timed meeting, ie: with other guests or a meeting link (an own event without
// guests isn't one). acceptedOnly: only ones the user accepted or organizes; else any not declined.
function isDoNotDisturbMeeting(eventItem, hasLink, acceptedOnly) {
	if (!isTimedEvent(eventItem)) {
		return false
	}
	if (!hasLink && !Guests.hasOtherGuests(eventItem.attendees)) {
		return false
	}
	var response = Shared.myResponse(eventItem)
	if (acceptedOnly) {
		return response === 'accepted' || response === ''
	}
	return response !== 'declined'
}

// KConfig's QDateTime format, local time: "2026,10,19,11,53,39".
function formatUntil(date) {
	return [
		date.getFullYear(),
		date.getMonth() + 1,
		date.getDate(),
		date.getHours(),
		date.getMinutes(),
		date.getSeconds(),
	].join(',')
}

// "2026,10,19,11,53,39" (or ISO "2026-10-19T11:53:39") -> Date; null when empty or invalid.
function parseUntil(text) {
	text = String(text || '').trim()
	if (!text) {
		return null
	}
	var parts = text.split(',')
	var date
	if (parts.length >= 3) {
		var n = parts.map(function(p) { return Number(p) })
		for (var i = 0; i < n.length; i++) {
			if (!isFinite(n[i])) {
				return null
			}
		}
		date = new Date(n[0], n[1] - 1, n[2], n[3] || 0, n[4] || 0, n[5] || 0)
	} else {
		date = new Date(text)
	}
	return isFinite(date.getTime()) ? date : null
}

// The Until to write for a meeting ending at end, or '' to leave it: a meeting already over, or
// Do Not Disturb already on until the end or later (a longer one the user set isn't shortened).
function untilToWrite(currentText, end, now) {
	end = new Date(end)
	if (!isFinite(end.getTime()) || end <= now) {
		return ''
	}
	var current = parseUntil(currentText)
	if (current && current >= end) {
		return ''
	}
	return formatUntil(end)
}

// Ending a meeting early clears Do Not Disturb only if it's still what the widget wrote.
function isOwnUntil(currentText, writtenText) {
	if (!writtenText) {
		return false
	}
	var current = parseUntil(currentText)
	var written = parseUntil(writtenText)
	return !!current && !!written && current.getTime() === written.getTime()
}
