.pragma library

// Tasks (Google Tasks, TickTick): event-shaped items with
// kind === 'tasks#task'. Raw fields kept on the item: due, status, completed, notes, position,
// parent. Days are 'YYYY-MM-DD' strings in local time.
// Provider-neutral fields (both managers set them; Google has only parentId):
//   dueTime: 'HH:mm' or '' (all-day / undated)
//   reminders: [minutes before due] (negative: after it, eg: 9:00 on an all-day task's day)
//   priority: 0 none, 1 low, 3 medium, 5 high (see priorityOf)
//   repeatRule: an RRULE string ('RRULE:FREQ=DAILY;INTERVAL=1') or ''
//   parentId: the parent task's id (Google subtasks) or ''
//   subtasks: checklist items [{ id, title, done }] (TickTick)

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

//--- Priority, reminders, subtasks

var PRIORITY_NONE = 0
var PRIORITY_LOW = 1
var PRIORITY_MEDIUM = 3
var PRIORITY_HIGH = 5

// The priority of an item (or a raw value): 0, 1, 3 or 5; anything else is rounded down to one
// of them (2 -> 1, 4 -> 3, over 5 -> 5), not a number -> 0.
function priorityOf(itemOrValue) {
	var value = itemOrValue !== null && typeof itemOrValue === 'object' ? itemOrValue.priority : itemOrValue
	var n = Number(value)
	if (!isFinite(n) || n < 1) {
		return PRIORITY_NONE
	}
	return n >= 5 ? PRIORITY_HIGH : n >= 3 ? PRIORITY_MEDIUM : PRIORITY_LOW
}

// 'HH:mm' when text is a time of day, else ''.
function cleanTime(text) {
	var m = /^(\d{1,2}):(\d{2})$/.exec(String(text || ''))
	if (!m || Number(m[1]) > 23 || Number(m[2]) > 59) {
		return ''
	}
	return pad2(Number(m[1])) + ':' + m[2]
}

// Reminders as whole minutes before due (numbers only), in the given order, repeats left out.
function cleanReminders(list) {
	var out = []
	var arr = list && typeof list.length === 'number' && typeof list !== 'string' ? list : []
	for (var i = 0; i < arr.length; i++) {
		var n = Number(arr[i])
		if (arr[i] !== null && arr[i] !== '' && isFinite(n) && out.indexOf(Math.round(n)) < 0) {
			out.push(Math.round(n))
		}
	}
	return out
}

// Subtasks as [{ id, title, done }] (id '' for a new one).
function cleanSubtasks(list) {
	var arr = list && typeof list.length === 'number' && typeof list !== 'string' ? list : []
	var out = []
	for (var i = 0; i < arr.length; i++) {
		var s = arr[i]
		if (!s || typeof s !== 'object') {
			continue
		}
		out.push({ id: String(s.id || ''), title: String(s.title || ''), done: !!s.done })
	}
	return out
}

// An RRULE string, or '' (anything not text).
function cleanRepeatRule(rule) {
	return typeof rule === 'string' ? rule.trim() : ''
}

// The priority's name: 'high', 'medium', 'low' or 'none' (the check's color, like TickTick).
function priorityKey(itemOrValue) {
	switch (priorityOf(itemOrValue)) {
		case PRIORITY_HIGH: return 'high'
		case PRIORITY_MEDIUM: return 'medium'
		case PRIORITY_LOW: return 'low'
	}
	return 'none'
}

// The time a task is due ('HH:mm'), '' when all-day or undated.
function dueTimeOf(item) {
	return dueDay(item) ? cleanTime(item && item.dueTime) : ''
}

// A task's checklist progress: { done, total } (TickTick's checklist items).
function subtaskProgress(item) {
	var list = cleanSubtasks(item && item.subtasks)
	return {
		done: list.filter(function(s) { return s.done }).length,
		total: list.length,
	}
}

// What the editor can set on a task of a provider ('TickTick', 'GoogleTasks', …): { dueTime,
// priority, repeat, reminders, subtasks }. Google Tasks has none of them.
function capabilities(provider) {
	var all = provider === 'TickTick'
	return { dueTime: all, priority: all, repeat: all, reminders: all, subtasks: all }
}

// The tasks of one list in subtask order: each task followed by its subtasks (parentId, or
// Google's parent), at any depth. Rows: [{ item, depth }] (0 for a top level task). Siblings keep
// the order of items; a task whose parent isn't in items (or a loop) is a top level one.
function subtaskTree(items) {
	items = items || []
	var byId = {}
	for (var i = 0; i < items.length; i++) {
		if (items[i] && items[i].id) {
			byId[items[i].id] = items[i]
		}
	}
	var parentOf = function(item) {
		var parent = item && (item.parentId || item.parent)
		return parent && byId[parent] && parent !== item.id ? String(parent) : ''
	}
	// Top level: no known parent, or a loop of parents.
	var isRoot = function(item) {
		var seen = {}
		var current = item
		while (current) {
			if (seen[current.id]) {
				return current === item // In a loop: only the item that closes it is a root
			}
			seen[current.id] = true
			var parent = parentOf(current)
			if (!parent) {
				return current === item
			}
			current = byId[parent]
		}
		return true
	}
	var children = {}
	for (var j = 0; j < items.length; j++) {
		var parent = parentOf(items[j])
		if (parent) {
			(children[parent] = children[parent] || []).push(items[j])
		}
	}
	var rows = []
	var placed = {}
	var place = function(item, depth) {
		if (!item || placed[item.id]) {
			return
		}
		placed[item.id] = true
		rows.push({ item: item, depth: depth })
		var kids = children[item.id] || []
		for (var k = 0; k < kids.length; k++) {
			place(kids[k], depth + 1)
		}
	}
	for (var r = 0; r < items.length; r++) {
		if (!items[r]) {
			continue
		}
		if (!items[r].id) {
			rows.push({ item: items[r], depth: 0 })
		} else if (isRoot(items[r])) {
			place(items[r], 0)
		}
	}
	// A loop with no task leading into it from outside: its tasks are top level.
	for (var q = 0; q < items.length; q++) {
		if (items[q] && items[q].id && !placed[items[q].id]) {
			place(items[q], 0)
		}
	}
	return rows
}

// A body with only the given changes: { title?, notes?, dueDay?: 'YYYY-MM-DD' | '', dueTime?:
// 'HH:mm' | '', priority?, repeatRule?, reminders?: [minutes], subtasks?: [{ id, title, done }] }.
// Google shape (title, notes, due); the other fields are kept by name for TickTick
// (toTickTick) and dropped for Google (googleBody).
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
	if (typeof changes.dueTime !== 'undefined') {
		body.dueTime = cleanTime(changes.dueTime)
	}
	if (typeof changes.priority !== 'undefined') {
		body.priority = priorityOf(changes.priority)
	}
	if (typeof changes.repeatRule !== 'undefined') {
		body.repeatRule = cleanRepeatRule(changes.repeatRule)
	}
	if (typeof changes.reminders !== 'undefined') {
		body.reminders = cleanReminders(changes.reminders)
	}
	if (typeof changes.subtasks !== 'undefined') {
		body.subtasks = cleanSubtasks(changes.subtasks)
	}
	return body
}

// The editor's changes to item (null: a new task), for editBody. form: { title, notes, dueDay
// ('YYYY-MM-DD' | ''), dueTime ('HH:mm' | ''), priority, repeatRule (left out: not changed),
// reminders: [minutes], subtasks: [{ id, title, done }] }; caps (capabilities): only what the
// task's provider has. A new task: its title, due day, and what isn't empty; an existing one:
// only what differs. No time or repeat without a due day; checklist items without a title are
// left out.
function editorChanges(item, form, caps) {
	caps = caps || {}
	form = form || {}
	var isNew = !item
	var out = {}
	var title = String(form.title || '')
	if (isNew || title !== String(item.summary || item.title || '')) {
		out.title = title
	}
	var notes = String(form.notes || '')
	if (isNew ? !!notes.trim() : notes !== String(item.notes || '')) {
		out.notes = notes
	}
	var day = form.dueDay || ''
	if (isNew || day !== dueDay(item)) {
		out.dueDay = day
	}
	if (caps.dueTime) {
		var time = day ? cleanTime(form.dueTime) : ''
		if (isNew ? !!time : time !== dueTimeOf(item)) {
			out.dueTime = time
		}
	}
	if (caps.priority) {
		var priority = priorityOf(form.priority)
		if (isNew ? priority > 0 : priority !== priorityOf(item)) {
			out.priority = priority
		}
	}
	if (caps.repeat && typeof form.repeatRule === 'string') {
		var rule = day ? cleanRepeatRule(form.repeatRule) : ''
		if (isNew ? !!rule : rule !== cleanRepeatRule(item.repeatRule)) {
			out.repeatRule = rule
		}
	}
	if (caps.reminders) {
		var reminders = cleanReminders(form.reminders)
		if (isNew ? reminders.length > 0 : JSON.stringify(reminders) !== JSON.stringify(cleanReminders(item.reminders))) {
			out.reminders = reminders
		}
	}
	if (caps.subtasks) {
		var subtasks = cleanSubtasks(form.subtasks).filter(function(s) {
			return !!s.title.trim()
		}).map(function(s) {
			return { id: s.id, title: s.title.trim(), done: s.done }
		})
		if (isNew ? subtasks.length > 0 : JSON.stringify(subtasks) !== JSON.stringify(cleanSubtasks(item.subtasks))) {
			out.subtasks = subtasks
		}
	}
	return out
}

// The fields Google Tasks doesn't have (no time, priority, repeat, reminders or checklist).
var NOT_GOOGLE_FIELDS = ['dueTime', 'priority', 'repeatRule', 'reminders', 'subtasks']

// A copy of body (editBody, restoreBody, toggleBody) without NOT_GOOGLE_FIELDS: what goes to Google.
function googleBody(body) {
	var out = {}
	for (var key in (body || {})) {
		if (NOT_GOOGLE_FIELDS.indexOf(key) < 0) {
			out[key] = body[key]
		}
	}
	return out
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
	// TickTick's own fields, when the task had them (googleBody drops them for Google).
	if (due && cleanTime(copy.dueTime)) {
		body.dueTime = cleanTime(copy.dueTime)
	}
	if (priorityOf(copy)) {
		body.priority = priorityOf(copy)
	}
	if (cleanRepeatRule(copy.repeatRule)) {
		body.repeatRule = cleanRepeatRule(copy.repeatRule)
	}
	if (cleanReminders(copy.reminders).length) {
		body.reminders = cleanReminders(copy.reminders)
	}
	if (cleanSubtasks(copy.subtasks).length) {
		body.subtasks = cleanSubtasks(copy.subtasks).map(function(s) {
			return { id: '', title: s.title, done: s.done } // New items: the old ids are gone
		})
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

// Minutes before due of a TickTick reminder ('TRIGGER:-PT15M' 15 before, 'TRIGGER:PT0S' at due,
// 'TRIGGER:P0DT9H0M0S' 9 hours after: 9:00 on an all-day task's day), or null.
function parseTickTickReminder(text) {
	var m = /^(?:TRIGGER:)?([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$/.exec(String(text || '').trim())
	if (!m || !/\d/.test(String(text))) {
		return null
	}
	var minutes = Number(m[2] || 0) * 7 * 1440 + Number(m[3] || 0) * 1440 + Number(m[4] || 0) * 60
		+ Number(m[5] || 0) + Math.floor(Number(m[6] || 0) / 60)
	return m[1] === '-' || minutes === 0 ? minutes : -minutes
}

// TickTick's reminder for minutes before due (see parseTickTickReminder).
function formatTickTickReminder(minutesBefore) {
	var n = Math.round(Number(minutesBefore) || 0)
	if (n === 0) {
		return 'TRIGGER:PT0S'
	}
	var total = Math.abs(n)
	var days = Math.floor(total / 1440)
	var hours = Math.floor((total % 1440) / 60)
	var minutes = total % 60
	var text = 'P' + (days ? days + 'D' : '')
	if (hours || minutes) {
		text += 'T' + (hours ? hours + 'H' : '') + (minutes ? minutes + 'M' : '')
	}
	return 'TRIGGER:' + (n > 0 ? '-' : '') + text
}

// A TickTick checklist item done: status 1 (also 2, like a task).
function tickTickItemDone(item) {
	return !!item && (item.status === 1 || item.status === 2)
}

// The Google-shaped fields of a TickTick task: { title, notes, due, dueTime, status, completed,
// reminders, priority, repeatRule, parentId, subtasks }, due null when undated, completed null
// when not done. wallClock: see tickTickDue.
function fromTickTick(task, wallClock) {
	var due = tickTickDue(task, wallClock)
	var done = !!task && task.status === 2
	var completedMs = parseTickTickDate(task && task.completedTime)
	var reminders = []
	var rawReminders = task && Array.isArray(task.reminders) ? task.reminders : []
	for (var i = 0; i < rawReminders.length; i++) {
		var minutes = parseTickTickReminder(rawReminders[i])
		if (minutes !== null && reminders.indexOf(minutes) < 0) {
			reminders.push(minutes)
		}
	}
	var rawItems = task && Array.isArray(task.items) ? task.items.slice() : []
	rawItems.sort(function(a, b) {
		return (Number(a && a.sortOrder) || 0) - (Number(b && b.sortOrder) || 0)
	})
	return {
		title: (task && task.title) || '',
		notes: (task && task.content) || '',
		due: dueValue(due.day),
		dueTime: due.time,
		status: done ? 'completed' : 'needsAction',
		completed: done && !isNaN(completedMs) ? new Date(completedMs).toISOString() : null,
		reminders: reminders,
		priority: priorityOf(task && task.priority),
		repeatRule: cleanRepeatRule(task && task.repeatFlag),
		parentId: task && task.parentId ? String(task.parentId) : '',
		subtasks: rawItems.filter(function(item) { return !!item }).map(function(item) {
			return { id: String(item.id || ''), title: String(item.title || ''), done: tickTickItemDone(item) }
		}),
	}
}

// The day ('YYYY-MM-DD') of a TickTick instant (UTC ms) as tickTickDue counts it: all-day in the
// task's zone (wallClock, optional) else local time; timed in local time.
function tickTickDayOf(ms, task, wallClock) {
	if (task && task.isAllDay !== false && task.timeZone && wallClock) {
		var w = wallClock(task.timeZone, ms)
		if (w) {
			return w.year + '-' + pad2(w.month + 1) + '-' + pad2(w.day)
		}
	}
	return dayString(new Date(ms))
}

// Days from day a to day b ('YYYY-MM-DD').
function daysBetween(a, b) {
	var pa = a.split('-'), pb = b.split('-')
	return Math.round((Date.UTC(Number(pb[0]), Number(pb[1]) - 1, Number(pb[2]))
		- Date.UTC(Number(pa[0]), Number(pa[1]) - 1, Number(pa[2]))) / 86400000)
}

// The new start (UTC ms) of a task that spans time (a startDate before its dueDate) when its due
// moment moves to dueMs on day ('YYYY-MM-DD'), so it keeps its length; null when it had no span.
// Timed to timed: the same length in time. Otherwise whole days: all-day it starts that many days
// before at the start of the day (in the task's zone, see toTickTick), timed at the due's time.
function tickTickShiftedStart(task, day, dueMs, allDay, toUtc, wallClock) {
	var oldDue = parseTickTickDate(task && task.dueDate)
	var oldStart = parseTickTickDate(task && task.startDate)
	if (isNaN(oldDue) || isNaN(oldStart) || oldStart >= oldDue) {
		return null
	}
	if (!allDay && task.isAllDay === false) {
		return dueMs - (oldDue - oldStart)
	}
	var days = daysBetween(tickTickDayOf(oldStart, task, wallClock), tickTickDayOf(oldDue, task, wallClock))
	if (days <= 0) {
		return null
	}
	var parts = addDays(day, -days).split('-')
	var y = Number(parts[0]), mo = Number(parts[1]) - 1, d = Number(parts[2])
	if (!allDay) {
		var due = new Date(dueMs)
		return new Date(y, mo, d, due.getHours(), due.getMinutes()).getTime()
	}
	var ms = task.timeZone && toUtc ? toUtc(task.timeZone, y, mo, d, 0, 0, 0) : null
	if (ms === null || typeof ms === 'undefined' || isNaN(ms)) {
		ms = new Date(y, mo, d).getTime()
	}
	return ms
}

// The TickTick fields for a body (editBody, toggleBody, restoreBody): only what it changes.
// task: the task's TickTick fields (dueDate, isAllDay, timeZone, items), or null for a new one.
// With dueTime ('HH:mm') the task is timed at that local time, with dueTime '' all-day; without
// dueTime a timed task keeps its time on another day. A task with a start before its due keeps its
// length (tickTickShiftedStart), else startDate is the due. All-day due days are at the start of the
// day in the task's time zone (toUtc(zone, year, month (0-11), day, h, m, s) -> UTC ms or null,
// eg: TimeZone.toUtc; optional), else in local time. A due of null clears the dates.
// opts (optional): { wallClock (see tickTickDue: the current day when only dueTime changes),
// timeZone: the zone a new timed task gets (eg: TimeZone.guessLocal()) }.
// reminders -> 'TRIGGER:...' strings, priority, repeatRule -> repeatFlag, subtasks -> items
// (the task's own item fields kept by id, status 0 / 1).
function toTickTick(body, task, toUtc, opts) {
	var out = {}
	body = body || {}
	opts = opts || {}
	if (typeof body.title !== 'undefined') {
		out.title = body.title || ''
	}
	if (typeof body.notes !== 'undefined') {
		out.content = body.notes || ''
	}
	var hasTime = typeof body.dueTime !== 'undefined'
	var newTime = hasTime ? cleanTime(body.dueTime) : ''
	var day = null // null: the due day doesn't change
	if (typeof body.due !== 'undefined') {
		day = dueDay(body)
	} else if (hasTime && task) {
		day = tickTickDue(task, opts.wallClock).day || null // No due day: no time either
	}
	if (day !== null) {
		if (!day) {
			out.dueDate = null
			out.startDate = null
		} else {
			var parts = day.split('-')
			var y = Number(parts[0]), mo = Number(parts[1]) - 1, d = Number(parts[2])
			var current = parseTickTickDate(task && (task.dueDate || task.startDate))
			var ms = null
			if (newTime) {
				ms = new Date(y, mo, d, Number(newTime.substring(0, 2)), Number(newTime.substring(3, 5))).getTime()
				out.isAllDay = false
				if (!(task && task.timeZone) && opts.timeZone) {
					out.timeZone = String(opts.timeZone)
				}
			} else if (!hasTime && task && task.isAllDay === false && !isNaN(current)) {
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
			var startMs = tickTickShiftedStart(task, day, ms, out.isAllDay, toUtc, opts.wallClock)
			if (startMs !== null) {
				out.startDate = formatTickTickDate(startMs)
			}
		}
	}
	if (typeof body.status !== 'undefined') {
		out.status = body.status === 'completed' ? 2 : 0
		var completedMs = parseTickTickDate(body.completed)
		if (out.status === 2 && !isNaN(completedMs)) {
			out.completedTime = formatTickTickDate(completedMs)
		}
	}
	if (typeof body.priority !== 'undefined') {
		out.priority = priorityOf(body.priority)
	}
	if (typeof body.repeatRule !== 'undefined') {
		out.repeatFlag = cleanRepeatRule(body.repeatRule)
	}
	if (typeof body.reminders !== 'undefined') {
		out.reminders = cleanReminders(body.reminders).map(formatTickTickReminder)
	}
	if (typeof body.subtasks !== 'undefined') {
		out.items = tickTickItems(body.subtasks, task && task.items)
	}
	return out
}

// TickTick checklist items for subtasks ([{ id, title, done }]): an item of current (the task's
// items) with the same id keeps its other fields; a new one (no id) has title and status only.
function tickTickItems(subtasks, current) {
	var byId = {}
	var currentList = current && typeof current.length === 'number' ? current : []
	for (var i = 0; i < currentList.length; i++) {
		if (currentList[i] && currentList[i].id) {
			byId[currentList[i].id] = currentList[i]
		}
	}
	var lastOrder = -1
	return cleanSubtasks(subtasks).map(function(s) {
		var item = {}
		var old = s.id ? byId[s.id] : null
		for (var key in (old || {})) {
			item[key] = old[key]
		}
		if (s.id) {
			item.id = s.id
		}
		item.title = s.title
		var wasDone = tickTickItemDone(old)
		item.status = s.done ? 1 : 0
		if (!s.done) {
			delete item.completedTime
		} else if (!wasDone) {
			item.completedTime = formatTickTickDate(Date.now())
		}
		if (!isFinite(Number(item.sortOrder)) || item.sortOrder === null || item.sortOrder === '') {
			item.sortOrder = lastOrder + 1 // After the item before it
		}
		lastOrder = Number(item.sortOrder)
		return item
	})
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

// By due day: the earliest first (overdue ones), undated last; 0 for the same day.
function compareDue(a, b) {
	var da = dueDay(a)
	var db = dueDay(b)
	if (da === db) {
		return 0
	}
	if (!da || !db) {
		return da ? -1 : 1
	}
	return da < db ? -1 : 1
}

// By title, ignoring case; 0 for the same title.
function compareTitle(a, b) {
	var at = String(a.summary || a.title || '').toLowerCase()
	var bt = String(b.summary || b.title || '').toLowerCase()
	return at === bt ? 0 : at.localeCompare(bt) || (at < bt ? -1 : 1)
}

// By priority: the highest first; 0 for the same priority.
function comparePriority(a, b) {
	return priorityOf(b) - priorityOf(a)
}

// The order of open tasks for a sort (Tasks view "Sort by"): 'due' (sortOpenTasks), 'title' (then
// by due day), 'list' (by the list's rank ra / rb, then in the list's order), 'priority' (the
// highest first, then by due day).
function compareOpen(a, b, sortBy, ra, rb) {
	if (sortBy === 'priority') {
		return comparePriority(a, b) || compareDue(a, b) || comparePosition(a, b)
	}
	if (sortBy === 'title') {
		return compareTitle(a, b) || compareDue(a, b) || comparePosition(a, b)
	}
	if (sortBy === 'list') {
		return ((ra || 0) - (rb || 0)) || comparePosition(a, b)
	}
	return compareDue(a, b) || comparePosition(a, b)
}

// Open tasks: by due day (overdue ones are the earliest, so first), undated last; the same due day
// in the list's order (position). sortBy (optional): see compareOpen. A sorted copy.
function sortOpenTasks(tasks, sortBy) {
	return (tasks || []).slice().sort(function(a, b) {
		return compareOpen(a, b, sortBy, 0, 0)
	})
}

// Open tasks of several lists, [{ item, list }], sorted (compareOpen; 'list': in the order of
// lists). A sorted copy.
function sortOpenEntries(entries, sortBy, lists) {
	var rank = function(list) {
		var i = (lists || []).indexOf(list)
		return i < 0 ? (lists || []).length : i
	}
	return (entries || []).slice().sort(function(a, b) {
		return compareOpen(a.item, b.item, sortBy, rank(a.list), rank(b.list))
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
//   { type: 'task', key, item, list, done }: open tasks (sortOpenTasks), then the 'add' row, then
//     with showCompleted the done ones (sortDoneTasks)
//   { type: 'add', key, list }: the list's quick add ("Add a task…"); all an empty list shows
// sortBy (optional): the open tasks' order, see compareOpen.
function taskRows(lists, itemsByList, showCompleted, sortBy) {
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
			subtaskTree(sortOpenTasks(open, sortBy)).forEach(function(node) {
				var item = node.item
				rows.push({ type: 'task', key: 'task:' + list.id + ':' + item.id, item: item, list: list, done: false, depth: node.depth })
			})
			rows.push({ type: 'add', key: 'add:' + list.id, list: list })
			if (showCompleted) {
				sortDoneTasks(done).forEach(function(item) {
					rows.push({ type: 'task', key: 'task:' + list.id + ':' + item.id, item: item, list: list, done: true })
				})
			}
		})
	})
	return rows
}

// The Day view's tasks for day ('YYYY-MM-DD'): dated ones only, due that day, and on today
// (today: 'YYYY-MM-DD') also the open overdue ones. Open first (sortOpenTasks), then done
// (sortDoneTasks); non-tasks and repeated ids skipped.
function dayTasks(items, day, today) {
	var open = []
	var done = []
	var seen = {}
	for (var i = 0; i < (items || []).length; i++) {
		var item = items[i]
		if (!isTask(item) || seen[item.calendarId + ':' + item.id]) {
			continue
		}
		var due = dueDay(item)
		// Dated tasks only (undated ones are in the Tasks tab): due that day, and on today the open
		// overdue ones.
		var shown = !!due && (due === day || (day === today && !isDone(item) && due < today))
		if (!shown) {
			continue
		}
		seen[item.calendarId + ':' + item.id] = true
		;(isDone(item) ? done : open).push(item)
	}
	return sortOpenTasks(open).concat(sortDoneTasks(done))
}

// dayTasks as rows, [{ item, depth }]: each task's subtasks (Google: parentId) right under it, the
// open ones and the done ones apart.
function dayTaskRows(items, day, today) {
	var tasks = dayTasks(items, day, today)
	return subtaskTree(tasks.filter(function(t) { return !isDone(t) }))
		.concat(subtaskTree(tasks.filter(isDone)))
}

//--- Tasks view by date

// The tasks of the lists, each once: { open: [{ item, list }], done: [{ item, list }] }.
// lists, itemsByList: as taskRows.
function listTasks(lists, itemsByList) {
	var open = []
	var done = []
	;(lists || []).forEach(function(list) {
		var seen = {}
		var items = (itemsByList && itemsByList[list.id]) || []
		for (var i = 0; i < items.length; i++) {
			var item = items[i]
			if (!isTask(item) || seen[item.id]) {
				continue
			}
			seen[item.id] = true
			;(isDone(item) ? done : open).push({ item: item, list: list })
		}
	})
	return { open: open, done: done }
}

// The first day of the week after today's ('YYYY-MM-DD'), weeks starting on firstDayOfWeek
// (0 = Sunday … 6 = Saturday).
function nextWeekStart(today, firstDayOfWeek) {
	var parts = today.split('-')
	var weekday = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]), 12).getDay()
	var first = ((Number(firstDayOfWeek) || 0) % 7 + 7) % 7
	return addDays(today, ((first - weekday + 7) % 7) || 7)
}

// The section of an open task due on day ('' when undated): 'overdue', 'today', 'tomorrow',
// 'week' (the rest of this week), 'later' or 'nodate'.
function dateSection(day, today, firstDayOfWeek) {
	if (!day) {
		return 'nodate'
	}
	if (day < today) {
		return 'overdue'
	}
	if (day === today) {
		return 'today'
	}
	if (day === addDays(today, 1)) {
		return 'tomorrow'
	}
	return day < nextWeekStart(today, firstDayOfWeek) ? 'week' : 'later'
}

var dateSectionOrder = ['overdue', 'today', 'tomorrow', 'week', 'later', 'nodate']

// The open tasks by when they're due: [{ key, items }], keys in dateSectionOrder, empty sections
// left out, each sorted (sortOpenTasks). items: tasks (done ones and non-tasks skipped); today:
// 'YYYY-MM-DD'; firstDayOfWeek: 0 = Sunday … 6 = Saturday.
function dateSections(items, today, firstDayOfWeek) {
	var byKey = {}
	;(items || []).forEach(function(item) {
		if (!isTask(item) || isDone(item)) {
			return
		}
		var key = dateSection(dueDay(item), today, firstDayOfWeek)
		;(byKey[key] = byKey[key] || []).push(item)
	})
	return dateSectionOrder.filter(function(key) {
		return !!byKey[key]
	}).map(function(key) {
		return { key: key, items: sortOpenTasks(byKey[key]) }
	})
}

// The rows of the Tasks view by date, top to bottom (lists, itemsByList: as taskRows):
//   { type: 'section', key, section, count }: a dateSections section, 'done' for the done ones
//   { type: 'task', key, item, list, done, section }
//   { type: 'empty', key }: no open task
//   { type: 'add', key }: the quick add, after the open tasks
// then, with showCompleted, the done ones (sortDoneTasks) under a 'done' section. sortBy
// (optional): the order within a section, see compareOpen.
function dateRows(lists, itemsByList, today, firstDayOfWeek, showCompleted, sortBy) {
	var tasks = listTasks(lists, itemsByList)
	var rows = []
	var bySection = {}
	tasks.open.forEach(function(entry) {
		var key = dateSection(dueDay(entry.item), today, firstDayOfWeek)
		;(bySection[key] = bySection[key] || []).push(entry)
	})
	var sections = dateSectionOrder.filter(function(key) { return !!bySection[key] })
	sections.forEach(function(section) {
		rows.push({ type: 'section', key: 'section:' + section, section: section, count: bySection[section].length })
		pushOpenRows(rows, sortOpenEntries(bySection[section], sortBy, lists), section)
	})
	if (!sections.length) {
		rows.push({ type: 'empty', key: 'empty' })
	}
	rows.push({ type: 'add', key: 'add' })
	if (showCompleted) {
		rows = rows.concat(completedRows(lists, itemsByList))
	}
	return rows
}

// Open rows of entries ([{ item, list }], sorted), each task's subtasks (Google: parentId) right
// under it, indented by depth, when they're in the same run.
function pushOpenRows(rows, entries, section) {
	var items = entries.map(function(e) { return e.item })
	subtaskTree(items).forEach(function(node) {
		var e = entries[items.indexOf(node.item)]
		rows.push({ type: 'task', key: 'task:' + e.list.id + ':' + e.item.id, item: e.item, list: e.list, done: false, section: section, depth: node.depth })
	})
}

// The rows of the Tasks view not grouped (lists, itemsByList: as taskRows): the open tasks of
// all the lists in one run (sortOpenEntries; section ''), the empty note without any, the quick
// add, then with showCompleted the done ones as dateRows has them.
function flatRows(lists, itemsByList, sortBy, showCompleted) {
	var tasks = listTasks(lists, itemsByList)
	var rows = []
	pushOpenRows(rows, sortOpenEntries(tasks.open, sortBy, lists), '')
	if (!rows.length) {
		rows.push({ type: 'empty', key: 'empty' })
	}
	rows.push({ type: 'add', key: 'add' })
	if (showCompleted) {
		rows = rows.concat(completedRows(lists, itemsByList))
	}
	return rows
}

// The done tasks of all the lists (sortDoneTasks) under a 'done' section, as dateRows has them
// with showCompleted; [] without done ones. The islands style's "Completed" card, both groupings.
function completedRows(lists, itemsByList) {
	var done = listTasks(lists, itemsByList).done
	if (!done.length) {
		return []
	}
	var items = done.map(function(e) { return e.item })
	var rows = [{ type: 'section', key: 'section:done', section: 'done', count: done.length }]
	sortDoneTasks(items).forEach(function(item) {
		var list = done[items.indexOf(item)].list
		rows.push({ type: 'task', key: 'task:' + list.id + ':' + item.id, item: item, list: list, done: true, section: 'done' })
	})
	return rows
}

// The islands style's cards over rows (taskRows / dateRows / completedRows): for each row
// { card, start, end, key }: in a card (an account heading isn't), the card's first / last row,
// and the card's key (its first row's). A section, a list, the empty note and "Completed" start a
// card; by date the quick add is a card of its own (with the empty note when there's no task),
// by list (and not grouped: pass true) it ends its list's card.
function cardRows(rows, byList) {
	var out = []
	var key = ''
	for (var i = 0; i < (rows || []).length; i++) {
		var row = rows[i]
		var card = row.type !== 'group'
		var start = card && (i === 0 || rows[i - 1].type === 'group' || row.type === 'section' || row.type === 'list'
			|| row.type === 'empty' || (row.type === 'add' && !byList && rows[i - 1].type !== 'empty'))
		if (start) {
			key = row.key
		}
		out.push({ card: card, start: start, end: false, key: card ? key : '' })
	}
	for (var j = 0; j < out.length; j++) {
		out[j].end = out[j].card && (j === out.length - 1 || !out[j + 1].card || out[j + 1].start)
	}
	return out
}

// rows without those of collapsed cards (collapsed: { cardKey: true }), each card's first row
// (its header) kept.
function collapseRows(rows, byList, collapsed) {
	var cards = cardRows(rows, byList)
	return (rows || []).filter(function(row, i) {
		return !cards[i].card || cards[i].start || !(collapsed && collapsed[cards[i].key])
	})
}

// The due day a task gets when dropped on a date section: today, tomorrow, '' (no date), or null
// when the section takes no drops.
function sectionDueDay(section, today) {
	switch (section) {
		case 'today': return today
		case 'tomorrow': return addDays(today, 1)
		case 'nodate': return ''
	}
	return null
}

// The account of a list id (the part before '::'), '' without one.
function listAccount(listId) {
	var id = String(listId || '')
	var i = id.indexOf('::')
	return i > 0 ? id.substring(0, i) : ''
}

// What dropping a task of list fromId on list toId does: 'move' (to another list of the same
// account), 'none' (its own list) or 'refuse' (another account).
function listDrop(fromId, toId) {
	if (!fromId || !toId || fromId === toId) {
		return 'none'
	}
	var account = listAccount(fromId)
	// Another account (eg: Google → TickTick): copied there, then deleted here.
	if (!account || !listAccount(toId)) {
		return 'refuse'
	}
	return account === listAccount(toId) ? 'move' : 'transfer'
}

//--- Reorder (Google lists): drag a task between the rows of its list

// Whether row b is a task row that a task of row a can be put next to: an open task of the same
// list, in the same section (by date).
function sameRun(a, b) {
	return !!a && !!b && b.type === 'task' && !b.done && !a.done && !!a.list && !!b.list
		&& a.list.id === b.list.id && (a.section || '') === (b.section || '')
}

// The task of dragged's list right before rows[index] in its section (other lists' tasks and
// dragged skipped): its id, '' at the start of the section.
function previousInRun(rows, index, dragged) {
	for (var i = index - 1; i >= 0; i--) {
		var row = rows[i]
		if (row.type !== 'task' || row.done || (row.section || '') !== (dragged.section || '')) {
			return ''
		}
		if (row !== dragged && row.key !== dragged.key && sameRun(dragged, row)) {
			return String(row.item.id)
		}
	}
	return ''
}

// Dropping the dragged task row (rows[dragIndex]) above (above: true) or below rows[targetIndex]:
// the id of the task it goes after ('' : first), or null when that's not a reorder (another list
// or section, a header, itself, or where it already is).
function reorderPrevious(rows, dragIndex, targetIndex, above) {
	rows = rows || []
	var dragged = rows[dragIndex]
	var target = rows[targetIndex]
	if (!dragged || dragged.type !== 'task' || dragIndex === targetIndex || !sameRun(dragged, target)) {
		return null
	}
	var previous = above ? previousInRun(rows, targetIndex, dragged) : String(target.item.id)
	if (previous === previousInRun(rows, dragIndex, dragged)) {
		return null // Where it already is
	}
	return previous
}

//--- Quick add ("Add a task…" rows)

// The body of a task typed in a quick add row: { title, due? }, or null without a title.
function quickAddBody(title, day) {
	var text = String(title || '').trim()
	if (!text) {
		return null
	}
	var body = { title: text }
	if (day) {
		body.due = dueValue(day)
	}
	return body
}

// The list a quick add without its own list adds to: lastId when it's one of lists, else the first.
function quickAddList(lists, lastId) {
	lists = lists || []
	for (var i = 0; i < lists.length; i++) {
		if (lists[i].id === lastId) {
			return lastId
		}
	}
	return lists.length ? lists[0].id : ''
}

//--- Smart filters (the Tasks view's side bar, like TickTick's smart lists)
// 'all', 'today' (due today, and the overdue open ones), 'tomorrow', 'next7' (today to 6 days on,
// the overdue open ones too), 'overdue', 'nodate', and 'list:<id>' for a task list.

var smartFilters = ['all', 'today', 'tomorrow', 'next7', 'overdue', 'nodate']

// The list id of a 'list:<id>' filter, else ''.
function filterListId(filter) {
	var f = String(filter || '')
	return f.indexOf('list:') === 0 ? f.substring(5) : ''
}

// The filter to show: filter when it's a smart one or one of lists' ('list:<id>'), else 'all'.
function validFilter(filter, lists) {
	if (smartFilters.indexOf(filter) >= 0) {
		return filter
	}
	var id = filterListId(filter)
	for (var i = 0; id && i < (lists || []).length; i++) {
		if (lists[i].id === id) {
			return filter
		}
	}
	return 'all'
}

// Whether a task is in a smart filter by when it's due (a 'list:' filter: every task). Open tasks
// by their due day; done ones by their due day, else the day they were completed (never overdue).
function matchesDate(item, filter, today) {
	var done = isDone(item)
	var due = dueDay(item)
	var day = done ? (due || completedDay(item)) : due
	switch (filter) {
		case 'today': return done ? day === today : !!due && due <= today
		case 'tomorrow': return !!day && day === addDays(today, 1)
		case 'next7': return !!day && day <= addDays(today, 6) && (!done || day >= today)
		case 'overdue': return !done && !!due && due < today
		case 'nodate': return !due
	}
	return true
}

// The tasks of items in filter (non-tasks skipped); a 'list:<id>' filter keeps those of that list
// (item.calendarId). today: 'YYYY-MM-DD'.
function filterTasks(items, filter, today) {
	var listId = filterListId(filter)
	return (items || []).filter(function(item) {
		return isTask(item) && (listId ? item.calendarId === listId : matchesDate(item, filter, today))
	})
}

// The lists and their tasks in filter, for taskRows / dateRows / flatRows: { lists, itemsByList }.
// A list filter: that list only; the others: every list, with its tasks in the filter.
// hidden: { listId: true } for lists left out of the smart filters (shown only on their own).
function filterLists(lists, itemsByList, filter, today, hidden) {
	var listId = filterListId(filter)
	var outLists = []
	var outItems = {}
	;(lists || []).forEach(function(list) {
		if (listId ? list.id !== listId : !!(hidden && hidden[list.id])) {
			return
		}
		outLists.push(list)
		var items = (itemsByList && itemsByList[list.id]) || []
		outItems[list.id] = listId ? items.slice() : items.filter(function(item) {
			return isTask(item) && matchesDate(item, filter, today)
		})
	})
	return { lists: outLists, itemsByList: outItems }
}

// The open tasks in each filter: { all, today, tomorrow, next7, overdue, nodate, 'list:<id>' }.
// hidden: as filterLists (those lists count only in their own filter).
function filterCounts(lists, itemsByList, today, hidden) {
	var counts = {}
	smartFilters.forEach(function(f) { counts[f] = 0 })
	;(lists || []).forEach(function(list) {
		counts['list:' + list.id] = 0
	})
	listTasks(lists, itemsByList).open.forEach(function(e) {
		smartFilters.forEach(function(f) {
			if (!(hidden && hidden[e.list.id]) && matchesDate(e.item, f, today)) {
				counts[f]++
			}
		})
		counts['list:' + e.list.id]++
	})
	return counts
}

// The entries of the filter side bar (and its menu), top to bottom:
//   { type: 'filter', key, count }: the smart filters
//   { type: 'separator', key }
//   { type: 'group', key, text }: an account's heading, only when the lists are from several
//   { type: 'list', key, list, count }: each list ('list:<id>'), by account as taskRows has them
// counts: filterCounts.
function filterEntries(lists, counts) {
	counts = counts || {}
	var entries = smartFilters.map(function(f) {
		return { type: 'filter', key: f, count: counts[f] || 0 }
	})
	var listRows = taskRows(lists, {}, false).filter(function(row) {
		return row.type === 'group' || row.type === 'list'
	})
	if (listRows.length) {
		entries.push({ type: 'separator', key: 'separator' })
	}
	listRows.forEach(function(row) {
		if (row.type === 'group') {
			entries.push({ type: 'group', key: row.key, text: row.text })
		} else {
			entries.push({ type: 'list', key: 'list:' + row.list.id, list: row.list, count: counts['list:' + row.list.id] || 0 })
		}
	})
	return entries
}

// Where "Add a task…" adds under filter: { listId: the filter's list or '', dueDay: today on
// Today and Next 7 days, tomorrow on Tomorrow, else '' }.
function filterQuickAdd(filter, today) {
	var dueDay = filter === 'today' || filter === 'next7' ? today : filter === 'tomorrow' ? addDays(today, 1) : ''
	return { listId: filterListId(filter), dueDay: dueDay }
}
