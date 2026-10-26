.pragma library

.import "Shared.js" as Shared
.import "Tasks.js" as Tasks
.import "NotifyTiming.js" as NotifyTiming

// The morning agenda notification: once a day at the first check at or after the chosen time
// (also when the computer is turned on later that day), today's events. Pure functions, tested
// in tests/daily_agenda.test.js.

function dayKey(date) {
	return date.getFullYear() + '-' + (date.getMonth() + 1) + '-' + date.getDate()
}

// "08:00" or minutes since midnight -> minutes since midnight (480 for anything invalid).
function parseTime(value) {
	if (typeof value === 'number') {
		return isFinite(value) && value >= 0 && value < 24 * 60 ? Math.floor(value) : 480
	}
	var match = /^\s*(\d{1,2}):(\d{2})\s*$/.exec(String(value || ''))
	if (match) {
		var hours = Number(match[1])
		var minutes = Number(match[2])
		if (hours < 24 && minutes < 60) {
			return hours * 60 + minutes
		}
	}
	return 480
}

// Due when today's agenda wasn't shown yet (lastDay: dayKey of the last one) and it's that time.
function isDue(now, timeMinutes, lastDay) {
	if (String(lastDay || '') === dayKey(now)) {
		return false
	}
	return now.getHours() * 60 + now.getMinutes() >= parseTime(timeMinutes)
}

function isAllDay(eventItem) {
	return !!(eventItem.start && eventItem.start.date)
}

// Today's events: { count, items: [{ allDay, start, title }] (at most maxItems), more }.
// All-day events (covering today) first, then timed ones starting today by time. Tasks, cancelled
// and declined events are skipped; the same event in two lists is counted once.
function summarize(events, now, maxItems) {
	var dayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate())
	var dayEnd = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1)
	var seen = {}
	var allDay = []
	var timed = []
	;(events || []).forEach(function(eventItem) {
		if (!eventItem || eventItem.kind === 'tasks#task' || eventItem.status === 'cancelled') {
			return
		}
		if (Shared.myResponse(eventItem) === 'declined') {
			return
		}
		var start = new Date(eventItem.startDateTime)
		var end = new Date(eventItem.endDateTime)
		if (!isFinite(start.getTime())) {
			return
		}
		var key = String(eventItem.id || eventItem.summary || '') + '|' + start.getTime()
		if (seen[key]) {
			return
		}
		if (isAllDay(eventItem)) {
			if (!(start < dayEnd && (isFinite(end.getTime()) ? end > dayStart : start >= dayStart))) {
				return
			}
			seen[key] = true
			allDay.push({ allDay: true, start: start, title: String(eventItem.summary || '') })
		} else {
			if (start < dayStart || start >= dayEnd) {
				return
			}
			seen[key] = true
			timed.push({ allDay: false, start: start, title: String(eventItem.summary || '') })
		}
	})
	allDay.sort(function(a, b) { return a.start - b.start })
	timed.sort(function(a, b) { return a.start - b.start })
	var list = allDay.concat(timed)
	var limit = maxItems > 0 ? maxItems : 5
	var shown = list.length <= limit ? list : list.slice(0, limit)
	return {
		count: list.length,
		items: shown,
		more: list.length - shown.length,
	}
}

//--- Tasks

// Open tasks due today and overdue ones: { count, today, overdue, titles (at most maxItems),
// more }. withAlerts false: without today's tasks that have reminders of their own (a due time or
// reminders, see NotifyTiming.taskHasAlert), for the morning summary. Overdue first (oldest
// first), then today's; higher priority first within a day. A task in two lists counted once.
function summarizeTasks(items, now, maxItems, withAlerts) {
	var today = Tasks.dayString(now)
	var seen = {}
	var list = []
	;(items || []).forEach(function(item) {
		if (!Tasks.isTask(item) || Tasks.isDone(item)) {
			return
		}
		var day = Tasks.dueDay(item)
		if (!day || day > today) {
			return
		}
		var overdue = day < today
		if (!overdue && !withAlerts && NotifyTiming.taskHasAlert(item)) {
			return
		}
		var key = String(item.calendarId || '') + '|' + String(item.id || item.summary || '')
		if (seen[key]) {
			return
		}
		seen[key] = true
		list.push({ day: day, overdue: overdue, priority: Tasks.priorityOf(item), title: String(item.summary || item.title || '') })
	})
	list.sort(function(a, b) {
		return a.day < b.day ? -1 : a.day > b.day ? 1 : b.priority - a.priority
	})
	var overdueCount = list.filter(function(t) { return t.overdue }).length
	var limit = maxItems > 0 ? maxItems : 3
	return {
		count: list.length,
		today: list.length - overdueCount,
		overdue: overdueCount,
		titles: list.slice(0, limit).map(function(t) { return t.title }),
		more: Math.max(0, list.length - limit),
	}
}

// How many open tasks are due before today (the panel tooltip), each task once.
function overdueTaskCount(items, now) {
	var seen = {}
	var count = 0
	;(items || []).forEach(function(item) {
		if (!Tasks.isTask(item) || !Tasks.isOverdue(item, now)) {
			return
		}
		var key = String(item.calendarId || '') + '|' + String(item.id || item.summary || '')
		if (!seen[key]) {
			seen[key] = true
			count++
		}
	})
	return count
}
