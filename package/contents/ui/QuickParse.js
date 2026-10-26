.pragma library

// Smart quick add: the due day, time, priority, list and repeat in a line like
// "Buy milk tomorrow 17:00 !high #Home every week". English and Polish words, plus the system
// locale's day and month names passed in (no Qt.locale() here, so it runs in node too).
//
// parse(text, opts) -> { title, dueDay: 'YYYY-MM-DD' | '', dueTime: 'HH:mm' | '', priority: 0 | 1
// | 3 | 5, listId, repeatRule: 'RRULE:...' | '', tokens: [{ text, kind, start, end, value }] }
// opts: {
//   today: 'YYYY-MM-DD' (required for dates),
//   lists: [{ id, name }] for '#Name',
//   dayFirst: true when the locale writes the day before the month (10/11 = 10 November),
//   dayNames: [[names of Sunday], [Monday], ...] more weekday names (the locale's),
//   monthNames: [[names of January], ...] more month names (the locale's),
//   ignore: ['kind:text'] tokens the user ruled out (kept in the title, see tokenKey),
// }
// kind: 'date', 'time', 'priority', 'list' or 'repeat'. The first of each kind counts; a later
// one stays in the title. A token never starts or ends inside a word.

var PRIORITY_LOW = 1
var PRIORITY_MEDIUM = 3
var PRIORITY_HIGH = 5

var DAY_CODES = ['SU', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA']

// Weekday words, Sunday first. No "sun", "sat" or "wed": everyday words.
var DAY_WORDS = [
	['sunday', 'niedziela', 'niedzielę', 'niedziele', 'niedz', 'nd'],
	['monday', 'mon', 'poniedziałek', 'poniedzialek', 'pon'],
	['tuesday', 'tue', 'tues', 'wtorek', 'wt'],
	['wednesday', 'środa', 'środę', 'sroda', 'srode', 'śr', 'sr'],
	['thursday', 'thu', 'thur', 'thurs', 'czwartek', 'czw'],
	['friday', 'fri', 'piątek', 'piatek', 'pt'],
	['saturday', 'sobota', 'sobotę', 'sobote', 'sob'],
]

// Month words (only taken next to a day number, so "May" alone is a name).
var MONTH_WORDS = [
	['january', 'jan', 'styczeń', 'stycznia', 'sty'],
	['february', 'feb', 'luty', 'lutego', 'lut'],
	['march', 'mar', 'marzec', 'marca'],
	['april', 'apr', 'kwiecień', 'kwietnia', 'kwi'],
	['may', 'maj', 'maja'],
	['june', 'jun', 'czerwiec', 'czerwca', 'cze'],
	['july', 'jul', 'lipiec', 'lipca', 'lip'],
	['august', 'aug', 'sierpień', 'sierpnia', 'sie'],
	['september', 'sep', 'sept', 'wrzesień', 'września', 'wrzesnia', 'wrz'],
	['october', 'oct', 'październik', 'października', 'pazdziernika', 'paź', 'paz'],
	['november', 'nov', 'listopad', 'listopada', 'lis'],
	['december', 'dec', 'grudzień', 'grudnia', 'gru'],
]

// The key of a token for opts.ignore.
function tokenKey(token) {
	return token.kind + ':' + String(token.text).toLowerCase()
}

function pad2(n) {
	return (n < 10 ? '0' : '') + n
}

function escapeRe(s) {
	return String(s).replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
}

// A letter (any script), digit or underscore.
function isWordChar(c) {
	return !!c && (/[0-9_]/.test(c) || c.toLowerCase() !== c.toUpperCase())
}

//--- Days as 'YYYY-MM-DD' (UTC arithmetic: no time zone in the way)

function dayOf(y, m, d) {
	var date = new Date(Date.UTC(y, m - 1, d))
	return date.getUTCFullYear() + '-' + pad2(date.getUTCMonth() + 1) + '-' + pad2(date.getUTCDate())
}

function partsOf(day) {
	var p = String(day).split('-')
	return { y: Number(p[0]), m: Number(p[1]), d: Number(p[2]) }
}

function addDays(day, n) {
	var p = partsOf(day)
	return dayOf(p.y, p.m, p.d + n)
}

function weekdayOf(day) {
	var p = partsOf(day)
	return new Date(Date.UTC(p.y, p.m - 1, p.d)).getUTCDay()
}

function validDate(y, m, d) {
	if (!(m >= 1 && m <= 12 && d >= 1 && d <= 31)) {
		return false
	}
	return dayOf(y, m, d) === y + '-' + pad2(m) + '-' + pad2(d)
}

// The day of month m, day d: in year y when given, else the next one from today on.
function dateValue(today, y, m, d) {
	if (y) {
		if (y < 100) {
			y += 2000
		}
		return validDate(y, m, d) ? dayOf(y, m, d) : ''
	}
	var t = partsOf(today)
	for (var year = t.y; year <= t.y + 4; year++) { // 29 February: the next leap year
		if (validDate(year, m, d) && dayOf(year, m, d) >= today) {
			return dayOf(year, m, d)
		}
	}
	return ''
}

// The next weekday wd (0 Sunday) after today; includeToday: today counts.
function nextWeekday(today, wd, includeToday) {
	var n = (wd - weekdayOf(today) + 7) % 7
	if (n === 0 && !includeToday) {
		n = 7
	}
	return addDays(today, n)
}

function timeValue(h, min, ampm) {
	h = Number(h)
	min = Number(min || 0)
	if (ampm) {
		if (h < 1 || h > 12) {
			return ''
		}
		var pm = /^p/i.test(ampm)
		h = h % 12 + (pm ? 12 : 0)
	}
	if (!(h >= 0 && h <= 23 && min >= 0 && min <= 59)) {
		return ''
	}
	return pad2(h) + ':' + pad2(min)
}

function numberWord(s) {
	var w = String(s).toLowerCase()
	if (w === 'a' || w === 'an' || w === 'one' || w === 'jeden') {
		return 1
	}
	return Number(w)
}

//--- Word lists

function mergeNames(base, extra) {
	var out = []
	for (var i = 0; i < base.length; i++) {
		var names = base[i].slice()
		var more = extra && extra[i] ? extra[i] : []
		for (var j = 0; j < more.length; j++) {
			var name = String(more[j] || '').toLowerCase().replace(/\.$/, '')
			if (name.length >= 3 && names.indexOf(name) < 0) {
				names.push(name)
			}
		}
		out.push(names)
	}
	return out
}

// [{ word, index }] longest first, for one regex alternation.
function wordTable(groups) {
	var table = []
	for (var i = 0; i < groups.length; i++) {
		for (var j = 0; j < groups[i].length; j++) {
			table.push({ word: groups[i][j], index: i })
		}
	}
	table.sort(function(a, b) { return b.word.length - a.word.length })
	return table
}

function alternation(table) {
	return '(' + table.map(function(e) { return escapeRe(e.word) }).join('|') + ')'
}

function indexOfWord(table, word) {
	var w = String(word).toLowerCase()
	for (var i = 0; i < table.length; i++) {
		if (table[i].word === w) {
			return table[i].index
		}
	}
	return -1
}

//--- The rules, in the order they are tried. Each: { kind, re, value(m) -> value | null }.
// re: a regex source, matched case-insensitively; value null: not a token after all.

function rules(opts) {
	var today = opts.today || ''
	var days = wordTable(mergeNames(DAY_WORDS, opts.dayNames))
	var months = wordTable(mergeNames(MONTH_WORDS, opts.monthNames))
	var DAY = alternation(days)
	var MONTH = alternation(months)
	var lists = opts.lists || []
	var dayFirst = !!opts.dayFirst
	var list = []
	var add = function(kind, re, value) {
		list.push({ kind: kind, re: re, value: value })
	}
	var dated = function(fn) {
		return function(m) { return today ? fn(m) || null : null }
	}
	var freq = function(word) {
		var w = String(word).toLowerCase()
		if (/^(day|days|dzień|dzien|dni)$/.test(w)) return 'DAILY'
		if (/^(year|years|rok|lata|lat)$/.test(w)) return 'YEARLY'
		if (/^(week|weeks|tydzień|tydzien|tygodnie|tygodni)$/.test(w)) return 'WEEKLY'
		if (/^(month|months|miesiąc|miesiac|miesiące|miesiace|miesięcy|miesiecy)$/.test(w)) return 'MONTHLY'
		return 'YEARLY'
	}
	var rule = function(f, interval, byDay) {
		return 'RRULE:FREQ=' + f + ';INTERVAL=' + (interval || 1) + (byDay ? ';BYDAY=' + byDay : '')
	}

	//--- Repeat
	add('repeat', '(?:every|each)\\s+(\\d{1,3})\\s+(days|weeks|months|years)', function(m) {
		return Number(m[1]) >= 1 ? rule(freq(m[2]), Number(m[1])) : null
	})
	add('repeat', '(?:every|each)\\s+(?:weekday|work\\s?day)', function() { return rule('WEEKLY', 1, 'MO,TU,WE,TH,FR') })
	add('repeat', '(?:every|each)\\s+' + DAY, function(m) {
		return rule('WEEKLY', 1, DAY_CODES[indexOfWord(days, m[1])])
	})
	add('repeat', '(?:every|each)\\s+(day|week|month|year)', function(m) { return rule(freq(m[1])) })
	add('repeat', '(daily|weekly|monthly|yearly|annually)', function(m) {
		var w = m[1].toLowerCase()
		return rule(w === 'daily' ? 'DAILY' : w === 'weekly' ? 'WEEKLY' : w === 'monthly' ? 'MONTHLY' : 'YEARLY')
	})
	add('repeat', '(codziennie|co\\s+dzień|co\\s+dzien|każdego\\s+dnia|kazdego\\s+dnia)', function() { return rule('DAILY') })
	add('repeat', 'co\\s+(\\d{1,3})\\s+(dni|tygodnie|tygodni|miesiące|miesiace|miesięcy|miesiecy)', function(m) {
		return Number(m[1]) >= 1 ? rule(freq(m[2]), Number(m[1])) : null
	})
	add('repeat', 'co\\s+(tydzień|tydzien|miesiąc|miesiac)', function(m) { return rule(freq(m[1])) })
	add('repeat', '(co\\s+roku|co\\s+rok|corocznie)', function() { return rule('YEARLY') })
	add('repeat', '(?:co|w\\s+każdy|w\\s+każdą|w\\s+kazdy|w\\s+kazda|każdy|każdą)\\s+' + DAY, function(m) {
		return rule('WEEKLY', 1, DAY_CODES[indexOfWord(days, m[1])])
	})

	//--- Dates with month names (before times: "o 17 października")
	add('date', '(?:on\\s+)?(\\d{1,2})(?:st|nd|rd|th|\\.)?\\s+' + MONTH + '(?:\\s+((?:19|20)\\d{2}))?', dated(function(m) {
		return dateValue(today, Number(m[3] || 0), indexOfWord(months, m[2]) + 1, Number(m[1]))
	}))
	add('date', '(?:on\\s+)?' + MONTH + '\\s+(\\d{1,2})(?:st|nd|rd|th)?(?:,?\\s+((?:19|20)\\d{2}))?', dated(function(m) {
		return dateValue(today, Number(m[3] || 0), indexOfWord(months, m[1]) + 1, Number(m[2]))
	}))

	//--- Times said as such ("at 17", "o 12.10", "@5pm"): before the numeric dates
	add('time', '(?:at|o|@|godz\\.?|godzina)\\s*(\\d{1,2})(?:[:.](\\d{2}))?(?:\\s*(am|pm|a\\.m\\.|p\\.m\\.))?', function(m) {
		return timeValue(m[1], m[2], m[3]) || null
	})

	//--- Numeric dates
	add('date', '((?:19|20)\\d{2})-(\\d{1,2})-(\\d{1,2})', dated(function(m) {
		return dateValue(today, Number(m[1]), Number(m[2]), Number(m[3]))
	}))
	add('date', '(?:on\\s+)?(\\d{1,2})\\.(\\d{1,2})(?:\\.((?:19|20)?\\d{2}))?', dated(function(m) {
		return dateValue(today, Number(m[3] || 0), Number(m[2]), Number(m[1]))
	}))
	add('date', '(?:on\\s+)?(\\d{1,2})/(\\d{1,2})(?:/((?:19|20)?\\d{2}))?', dated(function(m) {
		var a = Number(m[1]), b = Number(m[2]), y = Number(m[3] || 0)
		var first = dayFirst ? dateValue(today, y, b, a) : dateValue(today, y, a, b)
		return first || (dayFirst ? dateValue(today, y, a, b) : dateValue(today, y, b, a))
	}))

	//--- Relative dates
	add('date', '(?:the\\s+)?day\\s+after\\s+tomorrow|pojutrze', dated(function() { return addDays(today, 2) }))
	add('date', 'tomorrow|tmrw|jutro', dated(function() { return addDays(today, 1) }))
	add('date', 'today|dziś|dzisiaj|dzis', dated(function() { return today }))
	var after = function(n, f) {
		if (f === 'DAILY') return addDays(today, n)
		if (f === 'WEEKLY') return addDays(today, 7 * n)
		var t = partsOf(today)
		var mm = t.m - 1 + (f === 'YEARLY' ? 12 * n : n)
		var y = t.y + Math.floor(mm / 12)
		mm = mm % 12 + 1
		var last = new Date(Date.UTC(y, mm, 0)).getUTCDate()
		return dayOf(y, mm, Math.min(t.d, last))
	}
	add('date', '(?:in|za)\\s+(\\d{1,3}|an?|one|jeden)\\s+(days?|weeks?|months?|years?|dni|dzień|dzien|tygodnie|tygodni|tydzień|tydzien|miesiące|miesiace|miesięcy|miesiecy|miesiąc|miesiac|lata|lat|rok)', dated(function(m) {
		var n = numberWord(m[1])
		return n >= 0 ? after(n, freq(m[2])) : null
	}))
	add('date', 'za\\s+(tydzień|tydzien|miesiąc|miesiac|rok)', dated(function(m) { return after(1, freq(m[1])) }))
	add('date', 'next\\s+week|w\\s+przyszłym\\s+tygodniu|w\\s+przyszlym\\s+tygodniu|(?:w\\s+)?przyszły\\s+tydzień|(?:w\\s+)?przyszly\\s+tydzien', dated(function() {
		return nextWeekday(today, 1, false)
	}))
	add('date', '(?:(?:next|this|on|(?:w|we)(?:\\s+(?:przyszły|przyszłą|przyszłe|przyszly|przyszla|przyszle|następny|następną|nastepny|nastepna))?|przyszły|przyszłą|przyszly|przyszla|następny|następną|nastepny|nastepna)\\s+)?' + DAY, dated(function(m) {
		return nextWeekday(today, indexOfWord(days, m[1]), false)
	}))

	//--- Plain times
	add('time', '(\\d{1,2})[:.](\\d{2})(?:\\s*(am|pm|a\\.m\\.|p\\.m\\.))?', function(m) { return timeValue(m[1], m[2], m[3]) || null })
	add('time', '(\\d{1,2})\\s*(am|pm|a\\.m\\.|p\\.m\\.)', function(m) { return timeValue(m[1], 0, m[2]) || null })
	add('time', '(\\d{1,2})h(\\d{2})?', function(m) { return timeValue(m[1], m[2]) || null })

	//--- Priority: after a space or at the start
	add('priority', '!(high|wysoki|wysoka|3|!!)', function() { return PRIORITY_HIGH })
	add('priority', '!(medium|med|średni|sredni|średnia|srednia|2|!)', function() { return PRIORITY_MEDIUM })
	add('priority', '!(low|niski|niska|1)?', function() { return PRIORITY_LOW })

	//--- List: '#' after a space or at the start, the list whose name starts with the rest
	add('list', '#([^\\s#!@,;.]+)', function(m) {
		var want = m[1].toLowerCase()
		var found = null
		for (var i = 0; i < lists.length; i++) {
			var name = String(lists[i].name || '').toLowerCase()
			if (name === want) {
				return lists[i].id
			}
			if (!found && name.indexOf(want) === 0) {
				found = lists[i].id
			}
		}
		return found
	})
	return list
}

function parse(text, opts) {
	text = String(text || '')
	opts = opts || {}
	var ignore = opts.ignore || []
	var taken = [] // [start, end) spans: tokens and ignored ones
	var tokens = []
	var found = {}
	var free = function(start, end) {
		for (var i = 0; i < taken.length; i++) {
			if (start < taken[i][1] && taken[i][0] < end) {
				return false
			}
		}
		return true
	}
	var all = rules(opts)
	for (var r = 0; r < all.length; r++) {
		var rule = all[r]
		if (found[rule.kind]) {
			continue
		}
		var re = new RegExp(rule.re, 'gi')
		var m
		while ((m = re.exec(text)) !== null) {
			if (m[0].length === 0) {
				re.lastIndex++
				continue
			}
			var start = m.index
			var end = start + m[0].length
			var before = start > 0 ? text.charAt(start - 1) : ''
			var after = text.charAt(end)
			var sigil = rule.kind === 'priority' || rule.kind === 'list'
			var okBefore = sigil ? !before || /\s/.test(before) : !isWordChar(before) && !/[#!@\/:.\-]/.test(before)
			var okAfter = !isWordChar(after) && !/[#!@\/:]/.test(after) && !(after === '.' && /\d/.test(text.charAt(end + 1)))
			if (!okBefore || !okAfter || !free(start, end)) {
				re.lastIndex = start + 1
				continue
			}
			var value = rule.value(m)
			if (value === null || value === '' || typeof value === 'undefined') {
				re.lastIndex = start + 1
				continue
			}
			var token = { text: m[0], kind: rule.kind, start: start, end: end, value: value }
			taken.push([start, end])
			if (ignore.indexOf(tokenKey(token)) >= 0) {
				continue // Stays in the title, and nothing else takes it
			}
			tokens.push(token)
			found[rule.kind] = token
			break
		}
	}
	tokens.sort(function(a, b) { return a.start - b.start })

	var title = ''
	var at = 0
	for (var t = 0; t < tokens.length; t++) {
		title += text.substring(at, tokens[t].start) + ' '
		at = tokens[t].end
	}
	title += text.substring(at)

	var dueDay = found.date ? found.date.value : ''
	var repeatRule = found.repeat ? found.repeat.value : ''
	// "every monday" without a day: the first monday, today included.
	var byDay = /BYDAY=([A-Z]{2})(?:;|$)/.exec(repeatRule)
	if (!dueDay && byDay && opts.today) {
		dueDay = nextWeekday(opts.today, DAY_CODES.indexOf(byDay[1]), true)
	}
	return {
		title: title.replace(/\s+/g, ' ').trim(),
		dueDay: dueDay,
		dueTime: found.time ? found.time.value : '',
		priority: found.priority ? found.priority.value : 0,
		listId: found.list ? found.list.value : '',
		repeatRule: repeatRule,
		tokens: tokens,
	}
}
