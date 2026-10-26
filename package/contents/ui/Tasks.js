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

// The order of open tasks for a sort (Tasks view "Sort by"): 'due' (sortOpenTasks), 'title' (then
// by due day), 'list' (by the list's rank ra / rb, then in the list's order).
function compareOpen(a, b, sortBy, ra, rb) {
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
			sortOpenTasks(open, sortBy).forEach(function(item) {
				rows.push({ type: 'task', key: 'task:' + list.id + ':' + item.id, item: item, list: list, done: false })
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

function pushOpenRows(rows, entries, section) {
	entries.forEach(function(e) {
		rows.push({ type: 'task', key: 'task:' + e.list.id + ':' + e.item.id, item: e.item, list: e.list, done: false, section: section })
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
	return account && account === listAccount(toId) ? 'move' : 'refuse'
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
function filterLists(lists, itemsByList, filter, today) {
	var listId = filterListId(filter)
	var outLists = []
	var outItems = {}
	;(lists || []).forEach(function(list) {
		if (listId && list.id !== listId) {
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
function filterCounts(lists, itemsByList, today) {
	var counts = {}
	smartFilters.forEach(function(f) { counts[f] = 0 })
	;(lists || []).forEach(function(list) {
		counts['list:' + list.id] = 0
	})
	listTasks(lists, itemsByList).open.forEach(function(e) {
		smartFilters.forEach(function(f) {
			if (matchesDate(e.item, f, today)) {
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
