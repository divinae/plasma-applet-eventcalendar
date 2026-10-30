.pragma library

.import "Shared.js" as Shared

// Events per visible day, for the month grid, and lanes for multi-day events.

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
		var days = coveredDays(eventItem)
		for (var d = 0; d < dayTimes.length; d++) {
			if (days.last < dayTimes[d]) {
				break
			}
			if (days.first <= dayTimes[d]) {
				dayEvents[d].push(eventItem)
			}
		}
	}
	for (var k = 0; k < dayEvents.length; k++) {
		dayEvents[k].sort(compareEvents)
	}
	return dayEvents
}

// First and last day (midnight timestamps) an event covers. The end is exclusive: an event
// ending at midnight doesn't cover the next day. Zero-length events stay on their start day.
function coveredDays(eventItem) {
	var start = new Date(eventItem.startDateTime).getTime()
	var lastInstant = Math.max(start, new Date(eventItem.endDateTime).getTime() - 1)
	return {
		first: Shared.startOfDay(new Date(start)).getTime(),
		last: Shared.startOfDay(new Date(lastInstant)).getTime(),
	}
}

// Lanes for events spanning several days (all-day row of the week view, bars in the month view).
// dayLists: per day (column), the events shown on it. Each event gets one bar from its first to
// its last day in the list and the lowest lane free over that range: earlier first, then longer
// first, like Google Calendar. Returns { bars: [{ eventItem, first, last, lane }], laneCount }.
function assignLanes(dayLists) {
	var byEvent = []
	for (var i = 0; i < dayLists.length; i++) {
		var list = dayLists[i]
		for (var j = 0; j < list.length; j++) {
			var found = null
			for (var k = 0; k < byEvent.length; k++) {
				if (byEvent[k].eventItem === list[j]) {
					found = byEvent[k]
					break
				}
			}
			if (found) {
				found.last = i
			} else {
				byEvent.push({ eventItem: list[j], first: i, last: i, lane: 0, order: byEvent.length })
			}
		}
	}
	byEvent.sort(function(a, b) {
		return (a.first - b.first) || ((b.last - b.first) - (a.last - a.first)) || (a.order - b.order)
	})
	var laneEnds = [] // Last day index used per lane
	for (var e = 0; e < byEvent.length; e++) {
		var bar = byEvent[e]
		var lane = 0
		while (lane < laneEnds.length && laneEnds[lane] >= bar.first) {
			lane++
		}
		laneEnds[lane] = bar.last
		bar.lane = lane
		delete bar.order
	}
	return { bars: byEvent, laneCount: laneEnds.length }
}

// Per day, how many of the bars are in lanes from shownLanes on (not shown).
function hiddenPerDay(bars, shownLanes, dayCount) {
	var hidden = []
	for (var d = 0; d < dayCount; d++) {
		hidden.push(0)
	}
	for (var h = 0; h < bars.length; h++) {
		if (bars[h].lane >= shownLanes) {
			for (var day = bars[h].first; day <= bars[h].last; day++) {
				hidden[day]++
			}
		}
	}
	return hidden
}

// assignLanes with room for maxRows rows: with more lanes than that, maxRows - 1 lanes are shown
// and the last row is for "+N". Returns { bars (shown ones), laneCount (all lanes), hiddenPerDay }.
function layoutLanes(dayLists, maxRows) {
	var lanes = assignLanes(dayLists)
	var shownLanes = lanes.laneCount > maxRows ? maxRows - 1 : lanes.laneCount
	return {
		bars: lanes.bars.filter(function(bar) { return bar.lane < shownLanes }),
		laneCount: lanes.laneCount,
		hiddenPerDay: hiddenPerDay(lanes.bars, shownLanes, dayLists.length),
	}
}

// Day view: one day's all-day events as tiles side by side, columns per row, at most maxRows rows,
// in their order; too many: the last place is a "+N" for the rest. Returns { bars, laneCount,
// hiddenCount } like layoutLanes, a bar { eventItem, first: 0, last: 0, lane, slot, slots }.
function layoutTiles(events, columns, maxRows) {
	var places = columns * maxRows
	var shown = events.length > places ? places - 1 : events.length
	var bars = []
	for (var i = 0; i < shown; i++) {
		bars.push({ eventItem: events[i], first: 0, last: 0, lane: Math.floor(i / columns), slot: i % columns, slots: columns })
	}
	return {
		bars: bars,
		laneCount: Math.ceil(Math.min(events.length, places) / columns),
		hiddenCount: events.length - shown,
	}
}

// Month grid with multi-day events as bars across the days, like Google Calendar.
// dayTimes: ascending midnight timestamps of the visible days, weekLength days per row.
// maxRows: event rows that fit in a day cell (bars and titles, including a "+N" row).
// Events covering more than one day become bars in lanes at the top of each week row;
// the others are listed in their day cell below the lanes used on that day.
// Returns {
//   bars: [{ eventItem, week, first, last, lane, firstTime, lastTime, continuesBefore, continuesAfter }]
//     (first/last: column in the week row),
//   dayEvents: per day, the single-day events (sorted like bucketByDay),
//   reservedRows: per day, the rows taken by bars at the top of the cell (highest lane used + 1),
//   hiddenSpanCount: per day, bars in lanes that don't fit,
// }
function layoutMonth(items, dayTimes, weekLength, maxRows) {
	var dayCount = dayTimes.length
	var dayEvents = []
	var spanning = []
	for (var d = 0; d < dayCount; d++) {
		dayEvents.push([])
		spanning.push([])
	}
	var sorted = items.slice().sort(compareEvents)
	for (var i = 0; i < sorted.length; i++) {
		var eventItem = sorted[i]
		if (!eventItem.startDateTime || !eventItem.endDateTime) {
			continue
		}
		var days = coveredDays(eventItem)
		var target = days.last > days.first ? spanning : dayEvents
		for (var k = 0; k < dayCount; k++) {
			if (days.last < dayTimes[k]) {
				break
			}
			if (days.first <= dayTimes[k]) {
				target[k].push(eventItem)
			}
		}
	}

	var bars = []
	var reservedRows = []
	var hiddenSpanCount = []
	for (var week = 0; week * weekLength < dayCount; week++) {
		var offset = week * weekLength
		var weekDays = Math.min(weekLength, dayCount - offset)
		var lanes = assignLanes(spanning.slice(offset, offset + weekDays))
		// Highest lane + 1 per day, with all lanes shown.
		var used = []
		for (var u = 0; u < weekDays; u++) {
			used.push(0)
		}
		for (var b = 0; b < lanes.bars.length; b++) {
			for (var c = lanes.bars[b].first; c <= lanes.bars[b].last; c++) {
				used[c] = Math.max(used[c], lanes.bars[b].lane + 1)
			}
		}
		// All lanes fit when every cell still has a row for its own events or a "+N" left
		// (or has nothing else to show). Otherwise keep the last row free on every cell.
		var shownLanes = lanes.laneCount
		for (var w = 0; w < weekDays; w++) {
			var free = maxRows - used[w]
			if (free < 0 || (free === 0 && dayEvents[offset + w].length > 0)) {
				shownLanes = Math.max(0, Math.min(lanes.laneCount, maxRows - 1))
				break
			}
		}
		var hidden = hiddenPerDay(lanes.bars, shownLanes, weekDays)
		var reserved = []
		for (var r = 0; r < weekDays; r++) {
			reserved.push(0)
		}
		for (var s = 0; s < lanes.bars.length; s++) {
			var bar = lanes.bars[s]
			if (bar.lane >= shownLanes) {
				continue
			}
			for (var col = bar.first; col <= bar.last; col++) {
				reserved[col] = Math.max(reserved[col], bar.lane + 1)
			}
			var covered = coveredDays(bar.eventItem)
			var firstTime = dayTimes[offset + bar.first]
			var lastTime = dayTimes[offset + bar.last]
			bars.push({
				eventItem: bar.eventItem,
				week: week,
				first: bar.first,
				last: bar.last,
				lane: bar.lane,
				firstTime: firstTime,
				lastTime: lastTime,
				continuesBefore: covered.first < firstTime,
				continuesAfter: covered.last > lastTime,
			})
		}
		reservedRows = reservedRows.concat(reserved)
		hiddenSpanCount = hiddenSpanCount.concat(hidden)
	}
	for (var e = 0; e < dayCount; e++) {
		dayEvents[e].sort(compareEvents)
	}
	return { bars: bars, dayEvents: dayEvents, reservedRows: reservedRows, hiddenSpanCount: hiddenSpanCount }
}
