.pragma library

.import "Shared.js" as Shared

// Positions <-> times for dragging event blocks in the week / day view's hour grid.

var snapMinutes = 15

// The time at `y` in the hour grid (0 = firstHour) of the day starting at `dayStart`, snapped to
// snapMinutes. The inverse of WeekView.hourY. Local wall clock time, so a daylight saving day
// still gives the hour under the pointer.
function timeAtY(y, dayStart, firstHour, hourHeight) {
	var minutes = Math.round((y / hourHeight + firstHour) * 60 / snapMinutes) * snapMinutes
	var d = new Date(dayStart)
	d.setHours(0, minutes, 0, 0)
	return d
}

// The day column at `x` (grid coordinates, the hour labels on the left), within the shown days.
function dayIndexAtX(x, gutterWidth, columnWidth, dayCount) {
	var index = Math.floor((x - gutterWidth) / columnWidth)
	return Math.max(0, Math.min(dayCount - 1, index))
}

// New { start, end } for a moved block: the same duration from the new start.
function moved(start, end, newStart) {
	return { start: newStart, end: new Date(newStart.getTime() + (end - start)) }
}

// New { start, end } for a block resized from its bottom edge: at least snapMinutes long.
function resized(start, end, newEnd) {
	var min = start.getTime() + snapMinutes * 60000
	return { start: start, end: new Date(Math.max(min, newEnd.getTime())) }
}

//--- Whole day moves (month view, all-day row)

// Events that can be dragged: editable calendar events (not tasks, they only have a due date).
function canMove(eventItem) {
	return !!eventItem && !!eventItem.canEdit && eventItem.kind !== 'tasks#task'
		&& !!eventItem.start && !!(eventItem.start.date || eventItem.start.dateTime)
}

// Days from the day of `from` to the day of `to` (Dates or ms), in local calendar days: a
// daylight saving change in between doesn't make it a fraction.
function dayDelta(from, to) {
	var a = new Date(from)
	var b = new Date(to)
	return Math.round((Date.UTC(b.getFullYear(), b.getMonth(), b.getDate()) - Date.UTC(a.getFullYear(), a.getMonth(), a.getDate())) / 86400000)
}

// The Google start / end objects of `event` moved by `days` whole days, with the new times as
// Dates: { start, end, startDateTime, endDateTime }. All-day events keep their length in days,
// timed events their local time of day, duration and time zones.
function movedByDays(event, days) {
	if (event.start.date) {
		var startDay = Shared.addDays(Shared.parseLocalDate(event.start.date), days)
		var endDay = event.end && event.end.date ? Shared.addDays(Shared.parseLocalDate(event.end.date), days) : Shared.addDays(startDay, 1)
		return {
			start: { date: Shared.localDateString(startDay) },
			end: { date: Shared.localDateString(endDay) },
			startDateTime: startDay,
			endDateTime: endDay,
		}
	}
	var oldStart = new Date(event.start.dateTime)
	var oldEnd = new Date(event.end.dateTime)
	var newStart = Shared.addDays(oldStart, days)
	var newEnd = new Date(newStart.getTime() + (oldEnd - oldStart))
	var times = timedTimes(event, newStart, newEnd)
	times.startDateTime = newStart
	times.endDateTime = newEnd
	return times
}

// Google start / end objects for the Dates `start` / `end`, with the event's time zones (a copy
// needs them; Google keeps them on a move anyway).
function timedTimes(event, start, end) {
	var s = { dateTime: start.toISOString() }
	var e = { dateTime: end.toISOString() }
	if (event.start && event.start.timeZone) {
		s.timeZone = event.start.timeZone
	}
	if (event.end && event.end.timeZone) {
		e.timeZone = event.end.timeZone
	}
	return { start: s, end: e }
}
