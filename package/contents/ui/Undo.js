.pragma library

// Undo after deleting or moving an event (Google Calendar).

// Fields the widget adds when it parses an event, and the ones the server sets on its own.
var localFields = ['calendarManagerId', 'calendarId', 'startDateTime', 'endDateTime', 'canEdit',
	'_summary', 'reminderMinutes', 'backgroundColor', 'accepted']
var serverFields = ['id', 'etag', 'iCalUID', 'htmlLink', 'created', 'updated', 'creator',
	'organizer', 'sequence', 'hangoutLink', 'kind', 'status']

function clone(obj) {
	return obj === undefined ? undefined : JSON.parse(JSON.stringify(obj))
}

// A copy of a (non-recurring) event to create again if it can't be restored: the body of
// a new event (POST), without the ids and the server-set fields.
function restoreCopy(event) {
	var data = clone(event)
	if (!data) {
		return null
	}
	localFields.concat(serverFields).forEach(function(key) {
		delete data[key]
	})
	// The parser fills in an empty description; an untitled event has no summary.
	if (data.description === '') {
		delete data.description
	}
	if (Object.prototype.hasOwnProperty.call(event, '_summary') && !event._summary) {
		delete data.summary
	}
	return data
}

// The start / end to put back after a move.
function savedTimes(event) {
	return { start: clone(event.start), end: clone(event.end) }
}
