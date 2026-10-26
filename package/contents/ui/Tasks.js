.pragma library

// Tasks (Google Tasks, TickTick): event-shaped items with
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

// The items without tasks: the Month, Week and Day views show events only (tasks have their own
// view, the agenda and the tooltips keep them).
function withoutTasks(items) {
	return (items || []).filter(function(item) { return !isTask(item) })
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

//--- TickTick (https://developer.ticktick.com/docs/openapi.md)
// TickTick tasks are shown with the Google fields above (due, status, completed, notes), made
// from TickTick's own (dueDate / startDate, isAllDay, timeZone, status 0 / 2, content) by
// fromTickTick, and changes in Google shape go back as TickTick fields with toTickTick.

// UTC ms of a TickTick date ('yyyy-MM-ddTHH:mm:ss+0000', also 'Z', '+00:00', milliseconds), or NaN.
function parseTickTickDate(text) {
	var m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2}))?(?:\.(\d+))?(Z|[+-]\d{2}:?\d{2})?$/.exec(String(text || ''))
	if (!m) {
		return NaN
	}
	var ms = Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]), Number(m[4]), Number(m[5]), Number(m[6] || 0),
		m[7] ? Number((m[7] + '00').substring(0, 3)) : 0)
	var zone = m[8] || 'Z'
	if (zone !== 'Z') {
		var sign = zone.charAt(0) === '-' ? -1 : 1
		var digits = zone.substring(1).replace(':', '')
		ms -= sign * (Number(digits.substring(0, 2)) * 60 + Number(digits.substring(2, 4))) * 60000
	}
	return ms
}

// TickTick's format of an instant (UTC ms): 'yyyy-MM-ddTHH:mm:ss+0000'.
function formatTickTickDate(ms) {
	var d = new Date(ms)
	return d.getUTCFullYear() + '-' + pad2(d.getUTCMonth() + 1) + '-' + pad2(d.getUTCDate())
		+ 'T' + pad2(d.getUTCHours()) + ':' + pad2(d.getUTCMinutes()) + ':' + pad2(d.getUTCSeconds()) + '+0000'
}

// The due day and time of a TickTick task: { day: 'YYYY-MM-DD' | '', time: 'HH:mm' | '' }.
// All-day: the day in the task's time zone (wallClock(zone, utcMs) -> { year, month (0-11), day }
// or null, eg: TimeZone.wallClock; optional), else in local time; no time. Timed: local day and time.
function tickTickDue(task, wallClock) {
	var ms = parseTickTickDate(task && (task.dueDate || task.startDate))
	if (isNaN(ms)) {
		return { day: '', time: '' }
	}
	if (task.isAllDay !== false) {
		var w = task.timeZone && wallClock ? wallClock(task.timeZone, ms) : null
		if (w) {
			return { day: w.year + '-' + pad2(w.month + 1) + '-' + pad2(w.day), time: '' }
		}
		return { day: dayString(new Date(ms)), time: '' }
	}
	var d = new Date(ms)
	return { day: dayString(d), time: pad2(d.getHours()) + ':' + pad2(d.getMinutes()) }
}

// The Google-shaped fields of a TickTick task: { title, notes, due, dueTime, status, completed },
// due null when undated, completed null when not done. wallClock: see tickTickDue.
function fromTickTick(task, wallClock) {
	var due = tickTickDue(task, wallClock)
	var done = !!task && task.status === 2
	var completedMs = parseTickTickDate(task && task.completedTime)
	return {
		title: (task && task.title) || '',
		notes: (task && task.content) || '',
		due: dueValue(due.day),
		dueTime: due.time,
		status: done ? 'completed' : 'needsAction',
		completed: done && !isNaN(completedMs) ? new Date(completedMs).toISOString() : null,
	}
}

// The TickTick fields for a Google-shaped body (editBody, toggleBody, restoreBody): only what it
// changes. task: the task's TickTick fields (dueDate, isAllDay, timeZone), or null for a new one.
// A timed task keeps its time on another day; other due days are all-day, at the start of the
// day in the task's time zone (toUtc(zone, year, month (0-11), day, h, m, s) -> UTC ms or null,
// eg: TimeZone.toUtc; optional), else in local time. A due of null clears the dates.
function toTickTick(body, task, toUtc) {
	var out = {}
	body = body || {}
	if (typeof body.title !== 'undefined') {
		out.title = body.title || ''
	}
	if (typeof body.notes !== 'undefined') {
		out.content = body.notes || ''
	}
	if (typeof body.due !== 'undefined') {
		var day = dueDay(body)
		if (!day) {
			out.dueDate = null
			out.startDate = null
		} else {
			var parts = day.split('-')
			var y = Number(parts[0]), mo = Number(parts[1]) - 1, d = Number(parts[2])
			var current = parseTickTickDate(task && (task.dueDate || task.startDate))
			var ms = null
			if (task && task.isAllDay === false && !isNaN(current)) {
				var time = new Date(current)
				ms = new Date(y, mo, d, time.getHours(), time.getMinutes()).getTime()
				out.isAllDay = false
			} else {
				if (task && task.timeZone && toUtc) {
					ms = toUtc(task.timeZone, y, mo, d, 0, 0, 0)
				}
				if (ms === null || typeof ms === 'undefined' || isNaN(ms)) {
					ms = new Date(y, mo, d).getTime()
				}
				out.isAllDay = true
			}
			out.dueDate = formatTickTickDate(ms)
			out.startDate = out.dueDate
		}
	}
	if (typeof body.status !== 'undefined') {
		out.status = body.status === 'completed' ? 2 : 0
		var completedMs = parseTickTickDate(body.completed)
		if (out.status === 2 && !isNaN(completedMs)) {
			out.completedTime = formatTickTickDate(completedMs)
		}
	}
	return out
}

//--- Tasks view: task lists as sections

// Google's order within a list (position strings), tasks without one first, then by title.
function comparePosition(a, b) {
	var aHas = typeof a.position === 'string' && a.position !== ''
	var bHas = typeof b.position === 'string' && b.position !== ''
	if (aHas && bHas && a.position !== b.position) {
		return a.position < b.position ? -1 : 1
	}
	if (aHas !== bHas) {
		return aHas ? 1 : -1
	}
	var at = String(a.summary || a.title || '').toLowerCase()
	var bt = String(b.summary || b.title || '').toLowerCase()
	return at < bt ? -1 : at > bt ? 1 : 0
}

// Open tasks: by due day (overdue ones are the earliest, so first), undated last; the same due day
// in the list's order (position). A sorted copy.
function sortOpenTasks(tasks) {
	return (tasks || []).slice().sort(function(a, b) {
		var da = dueDay(a)
		var db = dueDay(b)
		if (da !== db) {
			if (!da || !db) {
				return da ? -1 : 1
			}
			return da < db ? -1 : 1
		}
		return comparePosition(a, b)
	})
}

// Done tasks: the most recently completed first. A sorted copy.
function sortDoneTasks(tasks) {
	return (tasks || []).slice().sort(function(a, b) {
		var ca = a.completed ? new Date(a.completed).getTime() || 0 : 0
		var cb = b.completed ? new Date(b.completed).getTime() || 0 : 0
		return ca !== cb ? cb - ca : comparePosition(a, b)
	})
}

// When a task is due, for its label: { kind: 'none' | 'overdue' | 'today' | 'tomorrow' | 'date', day }.
function dueInfo(item, now) {
	var day = dueDay(item)
	if (!day) {
		return { kind: 'none', day: '' }
	}
	var today = dayString(now)
	var kind = day === today ? 'today'
		: day === addDays(today, 1) ? 'tomorrow'
		: day < today && !isDone(item) ? 'overdue'
		: 'date'
	return { kind: kind, day: day }
}

// The first non-empty line of a task's notes, trimmed.
function firstLine(text) {
	var lines = String(text || '').split(/\r?\n/)
	for (var i = 0; i < lines.length; i++) {
		var line = lines[i].trim()
		if (line) {
			return line
		}
	}
	return ''
}

// The rows of the Tasks view, top to bottom.
// lists: [{ id, name, color, group }] (group: the account; lists of one group are kept together,
// in the order the groups first appear). itemsByList: { listId: [items] } (non-tasks and
// repeated ids are skipped). Rows:
//   { type: 'group', key, text }: only when the lists are from more than one account
//   { type: 'list', key, list, openCount, doneCount }
//   { type: 'task', key, item, list, done }: open tasks (sortOpenTasks), then with showCompleted
//     the done ones (sortDoneTasks)
//   { type: 'empty', key, list }: the list has no open task
function taskRows(lists, itemsByList, showCompleted) {
	var groups = []
	var byGroup = {}
	;(lists || []).forEach(function(list) {
		var group = String(list.group || '')
		if (!Object.prototype.hasOwnProperty.call(byGroup, group)) {
			byGroup[group] = []
			groups.push(group)
		}
		byGroup[group].push(list)
	})
	var showGroups = groups.length > 1
	var rows = []
	groups.forEach(function(group) {
		if (showGroups) {
			rows.push({ type: 'group', key: 'group:' + group, text: group })
		}
		byGroup[group].forEach(function(list) {
			var open = []
			var done = []
			var seen = {}
			var items = (itemsByList && itemsByList[list.id]) || []
			for (var i = 0; i < items.length; i++) {
				var item = items[i]
				if (!isTask(item) || seen[item.id]) {
					continue
				}
				seen[item.id] = true
				;(isDone(item) ? done : open).push(item)
			}
			rows.push({ type: 'list', key: 'list:' + list.id, list: list, openCount: open.length, doneCount: done.length })
			sortOpenTasks(open).forEach(function(item) {
				rows.push({ type: 'task', key: 'task:' + list.id + ':' + item.id, item: item, list: list, done: false })
			})
			if (!open.length) {
				rows.push({ type: 'empty', key: 'empty:' + list.id, list: list })
			}
			if (showCompleted) {
				sortDoneTasks(done).forEach(function(item) {
					rows.push({ type: 'task', key: 'task:' + list.id + ':' + item.id, item: item, list: list, done: true })
				})
			}
		})
	})
	return rows
}
