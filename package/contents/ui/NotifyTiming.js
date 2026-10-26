.pragma library

// When event notifications are due. Checks run about once a minute, but a check can come late or a
// minute can be skipped (a busy or restarting plasmashell, the time engine firing just before the
// full minute), so each check covers every minute since the previous one instead of only the
// current one. Keys remember what was sent, so nothing is sent twice.

var MINUTE = 60000

function floorMinute(ms) {
	return Math.floor(ms / MINUTE) * MINUTE
}

// The minutes (from, to] a check covers: since the last check, at most maxCatchUpMs back (after a
// long sleep old reminders are skipped); the first check covers the current minute only.
function checkWindow(lastCheckMs, nowMs, maxCatchUpMs) {
	var to = floorMinute(nowMs)
	var from = to - MINUTE
	if (lastCheckMs !== null && lastCheckMs !== undefined && isFinite(lastCheckMs)) {
		var last = floorMinute(lastCheckMs)
		if (last < to) {
			from = Math.max(last, to - maxCatchUpMs)
		} else {
			from = to // Same minute as the last check: nothing new
		}
	}
	return { from: from, to: to }
}

function inWindow(timeMs, win) {
	var minute = floorMinute(timeMs)
	return minute > win.from && minute <= win.to
}

// What to send for one event in this window: [{ kind: 'start' | 'reminder', minutes, key }].
// reminderMinutes: minutes before the start; 0 and negative ones are covered by 'start'.
function dueFor(eventItem, reminderMinutes, win, nowMs) {
	var due = []
	var start = new Date(eventItem.startDateTime).getTime()
	if (!isFinite(start)) {
		return due
	}
	var id = String(eventItem.calendarId || '') + '|' + String(eventItem.id || eventItem.summary || '') + '|' + start
	if (inWindow(start, win)) {
		due.push({ kind: 'start', minutes: 0, key: id + '|start' })
	}
	var list = reminderMinutes || []
	for (var i = 0; i < list.length; i++) {
		var minutes = Number(list[i])
		if (!(minutes > 0) || start <= nowMs) {
			continue
		}
		if (inWindow(start - minutes * MINUTE, win)) {
			due.push({ kind: 'reminder', minutes: minutes, key: id + '|' + minutes })
		}
	}
	return due
}

// Drops sent keys older than a day (key -> time sent).
function pruneSent(sent, nowMs) {
	var kept = {}
	for (var key in sent) {
		if (nowMs - sent[key] < 24 * 60 * MINUTE) {
			kept[key] = sent[key]
		}
	}
	return kept
}

//--- Tasks (kind 'tasks#task', see Tasks.js): reminders at the due moment minus each reminder.

// The due moment of a task in local time (ms): its due day at dueTime ('HH:mm'), or 00:00 for an
// all-day task; NaN when undated.
function taskDueMs(task) {
	var m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String((task && task.due) || ''))
	if (!m) {
		return NaN
	}
	var t = /^(\d{1,2}):(\d{2})$/.exec(String((task && task.dueTime) || ''))
	return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]), t ? Number(t[1]) : 0, t ? Number(t[2]) : 0).getTime()
}

// A task's reminders as whole minutes (numbers only, no repeats).
function taskReminders(task) {
	var list = task && task.reminders
	var out = []
	if (!list || typeof list === 'string' || typeof list.length !== 'number') {
		return out
	}
	for (var i = 0; i < list.length; i++) {
		var n = Number(list[i])
		if (list[i] !== null && list[i] !== '' && isFinite(n) && out.indexOf(Math.round(n)) < 0) {
			out.push(Math.round(n))
		}
	}
	return out
}

// Whether a task gets reminders of its own: open, with a due day and a due time or reminders
// (TickTick). The others (Google, all-day without reminders) are in the morning summary.
function taskHasAlert(task) {
	if (!task || task.status === 'completed' || !isFinite(taskDueMs(task))) {
		return false
	}
	return !!task.dueTime || taskReminders(task).length > 0
}

// When a task's reminders come: [{ minutes, at (ms) }]: each reminder (minutes before the due
// moment; negative = after it, eg: -540 on an all-day task = 09:00 that day), else the due time.
// All-day tasks count in wall-clock time from their day's 00:00, so -540 stays 09:00 on a day the
// clocks change (DST); timed ones in real minutes before the due moment.
function taskAlertTimes(task) {
	if (!taskHasAlert(task)) {
		return []
	}
	var due = taskDueMs(task)
	var allDay = !/^\d{1,2}:\d{2}$/.test(String((task && task.dueTime) || ''))
	var day = new Date(due)
	var reminders = taskReminders(task)
	if (!reminders.length) {
		reminders = [0]
	}
	return reminders.map(function(minutes) {
		var at = allDay
			? new Date(day.getFullYear(), day.getMonth(), day.getDate(), 0, -minutes).getTime()
			: due - minutes * MINUTE
		return { minutes: minutes, at: at }
	})
}

// The task reminders to send in this window: [{ kind: 'task', minutes, key }].
function taskDueFor(task, win) {
	var due = []
	var times = taskAlertTimes(task)
	var id = 'task|' + String((task && task.calendarId) || '') + '|' + String((task && (task.id || task.summary)) || '') + '|' + taskDueMs(task)
	for (var i = 0; i < times.length; i++) {
		if (inWindow(times[i].at, win)) {
			due.push({ kind: 'task', minutes: times[i].minutes, key: id + '|' + times[i].minutes })
		}
	}
	return due
}

// For a task reminder's text: { state: 'overdue' | 'today' | 'tomorrow' | 'date' | 'none', timed,
// due (ms) }. Overdue: a timed task past its time, an all-day one past its day.
function taskDueState(task, nowMs) {
	var due = taskDueMs(task)
	if (!isFinite(due)) {
		return { state: 'none', timed: false, due: NaN }
	}
	var timed = /^\d{1,2}:\d{2}$/.test(String((task && task.dueTime) || ''))
	var now = new Date(nowMs)
	var d = new Date(due)
	var dayStart = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
	var dayEnd = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1).getTime()
	var today = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
	var tomorrow = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1).getTime()
	var state = (timed ? floorMinute(due) < floorMinute(nowMs) : dayEnd <= nowMs) ? 'overdue'
		: dayStart === today ? 'today'
		: dayStart === tomorrow ? 'tomorrow'
		: 'date'
	return { state: state, timed: timed, due: due }
}
