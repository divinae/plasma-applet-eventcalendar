.pragma library

.import "Shared.js" as Shared

// Events per visible day, for the month grid.

function isAllDay(eventItem) {
	return !!(eventItem.start && eventItem.start.date)
}

// All-day events first, then by start time.
function compareEvents(a, b) {
	var aAllDay = isAllDay(a)
	var bAllDay = isAllDay(b)
	if (aAllDay !== bAllDay) {
		return aAllDay ? -1 : 1
	}
	return a.startDateTime - b.startDateTime
}

// dayTimes: ascending midnight timestamps of the visible days.
// Returns one sorted array of events per day.
function bucketByDay(items, dayTimes) {
	var dayEvents = dayTimes.map(function() { return [] })
	for (var i = 0; i < items.length; i++) {
		var eventItem = items[i]
		var startTime = Shared.startOfDay(eventItem.startDateTime).getTime()
		// The end is exclusive: an event (or all-day event) ending at midnight doesn't cover the
		// next day. Zero-length events stay on their start day.
		var start = new Date(eventItem.startDateTime).getTime()
		var lastInstant = Math.max(start, new Date(eventItem.endDateTime).getTime() - 1)
		var endTime = Shared.startOfDay(new Date(lastInstant)).getTime()
		for (var d = 0; d < dayTimes.length; d++) {
			if (endTime < dayTimes[d]) {
				break
			}
			if (startTime <= dayTimes[d]) {
				dayEvents[d].push(eventItem)
			}
		}
	}
	for (var k = 0; k < dayEvents.length; k++) {
		dayEvents[k].sort(compareEvents)
	}
	return dayEvents
}
