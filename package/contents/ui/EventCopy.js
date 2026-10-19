.pragma library

// A copy of an event made by Ctrl + drag: the body of a new event (POST) on the same calendar,
// at the given start / end (Google objects).
// Copied: title, location, description, color, reminders, show as (busy / free), visibility,
// and the event type with its settings (out of office, focus time, working location).
// Left out on purpose:
// - guests: the copy would send them invitations, a quick drag shouldn't. Duplicate (the editor)
//   copies them, with a chance to look first.
// - video call: the original's link belongs to the original; a new one can be added in the editor.
// - attachments, repeat rule: a dragged copy (also of an occurrence) is one new event on that day.
var copiedTypes = ['outOfOffice', 'focusTime', 'workingLocation']

function clone(obj) {
	return JSON.parse(JSON.stringify(obj))
}

function copyBody(event, start, end) {
	var body = {}
	// An untitled event: the parser fills in a summary, the original one is _summary.
	var summary = Object.prototype.hasOwnProperty.call(event, '_summary') ? event._summary : event.summary
	if (summary) {
		body.summary = summary
	}
	if (event.location) {
		body.location = event.location
	}
	if (event.description) {
		body.description = event.description
	}
	if (event.colorId) {
		body.colorId = String(event.colorId)
	}
	if (event.reminders) {
		body.reminders = clone(event.reminders)
	}
	if (event.transparency === 'transparent') {
		body.transparency = 'transparent'
	}
	if (event.visibility && event.visibility !== 'default') {
		body.visibility = event.visibility
	}
	if (copiedTypes.indexOf(event.eventType) >= 0) {
		body.eventType = event.eventType
		var key = event.eventType + 'Properties'
		if (event[key]) {
			body[key] = clone(event[key])
		}
	}
	body.start = clone(start)
	body.end = clone(end)
	return body
}
