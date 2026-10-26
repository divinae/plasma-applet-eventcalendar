.pragma library

// Tasks (Google Tasks today, other providers later): event-shaped items with
// kind === 'tasks#task'. Raw fields kept on the item: due, status, completed, notes, position,
// parent. Days are 'YYYY-MM-DD' strings in local time.

function pad2(n) {
	return (n < 10 ? '0' : '') + n
}

// 'YYYY-MM-DD' of a Date, in local time.
function dayString(d) {
	return d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate())
}

// The day n days after day ('YYYY-MM-DD'), across month ends and daylight saving changes.
function addDays(day, n) {
	var parts = day.split('-')
	return dayString(new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]) + n))
}

function isTask(item) {
	return !!item && item.kind === 'tasks#task'
}

function isDone(item) {
	return !!item && item.status === 'completed'
}

// The due day, 'YYYY-MM-DD', or '' when undated. Google gives a date as
// 'YYYY-MM-DDT00:00:00.000Z' (the time is always dropped): the date part is the day, whatever
// the time zone.
function dueDay(item) {
	var due = item && item.due
	if (typeof due !== 'string' || !/^\d{4}-\d{2}-\d{2}/.test(due)) {
		return ''
	}
	return due.substring(0, 10)
}

// The local day a done task was completed, or ''.
function completedDay(item) {
	var completed = item && item.completed
	if (!completed) {
		return ''
	}
	var d = new Date(completed)
	return isNaN(d.getTime()) ? '' : dayString(d)
}

// Not done, and due before today (now: a Date).
function isOverdue(item, now) {
	var due = dueDay(item)
	return !isDone(item) && due !== '' && due < dayString(now)
}

// The day the task is shown on, the same in every view:
// done: its due day, else the day it was completed; undated: today; overdue: today with
// overdueOnToday, else its due day.
function placementDay(item, now, overdueOnToday) {
	var today = dayString(now)
	var due = dueDay(item)
	if (isDone(item)) {
		return due || completedDay(item) || today
	}
	if (!due) {
		return today
	}
	if (overdueOnToday && due < today) {
		return today
	}
	return due
}

// The change that checks (done) or unchecks a task. now: optional Date, for tests.
function toggleBody(done, now) {
	return {
		status: done ? 'completed' : 'needsAction',
		completed: done ? (now || new Date()).toISOString() : null,
	}
}

// Google's due value for a day ('YYYY-MM-DD'), null for '' (no due date).
function dueValue(day) {
	return day ? day + 'T00:00:00.000Z' : null
}

// A Google body with only the given changes: { title?, notes?, dueDay?: 'YYYY-MM-DD' | '' }.
function editBody(changes) {
	var body = {}
	changes = changes || {}
	if (typeof changes.title !== 'undefined') {
		body.title = changes.title
	}
	if (typeof changes.notes !== 'undefined') {
		body.notes = changes.notes
	}
	if (typeof changes.dueDay !== 'undefined') {
		body.due = dueValue(changes.dueDay)
	}
	return body
}

// The body to create a deleted task again from its undo copy (Undo.restoreCopy): title, notes,
// due and done state. The copy has no status (a server field): isCompleted / completed tell.
function restoreBody(copy) {
	var body = { title: copy.title || copy._summary || copy.summary || '' }
	if (copy.notes) {
		body.notes = copy.notes
	}
	var due = dueDay(copy)
	if (due) {
		body.due = dueValue(due)
	}
	var done = copy.status === 'completed' || !!copy.isCompleted || !!copy.completed
	body.status = done ? 'completed' : 'needsAction'
	if (done && copy.completed) {
		body.completed = copy.completed
	}
	return body
}
