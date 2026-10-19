.pragma library

function openGoogleCalendarNewEventUrl(date) {
	function dateString(year, month, day) {
		var s = '' + year
		s += (month < 10 ? '0' : '') + month
		s += (day < 10 ? '0' : '') + day
		return s
	}

	var nextDay = new Date(date.getFullYear(), date.getMonth(), date.getDate() + 1)

	var url = 'https://calendar.google.com/calendar/render?action=TEMPLATE'
	var startDate = dateString(date.getFullYear(), date.getMonth() + 1, date.getDate())
	var endDate = dateString(nextDay.getFullYear(), nextDay.getMonth() + 1, nextDay.getDate())
	url += '&dates=' + startDate + '/' + endDate
	openExternalUrl(url)
}

// Midnight at the start of the day of d.
function startOfDay(d) {
	return new Date(d.getFullYear(), d.getMonth(), d.getDate())
}
function isSameDate(a, b) {
	return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
}
function isDateEarlier(a, b) {
	return a < startOfDay(b)
}
function isDateAfter(a, b) {
	var c = new Date(b.getFullYear(), b.getMonth(), b.getDate() + 1) // midnight of next day after b
	return a >= c
}
function dateTimeString(d) {
	return d.toISOString()
}
function dateString(d) {
	return d.toISOString().substr(0, 10)
}
function localeDateString(d) {
	return Qt.formatDateTime(d, 'yyyy-MM-dd')
}
function isValidDate(d) {
	if (d === null) {
		return false
	} else if (isNaN(d)) {
		return false
	} else {
		return true
	}
}

// Event description / task notes as safe StyledText: Google stores descriptions as HTML, which
// could load remote images (tracking) or carry odd markup. Reduce it to text (keeping link
// targets), escape it, then link URLs and keep line breaks.
function renderText(text) {
	if (typeof text === 'undefined' || text === null) {
		return ''
	}
	var raw = String(text)
	if (/<[a-z][^>]*>/i.test(raw)) {
		raw = raw
			// <a href="X">label</a>: keep the target, it's often the whole point (eg: a meeting link).
			.replace(/<a\s[^>]*href\s*=\s*"([^"]*)"[^>]*>([\s\S]*?)<\/a>/gi, function(m, href, label) {
				var plainLabel = label.replace(/<[^>]*>/g, '')
				return plainLabel && plainLabel !== href ? plainLabel + ' (' + href + ')' : href
			})
			.replace(/<br\s*\/?>/gi, '\n')
			.replace(/<\/(p|div|li|h[1-6])>/gi, '\n')
			.replace(/<[^>]*>/g, '')
			.replace(/&nbsp;/g, ' ')
			.replace(/&lt;/g, '<')
			.replace(/&gt;/g, '>')
			.replace(/&quot;/g, '"')
			.replace(/&#39;/g, "'")
			.replace(/&amp;/g, '&')
	}
	var rUrl = /(https?:\/\/[^\s<>"]+)/gi
	var out = ''
	var lastIndex = 0
	var match
	while ((match = rUrl.exec(raw)) !== null) {
		var href = match[0].replace(/[).,;:!?]+$/, '') // Not the sentence's punctuation
		out += escapeHtml(raw.slice(lastIndex, match.index))
		// href: StyledText doesn't decode entities there (&amp; would reach the browser); the URL
		// pattern has no quotes or angle brackets, so it's safe as is.
		out += isSafeExternalUrl(href) ? '<a href="' + href + '">' + escapeHtml(href) + '</a>' : escapeHtml(href)
		lastIndex = match.index + href.length
		rUrl.lastIndex = lastIndex
	}
	out += escapeHtml(raw.slice(lastIndex))
	out = out.replace(/\r\n?/g, '\n').replace(/\n/g, '<br>')
	// Remove leading new lines, as Google sometimes adds them.
	out = out.replace(/^(<br>)+/, '')
	return out
}

// Merge values of objB into objA
function merge(objA, objB) {
	var keys = Object.keys(objB)
	for (var i = 0; i < keys.length; i++) {
		var key = keys[i]
		objA[key] = objB[key]
	}
}

// Remove keys from objA that are missing in objB
function removeMissingKeys(objA, objB) {
	var keys = Object.keys(objA)
	for (var i = 0; i < keys.length; i++) {
		var key = keys[i]
		if (typeof objB[key] === 'undefined') {
			delete objA[key]
		}
	}
}

// Black or white text, whichever reads better on the given background color.
function contrastTextColor(bg) {
	var c = Qt.color(bg)
	var luminance = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
	return luminance > 0.6 ? "#202124" : "#ffffff"
}

function plainText(html) {
	return String(html || '')
		.replace(/<br\s*\/?>/gi, '\n')
		.replace(/<[^>]*>/g, '')
		.replace(/&nbsp;/g, ' ')
		.replace(/&amp;/g, '&')
		.trim()
}

// Non-working day for the current locale. Qt.locale().weekDays uses 1..7 (Monday..Sunday),
// Date.getDay() uses 0 for Sunday.
function isWeekend(date) {
	var workingDays = Qt.locale().weekDays
	var day = date.getDay()
	return workingDays.indexOf(day) < 0 && !(day === 0 && workingDays.indexOf(7) >= 0)
}

// Work week columns: the offsets (0..6) from a week's first day of its working days, in week
// order. firstWeekday: Date.getDay() of the week's first day (0 = Sunday). workingDays:
// Qt.locale().weekDays (1..7, Monday..Sunday); none given: Monday to Friday.
function workDayOffsets(firstWeekday, workingDays) {
	var days = workingDays && workingDays.length ? workingDays : [1, 2, 3, 4, 5]
	var working = {}
	for (var i = 0; i < days.length; i++) {
		working[Number(days[i]) % 7] = true // 7 (Sunday) -> 0, like getDay()
	}
	var offsets = []
	for (var offset = 0; offset < 7; offset++) {
		if (working[(firstWeekday + offset) % 7]) {
			offsets.push(offset)
		}
	}
	return offsets.length ? offsets : [0, 1, 2, 3, 4, 5, 6]
}

// Consecutive runs of true values: [true, false, true, true] -> [{ first: 0, count: 1 }, { first: 2, count: 2 }]
// Used to draw adjacent weekend days as one strip.
function runsOf(flags) {
	var runs = []
	for (var i = 0; i < flags.length; i++) {
		if (!flags[i]) {
			continue
		}
		if (runs.length && runs[runs.length - 1].first + runs[runs.length - 1].count === i) {
			runs[runs.length - 1].count++
		} else {
			runs.push({ first: i, count: 1 })
		}
	}
	return runs
}

// Array or array-like list. Event data passed through a `var` signal argument (Qt 6.12+) has
// array-like sequences for nested arrays, for which Array.isArray() is false.
function isList(value) {
	return !!value && typeof value !== 'string' && typeof value.length === 'number'
}
function toArray(value) {
	return isList(value) ? Array.prototype.slice.call(value) : []
}

// The signed-in user's answer to an invitation: 'needsAction', 'tentative', 'declined', 'accepted',
// or '' when not invited (no attendees, or the user organizes it). attendees is an array, or a
// ListModel once the event has been put in one (agenda).
function myResponse(eventItem) {
	var attendees = eventItem ? eventItem.attendees : null
	if (!attendees) {
		return ''
	}
	var isModel = typeof attendees.get === 'function' && typeof attendees.count === 'number'
	var count = isModel ? attendees.count : (isList(attendees) ? attendees.length : 0)
	for (var i = 0; i < count; i++) {
		var attendee = isModel ? attendees.get(i) : attendees[i]
		if (attendee && attendee.self) {
			return attendee.organizer ? '' : String(attendee.responseStatus || '')
		}
	}
	return ''
}

// Left out of the views (and the panel's next meeting) when declined events are set to Hide.
function isHiddenDeclined(eventItem, showDeclined) {
	return !showDeclined && myResponse(eventItem) === 'declined'
}

// Hidden with the popup header's calendar toggles (hiddenCalendarIds). A view filter: the events
// are still fetched and their reminders still come.
function isHiddenCalendar(calendarId, hiddenCalendarIds) {
	if (!hiddenCalendarIds || !calendarId) {
		return false
	}
	for (var i = 0; i < hiddenCalendarIds.length; i++) {
		if (hiddenCalendarIds[i] === String(calendarId)) {
			return true
		}
	}
	return false
}

// Titles of the events this one overlaps (EventModel sets conflictsWith, see Conflicts.js). It holds
// { summary } objects, not strings: a ListModel (agenda) drops plain strings from nested lists.
function conflictTitles(eventItem) {
	var list = eventItem ? eventItem.conflictsWith : null
	if (!list) {
		return []
	}
	var isModel = typeof list.get === 'function' && typeof list.count === 'number'
	var count = isModel ? list.count : (isList(list) ? list.length : 0)
	var titles = []
	for (var i = 0; i < count; i++) {
		var entry = isModel ? list.get(i) : list[i]
		if (entry) {
			titles.push(String(entry.summary || ''))
		}
	}
	return titles
}

// What an event has set, as small icons after its time: 'conflict' (overlaps another meeting),
// 'location', 'meeting' (a join link, found by the caller with MeetingLink.find), 'guests' (anyone
// besides the user), 'repeat' and 'description'. Keys in hide are left out, eg: when the view
// already shows the location. attendees may be an array or a ListModel (agenda).
var EVENT_INDICATOR_ICONS = {
	conflict: 'dialog-warning',
	location: 'mark-location',
	meeting: 'call-start',
	guests: 'group',
	repeat: 'media-playlist-repeat',
	description: 'view-list-text',
}
// Icons that fill their whole box (Breeze's pin) are drawn smaller to match the others.
var EVENT_INDICATOR_SCALE = {
	location: 0.75,
}
// Pixel size of an indicator icon: even, so a scaled 16 px icon stays crisp (16 -> 12).
function eventIndicatorIconSize(key, size) {
	var scale = EVENT_INDICATOR_SCALE[key] || 1
	return scale === 1 ? size : 2 * Math.round(size * scale / 2)
}
function eventIndicatorKeys(eventItem, hasMeeting, hide) {
	if (!eventItem) {
		return []
	}
	hide = hide || {}
	var attendees = eventItem.attendees
	var guestCount = 0
	if (attendees) {
		var isModel = typeof attendees.get === 'function' && typeof attendees.count === 'number'
		var count = isModel ? attendees.count : (isList(attendees) ? attendees.length : 0)
		for (var i = 0; i < count; i++) {
			var attendee = isModel ? attendees.get(i) : attendees[i]
			if (attendee && !attendee.self && !attendee.resource) {
				guestCount++
			}
		}
	}
	var keys = []
	function add(key, isSet) {
		if (isSet && !hide[key]) {
			keys.push(key)
		}
	}
	add('conflict', conflictTitles(eventItem).length > 0)
	add('location', !!eventItem.location)
	add('meeting', !!hasMeeting)
	add('guests', guestCount > 0)
	add('repeat', !!eventItem.recurringEventId || !!(eventItem.recurrence && (eventItem.recurrence.length || eventItem.recurrence.count)))
	add('description', !!String(eventItem.description || '').trim())
	return keys
}

// Not (yet) a yes: shown outlined like Google Calendar, with stripes for maybe.
function isUnconfirmedResponse(response) {
	return response === 'needsAction' || response === 'tentative' || response === 'declined'
}

// Number identifying a calendar day, eg: for weather lookups. Month is 0-based like Date.
function dayKey(d) {
	return d.getFullYear() * 10000 + d.getMonth() * 100 + d.getDate()
}

// Before today (midnight).
function isPastDay(d, now) {
	return d < startOfDay(now)
}

function formatTemp(t) {
	return isFinite(t) ? Math.round(t) + '°' : ''
}

// "09:45 – 10:00", format: a Qt time format, eg: appletConfig.timeFormat
function formatTimeRange(start, end, format) {
	return Qt.formatTime(start, format) + ' – ' + Qt.formatTime(end, format)
}

// Monochrome variant of a (weather) icon: readable on any background. Use with `fallback: name`.
function symbolicIcon(name) {
	return name ? name + '-symbolic' : ''
}

// Unset or empty string.
function isEmpty(s) {
	return typeof s === 'undefined' || s === null || s === ''
}
// Edit forms: a field changed (unset and empty count as equal). Loose != on purpose: '5' vs 5.
function hasChanged(a, b) {
	return a != b && !(isEmpty(a) && isEmpty(b))
}

//--- Location links
function isUrl(text) {
	return /^https?:\/\/\S+$/i.test(String(text || '').trim())
}
function escapeHtml(text) {
	if (typeof text === 'undefined' || text === null) {
		return ''
	}
	return String(text)
		.replace(/&/g, '&amp;')
		.replace(/</g, '&lt;')
		.replace(/>/g, '&gt;')
		.replace(/"/g, '&quot;')
		.replace(/'/g, '&#39;')
}
// Only web links are opened from event text (no file:, javascript:, custom schemes).
function isSafeExternalUrl(url) {
	return typeof url === 'string' && /^(https?):\/\/[^\s]+$/i.test(url.trim())
}
function openExternalUrl(url) {
	if (!isSafeExternalUrl(url)) {
		console.warn('[eventcalendar] Refusing to open unsafe URL', url)
		return false
	}
	Qt.openUrlExternally(url.trim())
	return true
}
// A URL location opens as is, anything else as a Google Maps search.
function locationUrl(location) {
	var text = String(location || '').trim()
	if (isUrl(text)) {
		return text
	}
	// Search path form: no '&' needed, and Maps pins the place it finds.
	return 'https://www.google.com/maps/search/' + encodeURIComponent(text)
}
// Location as a link (for a Text with textFormat: Text.StyledText).
// StyledText doesn't decode entities in href (&amp; would reach the browser): only quotes are escaped.
function locationLink(location) {
	var href = locationUrl(location).replace(/"/g, '%22')
	return '<a href="' + href + '">' + escapeHtml(location) + '</a>'
}

//--- Event span ("All day", "14 – 16 Oct", "14 Oct 22:00 – 16 Oct 02:00")
// Days an event covers. All-day events end at midnight the next day (exclusive); a timed event
// counts every day it touches.
function eventDayCount(e) {
	var start = startOfDay(new Date(e.startDateTime))
	var end = new Date(e.endDateTime)
	var isAllDay = !!(e.start && e.start.date)
	var last = startOfDay(new Date(Math.max(start.getTime(), end.getTime() - (isAllDay ? 1 : 0))))
	if (!isAllDay && end.getTime() === last.getTime() && end > start) {
		last.setDate(last.getDate() - 1) // Timed event ending exactly at midnight
	}
	return Math.round((last - start) / 86400000) + 1
}
// Date format for a span: the year only when it isn't the current one (or the span crosses years).
function spanDateFormat(a, b, now) {
	var sameYear = a.getFullYear() === b.getFullYear() && a.getFullYear() === now.getFullYear()
	return sameYear ? 'd MMM' : 'd MMM yyyy'
}
// { allDay, multiDay, days, startText, endText } for an event; the caller words it with i18n.
// timeFormat: Qt time format for timed events (eg: appletConfig.timeFormat).
function eventSpan(e, timeFormat, now) {
	var isAllDay = !!(e.start && e.start.date)
	var days = eventDayCount(e)
	var start = new Date(e.startDateTime)
	var end = new Date(e.endDateTime)
	var result = { allDay: isAllDay, multiDay: days > 1, days: days, startText: '', endText: '' }
	if (isAllDay) {
		var last = new Date(end)
		last.setDate(last.getDate() - 1)
		var dateFormat = spanDateFormat(start, last, now || new Date())
		result.startText = Qt.formatDate(start, dateFormat)
		result.endText = Qt.formatDate(last, dateFormat)
	} else if (days > 1) {
		var timedFormat = spanDateFormat(start, end, now || new Date()) + ' ' + timeFormat
		result.startText = Qt.formatDateTime(start, timedFormat)
		result.endText = Qt.formatDateTime(end, timedFormat)
	} else {
		result.startText = Qt.formatTime(start, timeFormat)
		result.endText = Qt.formatTime(end, timeFormat)
	}
	return result
}
