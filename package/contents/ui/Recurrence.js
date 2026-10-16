.pragma library

// Repeat presets for the event editor, as Google Calendar RRULE lines (RFC 5545).

var dayCodes = ['SU', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA'] // Date.getDay() order

// Preset rules for an event starting on `start`. Keys: none, daily, weekdays, weekly, monthly, yearly.
function presetRule(key, start) {
	switch (key) {
		case 'daily': return 'RRULE:FREQ=DAILY'
		case 'weekdays': return 'RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR'
		case 'weekly': return 'RRULE:FREQ=WEEKLY;BYDAY=' + dayCodes[start.getDay()]
		case 'monthly': return 'RRULE:FREQ=MONTHLY;BYMONTHDAY=' + start.getDate()
		case 'yearly': return 'RRULE:FREQ=YEARLY'
		default: return ''
	}
}

// The RRULE line of a Google recurrence list (which may also have EXDATE / RDATE lines).
function ruleOf(recurrence) {
	var lines = recurrence || []
	for (var i = 0; i < lines.length; i++) {
		if (String(lines[i]).indexOf('RRULE:') === 0) {
			return String(lines[i])
		}
	}
	return ''
}

function parts(rule) {
	var result = {}
	String(rule).replace(/^RRULE:/, '').split(';').forEach(function(part) {
		var kv = part.split('=')
		if (kv.length === 2) {
			result[kv[0].toUpperCase()] = kv[1].toUpperCase()
		}
	})
	return result
}

// Preset key matching an existing rule ('' if none matches). The end (UNTIL / COUNT) doesn't
// matter here: the editor keeps it separately (endOf / withEnd).
function matchPreset(rule, start) {
	if (!rule) {
		return 'none'
	}
	var p = parts(rule)
	if (p.INTERVAL && p.INTERVAL !== '1') {
		return ''
	}
	var keys = ['daily', 'weekdays', 'weekly', 'monthly', 'yearly']
	for (var i = 0; i < keys.length; i++) {
		var q = parts(presetRule(keys[i], start))
		var same = p.FREQ === q.FREQ
			&& (p.BYDAY || '') === (q.BYDAY || '')
			&& (!p.BYMONTHDAY || p.BYMONTHDAY === q.BYMONTHDAY)
			&& !p.BYMONTH && !p.BYSETPOS
		if (same) {
			return keys[i]
		}
	}
	return ''
}

// Replace the RRULE line of a recurrence list, keeping EXDATE / RDATE lines. rule '' removes it all.
function withRule(recurrence, rule) {
	if (!rule) {
		return []
	}
	var others = (recurrence || []).filter(function(line) {
		return String(line).indexOf('RRULE:') !== 0
	})
	return [rule].concat(others)
}

// An RRULE as an object: { freq, interval, byDay: ['MO', ...], byMonthDay, until: Date | null,
// count, supported }. until is the local day of the last occurrence. supported is false when the
// rule has parts the editor can't show (BYSETPOS, BYMONTH, numbered BYDAY like 3FR, ...): such a
// rule is kept as it is, only its end can change.
function parseRule(rule) {
	var p = parts(rule)
	var result = {
		freq: p.FREQ || '',
		interval: p.INTERVAL ? parseInt(p.INTERVAL, 10) || 1 : 1,
		byDay: p.BYDAY ? p.BYDAY.split(',') : [],
		byMonthDay: p.BYMONTHDAY ? parseInt(p.BYMONTHDAY, 10) || 0 : 0,
		until: p.UNTIL ? parseUntil(p.UNTIL) : null,
		count: p.COUNT ? parseInt(p.COUNT, 10) || 0 : 0,
		supported: true,
	}
	var known = ['FREQ', 'INTERVAL', 'BYDAY', 'BYMONTHDAY', 'UNTIL', 'COUNT', 'WKST']
	for (var key in p) {
		if (known.indexOf(key) < 0) {
			result.supported = false
		}
	}
	if (['DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY'].indexOf(result.freq) < 0) {
		result.supported = false
	}
	if (result.byDay.length && (result.freq !== 'WEEKLY' || result.byDay.some(function(d) { return dayCodes.indexOf(d) < 0 }))) {
		result.supported = false
	}
	if (p.BYMONTHDAY && (result.freq !== 'MONTHLY' || String(result.byMonthDay) !== p.BYMONTHDAY)) {
		result.supported = false
	}
	return result
}

// An RRULE line from an object like parseRule's. allDay: the event's kind, which sets the UNTIL
// format Google wants (a date for all-day events, a UTC time otherwise).
function buildRule(obj, allDay) {
	var rule = 'RRULE:FREQ=' + obj.freq
	if (obj.interval > 1) {
		rule += ';INTERVAL=' + obj.interval
	}
	if (obj.freq === 'WEEKLY' && obj.byDay && obj.byDay.length) {
		// Week order, so the same days always give the same rule.
		var days = dayCodes.filter(function(d) { return obj.byDay.indexOf(d) >= 0 })
		rule += ';BYDAY=' + days.join(',')
	}
	if (obj.freq === 'MONTHLY' && obj.byMonthDay) {
		rule += ';BYMONTHDAY=' + obj.byMonthDay
	}
	return withEnd(rule, endOfObject(obj), allDay)
}

function endOfObject(obj) {
	if (obj.count > 0) {
		return { type: 'count', count: obj.count }
	}
	if (obj.until) {
		return { type: 'until', date: obj.until }
	}
	return { type: 'never' }
}

// The end of a rule: { type: 'never' | 'until' | 'count', date, count }.
function endOf(rule) {
	return endOfObject(parseRule(rule))
}

// The rule with its end replaced. The other parts stay as they are, in their order.
function withEnd(rule, end, allDay) {
	if (!rule) {
		return ''
	}
	var kept = String(rule).replace(/^RRULE:/, '').split(';').filter(function(part) {
		var key = part.split('=')[0].toUpperCase()
		return part && key !== 'UNTIL' && key !== 'COUNT'
	})
	if (end && end.type === 'until' && end.date) {
		kept.push('UNTIL=' + untilString(end.date, allDay))
	} else if (end && end.type === 'count' && end.count > 0) {
		kept.push('COUNT=' + Math.floor(end.count))
	}
	return 'RRULE:' + kept.join(';')
}

function pad2(n) {
	return (n < 10 ? '0' : '') + n
}

// UNTIL for the local day `date`, inclusive. Timed events: the end of that day, in UTC.
function untilString(date, allDay) {
	var d = new Date(date)
	if (allDay) {
		return '' + d.getFullYear() + pad2(d.getMonth() + 1) + pad2(d.getDate())
	}
	d = new Date(d.getFullYear(), d.getMonth(), d.getDate(), 23, 59, 59)
	return '' + d.getUTCFullYear() + pad2(d.getUTCMonth() + 1) + pad2(d.getUTCDate())
		+ 'T' + pad2(d.getUTCHours()) + pad2(d.getUTCMinutes()) + pad2(d.getUTCSeconds()) + 'Z'
}

// The local day of an UNTIL value (YYYYMMDD, YYYYMMDDTHHMMSSZ or a floating YYYYMMDDTHHMMSS).
function parseUntil(value) {
	var m = /^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z?))?$/.exec(String(value).toUpperCase())
	if (!m) {
		return null
	}
	if (!m[4]) {
		return new Date(+m[1], +m[2] - 1, +m[3])
	}
	var d = m[7]
		? new Date(Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6]))
		: new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6])
	return new Date(d.getFullYear(), d.getMonth(), d.getDate())
}

// Editor state for a rule picked from a preset or parsed: { freq, interval, byDay }.
function customOf(rule, start) {
	var r = parseRule(rule)
	var freq = r.supported ? r.freq : 'WEEKLY'
	var byDay = r.supported && freq === 'WEEKLY' && r.byDay.length ? r.byDay : [dayCodes[start.getDay()]]
	return { freq: freq, interval: r.supported ? r.interval : 1, byDay: byDay }
}
