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

// Preset key matching an existing rule ('' if none matches). An end (UNTIL / COUNT) is allowed:
// the original rule is kept as long as the user doesn't pick another option.
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
