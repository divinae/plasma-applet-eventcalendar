.pragma library

// Guest lists of Google events in the editor. Attendees are Google attendee objects:
// { email, displayName, responseStatus, self, organizer, resource, optional, ... }.
// Pure functions, tested in tests/guests.test.js.

function normalizeEmail(email) {
	return String(email || '').trim().toLowerCase()
}

// Simple check, like Google Calendar's field: something@domain.tld, no spaces.
function isValidEmail(email) {
	return /^[^\s@]+@[^\s@]+\.[^\s@.]+$/.test(String(email || '').trim())
}

function toList(value) {
	if (!value || typeof value === 'string') {
		return []
	}
	if (typeof value.get === 'function' && typeof value.count === 'number') { // ListModel
		var items = []
		for (var i = 0; i < value.count; i++) {
			items.push(value.get(i))
		}
		return items
	}
	return typeof value.length === 'number' ? Array.prototype.slice.call(value) : []
}

function copyOf(attendee) {
	var copy = {}
	for (var key in attendee) {
		copy[key] = attendee[key]
	}
	return copy
}

// The people of a guest list, as editable copies: rooms (resources) and entries without an email
// (eg: the cached copy of the user's own answer) are left out.
function people(attendees) {
	return toList(attendees).filter(function(a) {
		return a && !a.resource && !!normalizeEmail(a.email)
	}).map(copyOf)
}

function indexOfEmail(list, email) {
	var key = normalizeEmail(email)
	for (var i = 0; i < list.length; i++) {
		if (normalizeEmail(list[i].email) === key) {
			return i
		}
	}
	return -1
}

// Add a guest by email. Returns { list, error } where error is '', 'invalid' or 'duplicate'; the
// list is a new array (unchanged on error).
function addGuest(list, email) {
	var trimmed = String(email || '').trim()
	if (!isValidEmail(trimmed)) {
		return { list: list, error: 'invalid' }
	}
	if (indexOfEmail(list, trimmed) >= 0) {
		return { list: list, error: 'duplicate' }
	}
	return { list: list.concat([{ email: trimmed }]), error: '' }
}

function removeGuest(list, email) {
	var key = normalizeEmail(email)
	return list.filter(function(a) {
		return normalizeEmail(a.email) !== key
	})
}

// Whether two guest lists have different people (case-insensitive emails, order ignored).
function emailsDiffer(listA, listB) {
	var a = people(listA).map(function(g) { return normalizeEmail(g.email) }).sort()
	var b = people(listB).map(function(g) { return normalizeEmail(g.email) }).sort()
	return a.join('\n') !== b.join('\n')
}

// Others than the user (and rooms) are invited.
function hasOtherGuests(attendees) {
	return people(attendees).some(function(a) { return !a.self })
}

// The attendees to save: the server's list with the editor's changes (initial -> edited) applied.
// Unchanged entries keep their objects (response, self, organizer, rooms, optional, ...), new ones
// are { email }, removed ones are dropped; duplicates (case-insensitive) are dropped.
function applyChanges(serverAttendees, initial, edited) {
	var before = {}
	people(initial).forEach(function(a) { before[normalizeEmail(a.email)] = true })
	var after = {}
	people(edited).forEach(function(a) { after[normalizeEmail(a.email)] = a })

	var result = []
	var seen = {}
	toList(serverAttendees).forEach(function(a) {
		if (!a) {
			return
		}
		var key = normalizeEmail(a.email)
		if (key) {
			if (seen[key] || (before[key] && !after[key])) {
				return // Duplicate, or removed in the editor
			}
			seen[key] = true
		}
		result.push(copyOf(a))
	})
	people(edited).forEach(function(a) {
		var key = normalizeEmail(a.email)
		if (!seen[key] && !before[key]) {
			seen[key] = true
			result.push({ email: String(a.email).trim() })
		}
	})
	return result
}

// The attendees of a new event: { email } per guest, deduplicated.
function newAttendees(edited) {
	return applyChanges([], [], edited)
}

// Guests seen in the given events (for suggestions), the most frequent first: [{ email, name }].
// Rooms and the user are left out.
function knownGuests(events) {
	var byKey = {}
	toList(events).forEach(function(event) {
		toList(event && event.attendees).forEach(function(a) {
			if (!a || a.self || a.resource) {
				return
			}
			var key = normalizeEmail(a.email)
			if (!key || !isValidEmail(key)) {
				return
			}
			var entry = byKey[key]
			if (!entry) {
				entry = byKey[key] = { email: String(a.email).trim(), name: '', count: 0 }
			}
			entry.count++
			if (!entry.name && a.displayName) {
				entry.name = String(a.displayName)
			}
		})
	})
	return Object.keys(byKey).map(function(key) { return byKey[key] }).sort(function(a, b) {
		return b.count - a.count || (a.email < b.email ? -1 : a.email > b.email ? 1 : 0)
	}).map(function(entry) {
		return { email: entry.email, name: entry.name }
	})
}

// Suggestions for the typed text: known guests whose email or name contains it, not yet added.
function suggest(known, text, current, limit) {
	var query = String(text || '').trim().toLowerCase()
	if (!query) {
		return []
	}
	var list = []
	for (var i = 0; i < known.length && list.length < (limit || 5); i++) {
		var g = known[i]
		var matches = g.email.toLowerCase().indexOf(query) >= 0 || g.name.toLowerCase().indexOf(query) >= 0
		if (matches && indexOfEmail(current || [], g.email) < 0) {
			list.push(g)
		}
	}
	return list
}

// Emails of the other guests, to write to them: not the user, not rooms, valid and deduplicated
// (case-insensitive), in list order.
function otherGuestEmails(attendees) {
	var seen = {}
	var emails = []
	people(attendees).forEach(function(a) {
		var key = normalizeEmail(a.email)
		if (a.self || seen[key] || !isValidEmail(key)) {
			return
		}
		seen[key] = true
		emails.push(String(a.email).trim())
	})
	return emails
}

// "Email Guests": a mailto: link to the other guests with the event title as subject, or '' when
// there's nobody to write to. Each part is percent-encoded ('@' kept), so a title can't add
// headers (eg: "&bcc=").
function mailtoUrl(attendees, subject) {
	var emails = otherGuestEmails(attendees)
	if (!emails.length) {
		return ''
	}
	var to = emails.map(function(email) {
		return encodeURIComponent(email).replace(/%40/g, '@')
	}).join(',')
	var title = String(subject || '').trim()
	return 'mailto:' + to + (title ? '?subject=' + encodeURIComponent(title) : '')
}
// mailtoUrl for an event: its own title (_summary), not the "(No title)" shown for untitled ones.
function eventMailtoUrl(event) {
	if (!event) {
		return ''
	}
	return mailtoUrl(event.attendees, '_summary' in event ? event._summary : event.summary)
}

// Icon for an attendee's answer.
function responseIcon(status) {
	switch (status) {
		case 'accepted': return "dialog-ok-apply"
		case 'declined': return "dialog-cancel"
		case 'tentative': return "question"
		default: return "clock"
	}
}
