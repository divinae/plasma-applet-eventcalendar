.pragma library

// Event search: match events by title, location and description, and order the results
// (upcoming first, soonest first; then past ones, most recent first).

function normalize(text) {
	var s = String(text || '').toLowerCase()
	if (typeof s.normalize === 'function') {
		s = s.normalize('NFD').replace(/[̀-ͯ]/g, '') // "Kraków" matches "krakow"
	}
	return s
}

function tokens(query) {
	return normalize(query).split(/\s+/).filter(function(t) { return t.length > 0 })
}

function plainText(html) {
	return String(html || '').replace(/<[^>]*>/g, ' ').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&')
}

// Every word of the query appears in the title, location or description.
function matches(eventItem, queryTokens) {
	if (!eventItem || !queryTokens || !queryTokens.length) {
		return false
	}
	var haystack = normalize([eventItem.summary, eventItem.location, plainText(eventItem.description)].join(' '))
	for (var i = 0; i < queryTokens.length; i++) {
		if (haystack.indexOf(queryTokens[i]) < 0) {
			return false
		}
	}
	return true
}

function time(value) {
	return value ? new Date(value).getTime() : 0
}

function sortResults(list, now) {
	var nowTime = time(now)
	return list.slice().sort(function(a, b) {
		var aUpcoming = time(a.endDateTime) >= nowTime
		var bUpcoming = time(b.endDateTime) >= nowTime
		if (aUpcoming !== bUpcoming) {
			return aUpcoming ? -1 : 1
		}
		var diff = time(a.startDateTime) - time(b.startDateTime)
		return aUpcoming ? diff : -diff
	})
}

function key(eventItem) {
	return (eventItem.calendarId || '') + '|' + (eventItem.id || '')
}

// Local results plus extra (eg: Google) results not already in the list; sorted, at most limit.
function merge(local, extra, now, limit) {
	var seen = {}
	var list = []
	var sources = [local || [], extra || []]
	for (var s = 0; s < sources.length; s++) {
		for (var i = 0; i < sources[s].length; i++) {
			var k = key(sources[s][i])
			if (!seen[k]) {
				seen[k] = true
				list.push(sources[s][i])
			}
		}
	}
	return sortResults(list, now).slice(0, limit || 100)
}

function isTask(item) {
	return !!item && item.kind === 'tasks#task'
}

// The loaded events (not tasks: searchTasks) that match the query.
function searchLocal(items, query, now, limit) {
	var queryTokens = tokens(query)
	if (!queryTokens.length) {
		return []
	}
	var found = []
	for (var i = 0; i < (items || []).length; i++) {
		if (!isTask(items[i]) && matches(items[i], queryTokens)) {
			found.push(items[i])
		}
	}
	return merge(found, [], now, limit)
}

// Every word of the query in a task's title or notes.
function matchesTask(item, queryTokens) {
	var haystack = normalize([item.summary || item.title, item.notes || item.description].join(' '))
	for (var i = 0; i < queryTokens.length; i++) {
		if (haystack.indexOf(queryTokens[i]) < 0) {
			return false
		}
	}
	return queryTokens.length > 0
}

// The loaded tasks that match the query (title, notes), each once: open ones first, the earliest
// due first (undated after the dated ones), then the done ones; at most limit.
function searchTasks(items, query, limit) {
	var queryTokens = tokens(query)
	if (!queryTokens.length) {
		return []
	}
	var seen = {}
	var found = []
	for (var i = 0; i < (items || []).length; i++) {
		var item = items[i]
		if (!isTask(item) || seen[key(item)] || !matchesTask(item, queryTokens)) {
			continue
		}
		seen[key(item)] = true
		found.push(item)
	}
	var rank = function(item) {
		var due = typeof item.due === 'string' ? item.due.substring(0, 10) : ''
		return (item.status === 'completed' ? '2' : due ? '0' : '1') + due
	}
	found.sort(function(a, b) {
		var ra = rank(a)
		var rb = rank(b)
		return ra < rb ? -1 : ra > rb ? 1 : 0
	})
	return found.slice(0, limit || 100)
}

if (typeof module !== 'undefined') {
	module.exports = {
		normalize: normalize,
		tokens: tokens,
		matches: matches,
		sortResults: sortResults,
		merge: merge,
		searchLocal: searchLocal,
		searchTasks: searchTasks,
	}
}
