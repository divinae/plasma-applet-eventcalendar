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

function searchLocal(items, query, now, limit) {
	var queryTokens = tokens(query)
	if (!queryTokens.length) {
		return []
	}
	var found = []
	for (var i = 0; i < (items || []).length; i++) {
		if (matches(items[i], queryTokens)) {
			found.push(items[i])
		}
	}
	return merge(found, [], now, limit)
}

if (typeof module !== 'undefined') {
	module.exports = {
		normalize: normalize,
		tokens: tokens,
		matches: matches,
		sortResults: sortResults,
		merge: merge,
		searchLocal: searchLocal,
	}
}
