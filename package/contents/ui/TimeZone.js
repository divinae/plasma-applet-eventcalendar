.pragma library
.import "code/TimeZoneData.js" as TimeZoneData

// Time zone math without Intl (QML's JavaScript has none): each IANA zone has a POSIX TZ rule
// (code/TimeZoneData.js, eg: "EST5EDT,M3.2.0,M11.1.0" for America/New_York), the zone's current
// rules, and for zones whose rules changed lately the transitions until then. Offsets are minutes east of UTC. Zones that aren't known return null: callers then use
// the local time (JS Date).

var HOUR = 3600000
var MINUTE = 60000
var parsedCache = {}

function knows(zone) {
	return !!zone && Object.prototype.hasOwnProperty.call(TimeZoneData.rules, zone)
}
function pickerZones() {
	return TimeZoneData.pickerZones
}

// "[+-]hh[:mm[:ss]]" -> seconds
function parseTime(text) {
	var m = /^([+-]?)(\d{1,3})(?::(\d{1,2}))?(?::(\d{1,2}))?$/.exec(text)
	if (!m) {
		return null
	}
	var seconds = parseInt(m[2], 10) * 3600 + parseInt(m[3] || '0', 10) * 60 + parseInt(m[4] || '0', 10)
	return m[1] === '-' ? -seconds : seconds
}

// Parses a POSIX TZ rule: { std: { abbr, offset }, dst: { abbr, offset } | null, start, end }
// where start / end are { type: 'M'|'J'|'n', month, week, day, n, time (seconds) }.
function parsePosix(rule) {
	var pos = 0
	function abbr() {
		var m
		if (rule.charAt(pos) === '<') {
			m = /^<([^>]*)>/.exec(rule.slice(pos))
		} else {
			m = /^([A-Za-z]{3,})/.exec(rule.slice(pos))
		}
		if (!m) {
			return null
		}
		pos += m[0].length
		return m[1]
	}
	function offset() {
		var m = /^[+-]?\d{1,2}(?::\d{1,2}){0,2}/.exec(rule.slice(pos))
		if (!m) {
			return null
		}
		pos += m[0].length
		return (0 - parseTime(m[0])) / 60 // POSIX offsets are west of UTC (and no -0)
	}
	function date() {
		var m = /^(?:M(\d{1,2})\.(\d)\.(\d)|J(\d{1,3})|(\d{1,3}))(?:\/([+-]?\d{1,3}(?::\d{1,2}){0,2}))?/.exec(rule.slice(pos))
		if (!m) {
			return null
		}
		pos += m[0].length
		var out = { time: m[6] ? parseTime(m[6]) : 7200 }
		if (m[1]) {
			out.type = 'M'
			out.month = parseInt(m[1], 10)
			out.week = parseInt(m[2], 10)
			out.day = parseInt(m[3], 10)
		} else if (m[4]) {
			out.type = 'J'
			out.n = parseInt(m[4], 10)
		} else {
			out.type = 'n'
			out.n = parseInt(m[5], 10)
		}
		return out
	}

	var stdAbbr = abbr()
	var stdOffset = offset()
	if (stdAbbr === null || stdOffset === null) {
		return null
	}
	var result = { std: { abbr: stdAbbr, offset: stdOffset }, dst: null }
	if (pos >= rule.length) {
		return result
	}
	var dstAbbr = abbr()
	if (dstAbbr === null) {
		return null
	}
	var dstOffset = stdOffset + 60
	if (rule.charAt(pos) !== ',') {
		dstOffset = offset()
		if (dstOffset === null) {
			return null
		}
	}
	result.dst = { abbr: dstAbbr, offset: dstOffset }
	if (rule.charAt(pos) !== ',') {
		// No dates: the US rules (POSIX default)
		result.start = { type: 'M', month: 3, week: 2, day: 0, time: 7200 }
		result.end = { type: 'M', month: 11, week: 1, day: 0, time: 7200 }
		return result
	}
	pos++
	result.start = date()
	if (!result.start || rule.charAt(pos) !== ',') {
		return null
	}
	pos++
	result.end = date()
	if (!result.end) {
		return null
	}
	return result
}

function parsed(zone) {
	if (!knows(zone)) {
		return null
	}
	if (!parsedCache[zone]) {
		parsedCache[zone] = parsePosix(TimeZoneData.rules[zone])
	}
	return parsedCache[zone]
}

function isLeap(year) {
	return (year % 4 === 0 && year % 100 !== 0) || year % 400 === 0
}

// UTC ms of a transition in `year`, its wall time read with `offset` (the offset before it).
function transitionUtc(date, year, offset) {
	var dayMs
	if (date.type === 'M') {
		var first = new Date(Date.UTC(year, date.month - 1, 1))
		var day = 1 + (date.day - first.getUTCDay() + 7) % 7 + (date.week - 1) * 7
		var daysInMonth = new Date(Date.UTC(year, date.month, 0)).getUTCDate()
		while (day > daysInMonth) { // Week 5: the last such day
			day -= 7
		}
		dayMs = Date.UTC(year, date.month - 1, day)
	} else if (date.type === 'J') { // 1..365, February 29th never counted
		var n = date.n
		if (isLeap(year) && n >= 60) {
			n++
		}
		dayMs = Date.UTC(year, 0, n)
	} else { // 0..365, leap days counted
		dayMs = Date.UTC(year, 0, date.n + 1)
	}
	return dayMs + date.time * 1000 - offset * MINUTE
}

function isDst(rules, utcMs) {
	var year = new Date(utcMs + rules.std.offset * MINUTE).getUTCFullYear()
	var start = transitionUtc(rules.start, year, rules.std.offset)
	var end = transitionUtc(rules.end, year, rules.dst.offset)
	if (start < end) {
		return utcMs >= start && utcMs < end
	}
	// Southern hemisphere (or Europe/Dublin's negative DST): DST over the new year.
	return utcMs < end || utcMs >= start
}

// The zone's offset and abbreviation at an instant: { offset, abbr } or null.
function infoAt(zone, utcMs) {
	var rules = parsed(zone)
	if (!rules) {
		return null
	}
	// Rules changed lately: the transitions until the last change.
	var table = TimeZoneData.recent[zone]
	if (table && utcMs >= table[0][0] * MINUTE && utcMs < table[table.length - 1][0] * MINUTE) {
		for (var i = table.length - 1; i >= 0; i--) {
			if (utcMs >= table[i][0] * MINUTE) {
				return { offset: table[i][1], abbr: table[i][2] }
			}
		}
	}
	var period = rules.dst && isDst(rules, utcMs) ? rules.dst : rules.std
	return { offset: period.offset, abbr: period.abbr }
}
function offsetAt(zone, utcMs) {
	var info = infoAt(zone, utcMs)
	return info ? info.offset : null
}

// "+0530" / "-03" style abbreviations as GMT+5:30 / GMT-3.
function displayAbbr(abbr) {
	var m = /^([+-])(\d\d)(\d\d)?$/.exec(abbr || '')
	if (!m) {
		return abbr || ''
	}
	var text = 'GMT' + m[1] + parseInt(m[2], 10)
	if (m[3] && m[3] !== '00') {
		text += ':' + m[3]
	}
	return text
}
function abbreviation(zone, utcMs) {
	var info = infoAt(zone, utcMs)
	return info ? displayAbbr(info.abbr) : ''
}

// The wall clock in `zone` at an instant: { year, month (0-11), day, hours, minutes, seconds, offset }.
function wallClock(zone, utcMs) {
	var offset = offsetAt(zone, utcMs)
	if (offset === null) {
		return null
	}
	var d = new Date(utcMs + offset * MINUTE)
	return {
		year: d.getUTCFullYear(),
		month: d.getUTCMonth(),
		day: d.getUTCDate(),
		hours: d.getUTCHours(),
		minutes: d.getUTCMinutes(),
		seconds: d.getUTCSeconds(),
		offset: offset,
	}
}

// UTC ms of a wall clock time in `zone`, or null. In a gap (clocks moved forward) the time is
// read with the offset before the change (02:30 -> 03:30); a repeated hour gives the first one.
function toUtc(zone, year, month, day, hours, minutes, seconds) {
	var rules = parsed(zone)
	if (!rules) {
		return null
	}
	var wall = Date.UTC(year, month, day, hours, minutes || 0, seconds || 0)
	var offsets = rules.dst ? [rules.std.offset, rules.dst.offset] : [rules.std.offset]
	var table = TimeZoneData.recent[zone] || []
	for (var k = 0; k < table.length; k++) {
		if (offsets.indexOf(table[k][1]) < 0) {
			offsets.push(table[k][1])
		}
	}
	var candidates = []
	for (var i = 0; i < offsets.length; i++) {
		var t = wall - offsets[i] * MINUTE
		if (offsetAt(zone, t) === offsets[i]) {
			candidates.push(t)
		}
	}
	if (candidates.length) {
		return Math.min.apply(null, candidates)
	}
	// Gap: read with the offset before the change.
	return wall - offsetAt(zone, wall - rules.std.offset * MINUTE - 12 * HOUR) * MINUTE
}

// Dates whose local fields show a zone's wall clock: the editor's selectors work on local Dates.
// toWallDate(zone, instant) -> a Date with the zone's clock time as local time.
function toWallDate(zone, instant) {
	var w = wallClock(zone, new Date(instant).getTime())
	if (!w) {
		return new Date(instant)
	}
	return new Date(w.year, w.month, w.day, w.hours, w.minutes, w.seconds)
}
// fromWallDate(zone, wallDate) -> the instant (Date) of that clock time in the zone.
function fromWallDate(zone, wallDate) {
	var d = new Date(wallDate)
	var t = toUtc(zone, d.getFullYear(), d.getMonth(), d.getDate(), d.getHours(), d.getMinutes(), d.getSeconds())
	return t === null ? d : new Date(t)
}

// Whether a zone shows the same clock as the local time zone (JS Date) at an instant and half a
// year either side (same DST rules, as far as it matters).
function matchesLocal(zone, utcMs) {
	if (!knows(zone)) {
		return false
	}
	var halfYear = 182 * 24 * HOUR
	var times = [utcMs, utcMs - halfYear, utcMs + halfYear]
	for (var i = 0; i < times.length; i++) {
		if (offsetAt(zone, times[i]) !== -new Date(times[i]).getTimezoneOffset()) {
			return false
		}
	}
	return true
}

// A zone with the local time's rules, when its name isn't known: the first picker zone that
// matches over a year (eg: Europe/Amsterdam for any Central European zone), or ''.
function guessLocal(utcMs) {
	var zones = TimeZoneData.pickerZones
	var now = utcMs || Date.now()
	for (var i = 0; i < zones.length; i++) {
		if (matchesLocal(zones[i], now) && matchesLocal(zones[i], now + 91 * 24 * HOUR)) {
			return zones[i]
		}
	}
	return ''
}

// "America/New_York" -> "New York", "America/Argentina/Buenos_Aires" -> "Buenos Aires".
function cityName(zone) {
	var parts = String(zone || '').split('/')
	return parts[parts.length - 1].replace(/_/g, ' ')
}
// "+05:30" style offset text.
function offsetText(offset) {
	var sign = offset < 0 ? '-' : '+'
	var abs = Math.abs(offset)
	var h = Math.floor(abs / 60)
	var m = abs % 60
	return sign + (h < 10 ? '0' : '') + h + ':' + (m < 10 ? '0' : '') + m
}

// Zones whose id (or city) contains every word of `query`, picker zones first; at most `limit`.
function search(query, limit, extra) {
	var words = String(query || '').toLowerCase().replace(/_/g, ' ').split(/[\s\/]+/).filter(function(w) { return w })
	var zones = TimeZoneData.pickerZones.slice()
	if (extra && zones.indexOf(extra) < 0 && knows(extra)) {
		zones.unshift(extra)
	}
	var out = []
	for (var i = 0; i < zones.length && out.length < (limit || 50); i++) {
		var text = zones[i].toLowerCase().replace(/_/g, ' ')
		var ok = true
		for (var j = 0; j < words.length; j++) {
			if (text.indexOf(words[j]) < 0) {
				ok = false
				break
			}
		}
		if (ok) {
			out.push(zones[i])
		}
	}
	return out
}
