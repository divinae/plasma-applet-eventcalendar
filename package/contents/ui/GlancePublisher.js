.pragma library

// What Event Calendar shares with Glance (the panel widget) over D-Bus: today's and tomorrow's
// events from every calendar, as plain values. No descriptions and no guests' addresses: only the
// count of guests and your own answer. Times are ms since the epoch.

var MAX_BYTES = 60000 // One argv string after base64 (run_argv.py): well under Linux's 128 KiB

function dayStart(ms) {
	var d = new Date(ms)
	d.setHours(0, 0, 0, 0)
	return d.getTime()
}

// The window shared: the start of today to the end of tomorrow
function windowOf(nowMs) {
	var start = dayStart(nowMs)
	var end = new Date(start)
	end.setDate(end.getDate() + 2)
	return { start: start, end: end.getTime() }
}

function timeOf(date) {
	if (date instanceof Date) {
		return date.getTime()
	}
	var t = Date.parse(date)
	return isNaN(t) ? NaN : t
}

// One event, or null for a task, a cancelled event or one without a usable start. meeting: MeetingLink.find's { url, label } or
// null; response, guests: Shared.attendeeSummary's; calendarName: its calendar's title.
function plain(eventItem, meeting, response, guests, calendarName, calendarId) {
	if (!eventItem || eventItem.kind === 'tasks#task' || eventItem.status === 'cancelled') {
		return null
	}
	var allDay = !!(eventItem.start && eventItem.start.date)
	var start = timeOf(eventItem.startDateTime)
	var end = timeOf(eventItem.endDateTime)
	if (isNaN(start)) {
		return null
	}
	if (isNaN(end) || end < start) {
		end = start
	}
	var url = meeting && meeting.url ? String(meeting.url) : ''
	return {
		id: String(eventItem.id || ''),
		summary: String(eventItem.summary || ''),
		start: start,
		end: end,
		allDay: allDay,
		location: String(eventItem.location || ''),
		color: String(eventItem.backgroundColor || ''),
		calendar: String(calendarName || ''),
		calendarId: String(calendarId || eventItem.calendarId || ''), // For Glance to open it (showEvent)
		meetingUrl: /^https?:\/\//i.test(url) ? url : '',
		meetingLabel: meeting && meeting.label ? String(meeting.label) : '',
		response: String(response || ''),
		guests: guests | 0,
		busy: eventItem.transparency !== 'transparent',
		htmlLink: /^https?:\/\//i.test(String(eventItem.htmlLink || '')) ? String(eventItem.htmlLink) : '',
	}
}

// The events (plain's) in the window, sorted by start
function select(items, nowMs) {
	var w = windowOf(nowMs)
	return items.filter(function(item) {
		return item && item.end > w.start && item.start < w.end
	}).sort(function(a, b) { return a.start - b.start })
}

// A string as GVariant text ('...', its backslashes and quotes escaped), so gdbus takes it as
// that string whatever it holds
function gvariantString(text) {
	return "'" + String(text).replace(/\\/g, "\\\\").replace(/'/g, "\\'") + "'"
}

// The text's size in UTF-8 bytes (what goes on the command line): titles in other alphabets take
// 2-3 bytes a character
function utf8Bytes(text) {
	return unescape(encodeURIComponent(text)).length
}

// The weather for Glance: now (logic.currentWeatherData) and today's high / low (weatherByDay's
// day), as plain values; null without either
function weather(current, today, units) {
	var c = current && isFinite(current.temp) ? current : null
	var t = today && today.temp ? today : null
	if (!c && !t) {
		return null
	}
	return {
		temp: c ? Math.round(c.temp) : null,
		text: c ? String(c.text || '') : '',
		iconName: String((c && c.iconName) || (t && t.iconName) || ''),
		high: t && isFinite(t.temp.max) ? Math.round(t.temp.max) : null,
		low: t && isFinite(t.temp.min) ? Math.round(t.temp.min) : null,
		place: c ? String(c.place || '') : '',
		units: units === 'imperial' ? 'imperial' : 'metric',
	}
}

// The payload Glance accepts: {"version": 1, "events": [...], "weather": {...}}, kept under MAX_BYTES by leaving
// out the latest events first (tomorrow before today)
function payload(events, nowMs, weatherNow) {
	var list = events.slice()
	var data = function() {
		var out = { version: 1, savedAt: nowMs, events: list }
		if (weatherNow) {
			out.weather = weatherNow
		}
		return JSON.stringify(out)
	}
	var text = data()
	while (utf8Bytes(text) > MAX_BYTES && list.length) {
		list.pop()
		text = data()
	}
	return text
}
