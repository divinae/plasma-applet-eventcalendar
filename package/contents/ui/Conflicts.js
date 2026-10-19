.pragma library

.import "Shared.js" as Shared

// Meetings that overlap another one. Only timed events the user takes part in count: all-day
// events, "free" ones (transparency: 'transparent'), tasks, cancelled and declined events don't.
// Touching ends (one ends at 10:00, the next starts at 10:00) are not a conflict.

function eventKey(eventItem) {
	return String(eventItem.calendarId || '') + '|' + String(eventItem.id || '') + '|' + new Date(eventItem.startDateTime).getTime()
}

function isBusy(eventItem) {
	if (!eventItem || eventItem.kind === 'tasks#task' || (eventItem.start && eventItem.start.date)) {
		return false
	}
	if (eventItem.transparency === 'transparent' || eventItem.status === 'cancelled') {
		return false
	}
	return Shared.myResponse(eventItem) !== 'declined'
}

// { eventKey: [titles of the events it overlaps] }, only for events that overlap something.
function find(events) {
	var list = []
	var all = Shared.toArray(events)
	for (var i = 0; i < all.length; i++) {
		var eventItem = all[i]
		if (!isBusy(eventItem)) {
			continue
		}
		var start = new Date(eventItem.startDateTime).getTime()
		var end = new Date(eventItem.endDateTime).getTime()
		if (isFinite(start) && isFinite(end) && end > start) {
			list.push({ item: eventItem, start: start, end: end, key: eventKey(eventItem) })
		}
	}
	list.sort(function(a, b) { return a.start - b.start })

	var result = {}
	function add(a, b) {
		var titles = result[a.key] || (result[a.key] = [])
		var title = String(b.item.summary || '')
		if (titles.indexOf(title) < 0) {
			titles.push(title)
		}
	}
	// Sweep by start time, keeping the events that haven't ended yet.
	var active = []
	for (var j = 0; j < list.length; j++) {
		var current = list[j]
		active = active.filter(function(other) { return other.end > current.start })
		for (var k = 0; k < active.length; k++) {
			// The same meeting shown from two calendars is not a conflict with itself.
			if (active[k].item.id && active[k].item.id === current.item.id) {
				continue
			}
			add(active[k], current)
			add(current, active[k])
		}
		active.push(current)
	}
	return result
}
