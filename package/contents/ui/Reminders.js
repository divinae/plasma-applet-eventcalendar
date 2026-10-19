.pragma library

// An event's own reminders in Google Calendar: { useDefault, overrides: [{ method, minutes }] }.
// The editor works with notification ("popup") reminders as { value, unit }; other kinds (email)
// are kept as they are.

var MAX_OVERRIDES = 5 // Google's limit
var MAX_MINUTES = 40320 // 4 weeks, Google's limit
var UNITS = ['minutes', 'hours', 'days', 'weeks']
var UNIT_MINUTES = { minutes: 1, hours: 60, days: 1440, weeks: 10080 }

function toList(value) {
	if (!value) {
		return []
	}
	if (typeof value.length === 'number') {
		return Array.prototype.slice.call(value)
	}
	return []
}

// 90 -> { value: 90, unit: 'minutes' }, 120 -> 2 hours, 1440 -> 1 day.
function split(minutes) {
	minutes = Math.max(0, Math.round(Number(minutes) || 0))
	if (minutes > 0) {
		for (var i = UNITS.length - 1; i > 0; i--) {
			var size = UNIT_MINUTES[UNITS[i]]
			if (minutes % size === 0) {
				return { value: minutes / size, unit: UNITS[i] }
			}
		}
	}
	return { value: minutes, unit: 'minutes' }
}

function toMinutes(item) {
	var minutes = Math.round(Number(item.value) || 0) * (UNIT_MINUTES[item.unit] || 1)
	return Math.max(0, Math.min(MAX_MINUTES, minutes))
}

// The editor's state for an event: { custom, items: [{ value, unit }], others: [overrides] }.
// custom = false: the calendar's default reminders.
function fromEvent(eventItem) {
	var reminders = eventItem && eventItem.reminders
	if (!reminders || reminders.useDefault !== false) {
		return { custom: false, items: [], others: [] }
	}
	var items = []
	var others = []
	toList(reminders.overrides).forEach(function(override) {
		if (override && override.method === 'popup') {
			items.push(split(override.minutes))
		} else if (override) {
			others.push({ method: String(override.method), minutes: Number(override.minutes) })
		}
	})
	items.sort(function(a, b) { return toMinutes(a) - toMinutes(b) })
	return { custom: true, items: items, others: others }
}

// The reminders value to send to Google.
function toGoogle(state) {
	if (!state.custom) {
		return { useDefault: true }
	}
	var overrides = []
	var seen = {}
	toList(state.items).forEach(function(item) {
		var minutes = toMinutes(item)
		if (!seen[minutes]) {
			seen[minutes] = true
			overrides.push({ method: 'popup', minutes: minutes })
		}
	})
	overrides.sort(function(a, b) { return a.minutes - b.minutes })
	overrides = overrides.concat(toList(state.others))
	return { useDefault: false, overrides: overrides.slice(0, MAX_OVERRIDES) }
}

function sameAs(a, b) {
	return JSON.stringify(toGoogle(a)) === JSON.stringify(toGoogle(b))
}

// The notification minutes, as the widget reads them from a parsed event (reminderMinutes).
function popupMinutes(state) {
	return toGoogle(state).overrides
		? toGoogle(state).overrides.filter(function(o) { return o.method === 'popup' }).map(function(o) { return o.minutes })
		: null
}
