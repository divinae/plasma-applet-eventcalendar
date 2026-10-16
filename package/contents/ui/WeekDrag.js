.pragma library

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
