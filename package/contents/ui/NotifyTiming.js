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
