.pragma library
.import "lib/GoogleError.js" as GoogleError

// Import .ics files: events from `icsjson.py events` (the file's VEVENTs as they are) to
// Google Calendar `events.import` bodies. Import keeps the iCalUID, so importing the same
// invitation again updates the event instead of adding a copy. Guests and the organizer are
// left out: importing doesn't send invitations.

// A date or time of an icsjson event: { date } or { dateTime, timeZone? }. Google needs a time
// zone for the start and end of a recurring event, and for a floating time (no UTC offset).
function googleDate(value, needsZone, fallbackTimeZone) {
	if (!value) {
		return null
	}
	if (value.date) {
		return { date: value.date }
	}
	var result = { dateTime: value.dateTime }
	var floating = !/(Z|[+-]\d\d:?\d\d)$/.test(String(value.dateTime))
	if (value.timeZone) {
		result.timeZone = value.timeZone
	} else if ((needsZone || floating) && fallbackTimeZone) {
		result.timeZone = fallbackTimeZone
	}
	return result
}

// The events.import body for an icsjson event. fallbackTimeZone: the calendar's time zone,
// for times without one (floating times, or offsets without a zone name).
function googleEventBody(item, fallbackTimeZone) {
	var recurrence = Array.isArray(item.recurrence) ? item.recurrence.filter(function(line) {
		return /^(RRULE|EXRULE|RDATE|EXDATE)[:;]/.test(String(line))
	}) : []
	var recurring = recurrence.length > 0
	var body = {
		iCalUID: item.iCalUID,
		summary: item.summary || '',
		start: googleDate(item.start, recurring, fallbackTimeZone),
		end: googleDate(item.end, recurring, fallbackTimeZone),
	}
	if (item.description) {
		body.description = item.description
	}
	if (item.location) {
		body.location = item.location
	}
	if (recurring) {
		body.recurrence = recurrence
	}
	if (item.recurrenceId) {
		// A changed occurrence of a series in the same file.
		body.originalStartTime = googleDate(item.recurrenceId, true, fallbackTimeZone)
	}
	if (item.transp === 'TRANSPARENT') {
		body.transparency = 'transparent'
	}
	if (item['class'] === 'PRIVATE' || item['class'] === 'CONFIDENTIAL') {
		body.visibility = 'private'
	}
	return body
}

// Import order: a series before its changed occurrences, otherwise as in the file.
// Returns the indexes of `items`.
function importOrder(items) {
	var order = []
	for (var i = 0; i < items.length; i++) {
		if (!items[i].recurrenceId) {
			order.push(i)
		}
	}
	for (var j = 0; j < items.length; j++) {
		if (items[j].recurrenceId) {
			order.push(j)
		}
	}
	return order
}

// A JS Date for an icsjson { date } / { dateTime } (to show it). Dates and floating times are local.
function toDate(value) {
	if (!value) {
		return null
	}
	var m
	if (value.date) {
		m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value.date)
		return m ? new Date(+m[1], +m[2] - 1, +m[3]) : null
	}
	var text = String(value.dateTime || '')
	if (/(Z|[+-]\d\d:?\d\d)$/.test(text)) {
		var d = new Date(text)
		return isNaN(d.getTime()) ? null : d
	}
	m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2}))?/.exec(text)
	return m ? new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +(m[6] || 0)) : null
}

// The last day of an all-day event: its exclusive end date minus a day.
function lastDay(item) {
	var end = toDate(item.end)
	if (!end || !item.allDay) {
		return end
	}
	var last = new Date(end.getFullYear(), end.getMonth(), end.getDate() - 1)
	var start = toDate(item.start)
	return start && last < start ? start : last
}

// The number of excluded occurrences (EXDATE values).
function exceptionCount(item) {
	var count = 0
	;(item.recurrence || []).forEach(function(line) {
		var m = /^EXDATE[^:]*:(.*)$/.exec(String(line))
		if (m) {
			count += m[1].split(',').filter(function(v) { return v.length > 0 }).length
		}
	})
	return count
}

// A short message from a failed Google request: the API's error message, else the HTTP status.
function errorMessage(err, data, status) {
	var body = GoogleError.googleErrorBody(err, data)
	if (body) {
		var message = body.error.message || (body.error.errors && body.error.errors[0] && body.error.errors[0].message)
		if (message) {
			return (body.error.code ? body.error.code + ': ' : '') + message
		}
	}
	if (typeof err === 'string' && err) {
		return err
	}
	return 'HTTP ' + (status || 0)
}
