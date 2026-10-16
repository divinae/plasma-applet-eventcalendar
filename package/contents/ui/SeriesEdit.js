.pragma library

// Moving a whole series of a recurring event by as much as one of its occurrences moved.
// Used by the event editor and by dragging an occurrence in the week view.

function startOfDay(d) {
	return new Date(d.getFullYear(), d.getMonth(), d.getDate())
}

function pad2(n) {
	return (n < 10 ? '0' : '') + n
}

function localDateString(d) {
	return d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate())
}

// The instant of a Google start / end object. All-day dates are local midnight.
function instant(obj) {
	if (obj.dateTime) {
		return new Date(obj.dateTime).getTime()
	}
	var d = obj.date.split('-')
	return new Date(+d[0], +d[1] - 1, +d[2]).getTime()
}

// New start / end objects for `series` (the recurring event), when its occurrence that started
// at `occurrenceStart` (a Date) gets the times `start` / `end` (Google objects). The days the
// occurrence moved and its new time of day are applied to the series start in local time, so a
// daylight saving change between the two dates doesn't shift the hour. Timed events keep the
// series' time zone, or get `timeZone` (Google needs one to expand a recurring event).
function shiftedTimes(series, occurrenceStart, start, end, timeZone) {
	var newStart = new Date(instant(start))
	var dayShift = Math.round((startOfDay(newStart) - startOfDay(new Date(occurrenceStart))) / 86400000)
	var duration = instant(end) - instant(start)
	var seriesStart = new Date(instant(series.start))
	seriesStart.setDate(seriesStart.getDate() + dayShift)
	seriesStart.setHours(newStart.getHours(), newStart.getMinutes(), 0, 0)
	var seriesEnd = new Date(seriesStart.getTime() + duration)
	if (start.date) {
		return {
			start: { date: localDateString(seriesStart) },
			end: { date: localDateString(seriesEnd) },
		}
	}
	var zone = (series.start && series.start.timeZone) || timeZone
	return {
		start: { dateTime: seriesStart.toISOString(), timeZone: zone },
		end: { dateTime: seriesEnd.toISOString(), timeZone: zone },
	}
}
