.pragma library

.import "Shared.js" as Shared

// Moving a whole series of a recurring event by as much as one of its occurrences moved.
// Used by the event editor and by dragging an occurrence in the week view.

// The instant of a Google start / end object. All-day dates are local midnight.
function instant(obj) {
	if (obj.dateTime) {
		return new Date(obj.dateTime).getTime()
	}
	return Shared.parseLocalDate(obj.date).getTime()
}

// New start / end objects for `series` (the recurring event), when its occurrence that started
// at `occurrenceStart` (a Date) gets the times `start` / `end` (Google objects). The days the
// occurrence moved and its new time of day are applied to the series start in local time, so a
// daylight saving change between the two dates doesn't shift the hour. Timed events keep the
// series' time zone, or get `timeZone` (Google needs one to expand a recurring event).
function shiftedTimes(series, occurrenceStart, start, end, timeZone) {
	var newStart = new Date(instant(start))
	var dayShift = Math.round((Shared.startOfDay(newStart) - Shared.startOfDay(new Date(occurrenceStart))) / 86400000)
	var duration = instant(end) - instant(start)
	var seriesStart = new Date(instant(series.start))
	seriesStart.setDate(seriesStart.getDate() + dayShift)
	seriesStart.setHours(newStart.getHours(), newStart.getMinutes(), 0, 0)
	if (start.date) {
		// Whole days: on a daylight saving day the length in ms isn't a multiple of 24 h.
		var seriesEnd = Shared.addDays(seriesStart, Math.round(duration / 86400000))
		return {
			start: { date: Shared.localDateString(seriesStart) },
			end: { date: Shared.localDateString(seriesEnd) },
		}
	}
	var zone = (series.start && series.start.timeZone) || timeZone
	return {
		start: { dateTime: seriesStart.toISOString(), timeZone: zone },
		end: { dateTime: new Date(seriesStart.getTime() + duration).toISOString(), timeZone: zone },
	}
}
