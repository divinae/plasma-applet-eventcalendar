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
		var endDate = Shared.startOfDay(eventItem.endDateTime)
		if (eventItem.end.date) {
			// All day events end at midnight which is technically the next day.
			endDate.setDate(endDate.getDate() - 1)
		}
		var endTime = endDate.getTime()
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
