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
	Qt.openUrlExternally(url)
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

function renderText(text) {
	if (typeof text === 'undefined') {
		return ''
	}
	var out = text
	
	// Render links
	// Google doesn't auto-convert links to anchor tags when you paste a link in the description.
	// However, we should treat it as a link. This simple regex replacement works when we're not
	// dealing with HTML. So if we see an HTML anchor tag, skip it and assume the link has been
	// formatted.
	if (out.indexOf('<a href') === -1) {
		var rUrl = /(http|https):\/\/[\w-]+(\.[\w-]+)+([\w.,@?^=%&amp;:\/~+#-]*[\w@?^=%&amp;\/~+#-])?/gi
		out = out.replace(rUrl, function(m) {
			// Google replaces ampersands with HTML the entity in the url text.
			var encodedUrl = m.replace(/\&/g, '&amp;')

			// Add extra space at the end to prevent styling entire text as a link when ending with a link.
			return '<a href="' + m + '">' + encodedUrl + '</a>' + '&nbsp;'
		})
	}

	// Remove leading new line, as Google sometimes adds them.
	out = out.replace(/^(\<br\>)+/, '')

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
