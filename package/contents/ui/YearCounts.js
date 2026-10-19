.pragma library

// Year view: events per day, month grids and the range to fetch.

// 'yyyy-m-d' key (month 1-12) of a local date.
function dayKey(year, month, day) {
	return year + '-' + month + '-' + day
}

// { dayKey: number of events } for the days of year. Multi-day events count on every day they
// cover (the end is exclusive: an event ending at midnight doesn't cover the next day).
function countsByDay(items, year) {
	var counts = {}
	var yearStart = new Date(year, 0, 1).getTime()
	var yearEnd = new Date(year + 1, 0, 1).getTime()
	for (var i = 0; i < (items ? items.length : 0); i++) {
		var item = items[i]
		if (!item || !item.startDateTime) {
			continue
		}
		var start = new Date(item.startDateTime).getTime()
		var end = item.endDateTime ? new Date(item.endDateTime).getTime() : start
		var lastInstant = Math.max(start, end - 1)
		if (isNaN(start) || isNaN(lastInstant) || lastInstant < yearStart || start >= yearEnd) {
			continue
		}
		var s = new Date(Math.max(start, yearStart))
		var day = new Date(s.getFullYear(), s.getMonth(), s.getDate())
		var last = Math.min(lastInstant, yearEnd - 1)
		while (day.getTime() <= last) {
			var key = dayKey(day.getFullYear(), day.getMonth() + 1, day.getDate())
			counts[key] = (counts[key] || 0) + 1
			day.setDate(day.getDate() + 1)
		}
	}
	return counts
}

// Tint level for a count: 0 none, 1 one event, 2 two or three, 3 four or more.
function level(count) {
	if (!count) {
		return 0
	}
	return count === 1 ? 1 : count <= 3 ? 2 : 3
}

// The 42 cells (6 weeks) of a month grid starting on firstDayOfWeek (0 = Sunday): the day number
// for days of the month, 0 for the empty cells around it.
function monthCells(year, month, firstDayOfWeek) {
	var first = new Date(year, month, 1).getDay()
	var lead = ((first - (firstDayOfWeek || 0)) % 7 + 7) % 7
	var days = new Date(year, month + 1, 0).getDate()
	var cells = []
	for (var i = 0; i < 42; i++) {
		var d = i - lead + 1
		cells.push(d >= 1 && d <= days ? d : 0)
	}
	return cells
}

// Range to fetch for the year view: the whole year, and the agenda days after today when the
// year is the current one (upcoming events, notifications). { min, max } (max exclusive).
function fetchRange(year, today, nextDays) {
	var min = new Date(year, 0, 1)
	var max = new Date(year + 1, 0, 1)
	if (today && today.getFullYear() === year && nextDays > 0) {
		var agendaMax = new Date(today.getFullYear(), today.getMonth(), today.getDate() + nextDays)
		if (agendaMax > max) {
			max = agendaMax
		}
	}
	return { min: min, max: max }
}
