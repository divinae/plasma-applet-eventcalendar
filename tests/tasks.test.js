// Fixed zone with daylight saving (Europe/Warsaw switches back on 25 October 2026).
process.env.TZ = 'Europe/Warsaw'

const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const read = file => fs.readFileSync(path.join(__dirname, '../package/contents/ui', file), 'utf8')
	.replace(/^\.pragma library\s*$/m, '').replace(/^\.import .*$/mg, '')
const names = ['isTask', 'isDone', 'dueDay', 'completedDay', 'isOverdue', 'placementDay', 'toggleBody',
	'editBody', 'restoreBody', 'dayString', 'addDays', 'parseTickTickDate', 'formatTickTickDate', 'tickTickDue',
	'fromTickTick', 'toTickTick', 'withoutTasks', 'sortOpenTasks', 'sortDoneTasks', 'dueInfo', 'firstLine', 'taskRows', 'dayTasks',
	'nextWeekStart', 'dateSections', 'dateRows', 'completedRows', 'cardRows', 'collapseRows', 'sectionDueDay', 'listAccount', 'listDrop', 'quickAddBody', 'quickAddList',
	'flatRows', 'filterListId', 'validFilter', 'filterTasks', 'filterLists', 'filterCounts', 'filterEntries', 'filterQuickAdd',
	'priorityOf', 'editorChanges', 'priorityKey', 'dueTimeOf', 'subtaskProgress', 'capabilities', 'dayTaskRows', 'reorderPrevious', 'subtaskTree', 'googleBody', 'parseTickTickReminder', 'formatTickTickReminder', 'tickTickItems']
const T = {}
const plain = o => JSON.parse(JSON.stringify(o))
const same = (a, b, msg) => assert.deepStrictEqual(plain(a), b, msg)
vm.runInNewContext(read('Tasks.js') + '\nObject.assign(out, { ' + names.join(', ') + ' })', { out: T, Date })

const now = new Date(2026, 9, 26, 0, 30) // Monday 26 October, 00:30 local (still the 25th in UTC)
const task = (fields) => Object.assign({ kind: 'tasks#task', status: 'needsAction' }, fields)

// isTask / isDone
assert.strictEqual(T.isTask(task({})), true)
assert.strictEqual(T.isTask({ kind: 'calendar#event' }), false)
assert.strictEqual(T.isTask(null), false)
assert.strictEqual(T.isDone(task({ status: 'completed' })), true)
assert.strictEqual(T.isDone(task({})), false)

// withoutTasks: the Month / Week / Day views get events only.
same(T.withoutTasks([task({ id: 't' }), { kind: 'calendar#event', id: 'e' }, { id: 'x' }]).map(i => i.id), ['e', 'x'])
same(T.withoutTasks(null), [])

// sortOpenTasks: overdue (earliest due) first, then by due day, undated last; same day by position.
{
	const open = [
		task({ id: 'undated-b', position: '2' }),
		task({ id: 'later', due: '2026-11-03T00:00:00.000Z' }),
		task({ id: 'today-2', due: '2026-10-26T00:00:00.000Z', position: '00002' }),
		task({ id: 'overdue', due: '2026-10-20T00:00:00.000Z' }),
		task({ id: 'today-1', due: '2026-10-26T00:00:00.000Z', position: '00001' }),
		task({ id: 'undated-a', position: '1' }),
	]
	same(T.sortOpenTasks(open).map(t => t.id), ['overdue', 'today-1', 'today-2', 'later', 'undated-a', 'undated-b'])
	assert.strictEqual(open[0].id, 'undated-b', 'a sorted copy')
}
// sortDoneTasks: last completed first.
same(T.sortDoneTasks([
	task({ id: 'old', status: 'completed', completed: '2026-10-01T10:00:00.000Z' }),
	task({ id: 'new', status: 'completed', completed: '2026-10-25T10:00:00.000Z' }),
]).map(t => t.id), ['new', 'old'])

// dueInfo
same(T.dueInfo(task({}), now), { kind: 'none', day: '' })
same(T.dueInfo(task({ due: '2026-10-26T00:00:00.000Z' }), now), { kind: 'today', day: '2026-10-26' })
same(T.dueInfo(task({ due: '2026-10-27T00:00:00.000Z' }), now), { kind: 'tomorrow', day: '2026-10-27' })
same(T.dueInfo(task({ due: '2026-10-25T00:00:00.000Z' }), now), { kind: 'overdue', day: '2026-10-25' })
same(T.dueInfo(task({ due: '2026-10-25T00:00:00.000Z', status: 'completed' }), now), { kind: 'date', day: '2026-10-25' })
same(T.dueInfo(task({ due: '2026-12-01T00:00:00.000Z' }), now), { kind: 'date', day: '2026-12-01' })

// firstLine
assert.strictEqual(T.firstLine('\n  first  \nsecond'), 'first')
assert.strictEqual(T.firstLine(undefined), '')

// taskRows: lists grouped by account (headings only for more than one), open tasks, an empty
// note, done tasks with showCompleted; events and repeated ids skipped.
{
	const lists = [
		{ id: 'g::a', name: 'A', group: 'Work' },
		{ id: 't::x', name: 'X', group: 'TickTick' },
		{ id: 'g::b', name: 'B', group: 'Work' },
	]
	const items = {
		'g::a': [task({ id: '1', due: '2026-10-28T00:00:00.000Z' }), task({ id: '2', due: '2026-10-20T00:00:00.000Z' }),
			task({ id: '2', due: '2026-10-20T00:00:00.000Z' }), { kind: 'calendar#event', id: 'e' },
			task({ id: '3', status: 'completed' })],
		'g::b': [task({ id: '4', status: 'completed' })],
	}
	const rows = T.taskRows(lists, items, false)
	same(rows.map(r => r.key), ['group:Work', 'list:g::a', 'task:g::a:2', 'task:g::a:1', 'add:g::a', 'list:g::b', 'add:g::b',
		'group:TickTick', 'list:t::x', 'add:t::x'])
	assert.strictEqual(rows[1].openCount, 2)
	assert.strictEqual(rows[1].doneCount, 1)
	const withDone = T.taskRows(lists, items, true)
	same(withDone.filter(r => r.type === 'task').map(r => r.item.id + (r.done ? '+' : '')), ['2', '1', '3+', '4+'])
	same(withDone.slice(1, 6).map(r => r.key), ['list:g::a', 'task:g::a:2', 'task:g::a:1', 'add:g::a', 'task:g::a:3'],
		'the quick add after the open tasks, before the done ones')
	same(T.taskRows([lists[0]], items, false).filter(r => r.type === 'group'), [], 'one account: no heading')
}

// dayTasks: dated tasks only: due that day; on today also the open overdue ones; done after open.
{
	const items = [
		task({ id: 'today', calendarId: 'l', due: '2026-10-26T00:00:00.000Z' }),
		task({ id: 'overdue', calendarId: 'l', due: '2026-10-20T00:00:00.000Z' }),
		task({ id: 'undated', calendarId: 'l' }),
		task({ id: 'done-today', calendarId: 'l', due: '2026-10-26T00:00:00.000Z', status: 'completed' }),
		task({ id: 'done-undated', calendarId: 'l', status: 'completed' }),
		task({ id: 'tomorrow', calendarId: 'l', due: '2026-10-27T00:00:00.000Z' }),
		task({ id: 'today', calendarId: 'l', due: '2026-10-26T00:00:00.000Z' }),
		{ kind: 'calendar#event', id: 'e', calendarId: 'c' },
	]
	same(T.dayTasks(items, '2026-10-26', '2026-10-26').map(t => t.id), ['overdue', 'today', 'done-today'], 'no undated')
	same(T.dayTasks(items, '2026-10-27', '2026-10-26').map(t => t.id), ['tomorrow'])
	same(T.dayTasks(items, '2026-10-20', '2026-10-26').map(t => t.id), ['overdue'], 'its own day too')
	same(T.dayTasks(null, '2026-10-26', '2026-10-26'), [])
}

// dateSections: Monday 26 October; "this week" is the rest of the week (Monday-first: to Sunday 1
// November; Sunday-first: to Saturday 31 October).
{
	const due = (id, day, more) => task(Object.assign({ id: id, due: day ? day + 'T00:00:00.000Z' : undefined }, more))
	const items = [
		due('none-b', '', { position: '2' }), due('later', '2026-11-05'), due('sun', '2026-11-01'),
		due('wed', '2026-10-28'), due('tomorrow', '2026-10-27'), due('today', '2026-10-26'),
		due('old', '2026-10-01'), due('overdue', '2026-10-25'), due('none-a', '', { position: '1' }),
		due('done', '2026-10-26', { status: 'completed' }), { kind: 'calendar#event', id: 'e' },
	]
	const keys = s => s.map(x => x.key + ':' + x.items.map(t => t.id).join(','))
	same(keys(T.dateSections(items, '2026-10-26', 1)), ['overdue:old,overdue', 'today:today', 'tomorrow:tomorrow',
		'week:wed,sun', 'later:later', 'nodate:none-a,none-b'])
	same(keys(T.dateSections(items, '2026-10-26', 0)).slice(3, 5), ['week:wed', 'later:sun,later'], 'Sunday-first')
	// On the week's last day "tomorrow" is next week: no "this week".
	same(keys(T.dateSections(items, '2026-11-01', 1)).map(k => k.split(':')[0]), ['overdue', 'today', 'later', 'nodate'])
	same(T.dateSections([due('x', '2026-10-30')], '2026-10-26', 1).map(s => s.key), ['week'], 'empty sections left out')
	same(T.dateSections(null, '2026-10-26', 1), [])
	assert.strictEqual(T.nextWeekStart('2026-10-26', 1), '2026-11-02')
	assert.strictEqual(T.nextWeekStart('2026-11-01', 0), '2026-11-08', 'a week day is never its own next week')
	assert.strictEqual(T.nextWeekStart('2026-10-31', 6), '2026-11-07')
}

// dateRows: sections with each task's list, the quick add after the open tasks, done ones last.
{
	const lists = [{ id: 'g::a', name: 'A' }, { id: 'g::b', name: 'B' }]
	const items = {
		'g::a': [task({ id: '1', due: '2026-10-26T00:00:00.000Z' }), task({ id: '2' }), task({ id: '2' }),
			task({ id: '3', status: 'completed', completed: '2026-10-20T10:00:00.000Z' })],
		'g::b': [task({ id: '4', due: '2026-10-20T00:00:00.000Z' }), { kind: 'calendar#event', id: 'e' },
			task({ id: '5', status: 'completed', completed: '2026-10-25T10:00:00.000Z' })],
	}
	same(T.dateRows(lists, items, '2026-10-26', 1, false).map(r => r.key), ['section:overdue', 'task:g::b:4',
		'section:today', 'task:g::a:1', 'section:nodate', 'task:g::a:2', 'add'])
	const withDone = T.dateRows(lists, items, '2026-10-26', 1, true)
	same(withDone.slice(-3).map(r => r.key), ['section:done', 'task:g::b:5', 'task:g::a:3'])
	assert.strictEqual(withDone[1].list.name, 'B')
	assert.strictEqual(withDone[1].section, 'overdue')
	assert.strictEqual(withDone[0].count, 1)
	same(T.dateRows(lists, {}, '2026-10-26', 1, true).map(r => r.key), ['empty', 'add'])

	// completedRows: the done ones of all lists, the same rows as dateRows' with showCompleted.
	same(plain(T.completedRows(lists, items)), plain(withDone.slice(-3)))
	same(T.completedRows(lists, {}), [])

	// cardRows: by date a card per section, the quick add a card of its own, then "Completed".
	const cardSummary = (rows, byList) => T.cardRows(rows, byList).map((c, i) =>
		(c.card ? (c.start ? '[' : '') + rows[i].key + (c.end ? ']' : '') : rows[i].key) + (c.card ? '@' + c.key : ''))
	same(cardSummary(withDone, false), ['[section:overdue@section:overdue', 'task:g::b:4]@section:overdue',
		'[section:today@section:today', 'task:g::a:1]@section:today', '[section:nodate@section:nodate', 'task:g::a:2]@section:nodate',
		'[add]@add', '[section:done@section:done', 'task:g::b:5@section:done', 'task:g::a:3]@section:done'])
	// No open task: the empty note and the quick add share a card.
	same(cardSummary(T.dateRows(lists, {}, '2026-10-26', 1, false), false), ['[empty@empty', 'add]@empty'])
	// collapseRows: a collapsed card keeps its header.
	same(T.collapseRows(withDone, false, { 'section:today': true, 'section:done': true }).map(r => r.key), ['section:overdue',
		'task:g::b:4', 'section:today', 'section:nodate', 'task:g::a:2', 'add', 'section:done'])
	same(T.collapseRows(withDone, false, {}).length, withDone.length)
}

// cardRows by list: an account heading outside the cards, a list with its quick add and done ones.
{
	const lists = [{ id: 'g::a', name: 'A', group: 'g' }, { id: 't::b', name: 'B', group: 't' }]
	const items = { 'g::a': [task({ id: '1' }), task({ id: '2', status: 'completed' })], 't::b': [] }
	const rows = T.taskRows(lists, items, true)
	same(T.cardRows(rows, true).map((c, i) => [rows[i].key, c.card, c.start, c.end, c.key]), [
		['group:g', false, false, false, ''],
		['list:g::a', true, true, false, 'list:g::a'],
		['task:g::a:1', true, false, false, 'list:g::a'],
		['add:g::a', true, false, false, 'list:g::a'],
		['task:g::a:2', true, false, true, 'list:g::a'],
		['group:t', false, false, false, ''],
		['list:t::b', true, true, false, 'list:t::b'],
		['add:t::b', true, false, true, 'list:t::b'],
	])
	same(T.collapseRows(rows, true, { 'list:g::a': true }).map(r => r.key), ['group:g', 'list:g::a', 'group:t', 'list:t::b', 'add:t::b'])
}

// Sort by (sortOpenTasks / taskRows / dateRows / flatRows): due date, title or list order.
{
	const a = task({ id: 'a', summary: 'banana', due: '2026-10-27T00:00:00.000Z', position: '2' })
	const b = task({ id: 'b', summary: 'Apple', position: '3' })
	const c = task({ id: 'c', summary: 'cherry', due: '2026-10-26T00:00:00.000Z', position: '1' })
	same(T.sortOpenTasks([a, b, c]).map(t => t.id), ['c', 'a', 'b'], 'due by default')
	same(T.sortOpenTasks([a, b, c], 'title').map(t => t.id), ['b', 'a', 'c'], 'by title, ignoring case')
	same(T.sortOpenTasks([a, b, c], 'list').map(t => t.id), ['c', 'a', 'b'], "in the list's order")
	const lists = [{ id: 'g::a', name: 'A' }, { id: 'g::b', name: 'B' }]
	const items = { 'g::b': [a, c], 'g::a': [b] }
	same(T.taskRows(lists, items, false, 'title').filter(r => r.type === 'task').map(r => r.item.id), ['b', 'a', 'c'])
	same(T.taskRows(lists, items, false, 'list').filter(r => r.type === 'task').map(r => r.item.id), ['b', 'c', 'a'])

	// flatRows: one run of the open tasks of all lists, then the quick add (and the done ones).
	same(T.flatRows(lists, items, 'due', false).map(r => r.key), ['task:g::b:c', 'task:g::b:a', 'task:g::a:b', 'add'])
	same(T.flatRows(lists, items, 'title', false).map(r => r.key), ['task:g::a:b', 'task:g::b:a', 'task:g::b:c', 'add'])
	same(T.flatRows(lists, items, 'list', false).map(r => r.key), ['task:g::a:b', 'task:g::b:c', 'task:g::b:a', 'add'],
		'by the order of the lists')
	same(T.flatRows(lists, {}, 'due', false).map(r => r.key), ['empty', 'add'])
	const done = { 'g::a': [b, task({ id: 'd', status: 'completed' })] }
	same(T.flatRows(lists, done, 'due', true).map(r => r.key), ['task:g::a:b', 'add', 'section:done', 'task:g::a:d'])
	assert.strictEqual(T.flatRows(lists, items, 'due', false)[0].section, '')
	// Not grouped, islands: the tasks and the quick add are one card.
	same(T.cardRows(T.flatRows(lists, done, 'due', true), true).map(c => [c.start, c.end]),
		[[true, false], [false, true], [true, false], [false, true]])

	// dateRows: the sort within each section.
	const same2 = { 'g::a': [task({ id: 'z', summary: 'Zed', due: '2026-10-26T00:00:00.000Z', position: '1' }),
		task({ id: 'y', summary: 'apple', due: '2026-10-26T00:00:00.000Z', position: '2' })] }
	same(T.dateRows(lists, same2, '2026-10-26', 1, false).map(r => r.key), ['section:today', 'task:g::a:z', 'task:g::a:y', 'add'])
	same(T.dateRows(lists, same2, '2026-10-26', 1, false, 'title').map(r => r.key), ['section:today', 'task:g::a:y', 'task:g::a:z', 'add'])
}

// Smart filters: today is Monday 26 October.
{
	const today = '2026-10-26'
	const due = (id, list, day, more) => task(Object.assign({ id: id, calendarId: list, due: day ? day + 'T00:00:00.000Z' : undefined }, more))
	const lists = [{ id: 'g::a', name: 'A', group: 'me@g' }, { id: 'g::b', name: 'B', group: 'me@g' }, { id: 't::c', name: 'C', group: 'TickTick' }]
	const items = {
		'g::a': [due('old', 'g::a', '2026-10-20'), due('today', 'g::a', today), due('tomorrow', 'g::a', '2026-10-27'),
			due('sun', 'g::a', '2026-11-01'), due('next-mon', 'g::a', '2026-11-02'), due('none', 'g::a', ''),
			due('done-today', 'g::a', today, { status: 'completed' }),
			due('done-old', 'g::a', '2026-10-20', { status: 'completed' }),
			due('done-undated', 'g::a', '', { status: 'completed', completed: '2026-10-26T09:00:00.000Z' })],
		'g::b': [due('b-today', 'g::b', today), { kind: 'calendar#event', id: 'e', calendarId: 'g::b' }],
		't::c': [],
	}
	const all = [].concat(items['g::a'], items['g::b'])
	const ids = (filter) => T.filterTasks(all, filter, today).map(t => t.id)
	same(ids('all'), ['old', 'today', 'tomorrow', 'sun', 'next-mon', 'none', 'done-today', 'done-old', 'done-undated', 'b-today'])
	same(ids('today'), ['old', 'today', 'done-today', 'done-undated', 'b-today'], 'overdue open ones too; done ones done today')
	same(ids('tomorrow'), ['tomorrow'])
	same(ids('next7'), ['old', 'today', 'tomorrow', 'sun', 'done-today', 'done-undated', 'b-today'], 'today to +6, overdue too')
	same(ids('overdue'), ['old'], 'open ones only')
	same(ids('nodate'), ['none', 'done-undated'])
	same(ids('list:g::b'), ['b-today'])
	same(T.filterTasks(null, 'all', today), [])

	// filterCounts: open tasks only.
	same(T.filterCounts(lists, items, today), { all: 7, today: 3, tomorrow: 1, next7: 5, overdue: 1, nodate: 1,
		'list:g::a': 6, 'list:g::b': 1, 'list:t::c': 0 })
	same(T.filterCounts([], {}, today), { all: 0, today: 0, tomorrow: 0, next7: 0, overdue: 0, nodate: 0 })

	// filterLists: a list filter keeps that list only; the others keep every list.
	const one = T.filterLists(lists, items, 'list:g::b', today)
	same(one.lists.map(l => l.id), ['g::b'])
	same(Object.keys(one.itemsByList), ['g::b'])
	const tomorrow = T.filterLists(lists, items, 'tomorrow', today)
	same(tomorrow.lists.map(l => l.id), ['g::a', 'g::b', 't::c'])
	same(tomorrow.itemsByList['g::a'].map(t => t.id), ['tomorrow'])
	same(tomorrow.itemsByList['g::b'], [])
	same(T.dateRows(tomorrow.lists, tomorrow.itemsByList, today, 1, false).map(r => r.key), ['section:tomorrow', 'task:g::a:tomorrow', 'add'])

	// Lists left out of the smart filters (hidden): only on their own filter, and not counted elsewhere.
	const hidden = { 'g::b': true }
	same(T.filterLists(lists, items, 'today', today, hidden).lists.map(l => l.id), ['g::a', 't::c'], 'hidden list not in a smart filter')
	same(T.filterLists(lists, items, 'list:g::b', today, hidden).lists.map(l => l.id), ['g::b'], 'still on its own')
	const hiddenCounts = T.filterCounts(lists, items, today, hidden)
	assert.strictEqual(hiddenCounts.all, 6, 'all without the hidden list')
	assert.strictEqual(hiddenCounts['list:g::b'], 1, 'its own count kept')

	// validFilter: back to 'all' when the list is gone, or for anything unknown.
	assert.strictEqual(T.validFilter('today', lists), 'today')
	assert.strictEqual(T.validFilter('list:t::c', lists), 'list:t::c')
	assert.strictEqual(T.validFilter('list:gone', lists), 'all')
	assert.strictEqual(T.validFilter('list:', lists), 'all')
	assert.strictEqual(T.validFilter('', lists), 'all')
	assert.strictEqual(T.validFilter(undefined, null), 'all')
	assert.strictEqual(T.filterListId('list:g::a'), 'g::a')
	assert.strictEqual(T.filterListId('today'), '')

	// filterEntries: the smart filters, then the lists by account (headings with several accounts).
	const counts = T.filterCounts(lists, items, today)
	same(T.filterEntries(lists, counts).map(e => e.type + ':' + e.key + (e.count !== undefined ? '=' + e.count : '')), [
		'filter:all=7', 'filter:today=3', 'filter:tomorrow=1', 'filter:next7=5', 'filter:overdue=1', 'filter:nodate=1',
		'separator:separator', 'group:group:me@g', 'list:list:g::a=6', 'list:list:g::b=1', 'group:group:TickTick', 'list:list:t::c=0'])
	same(T.filterEntries(lists.slice(0, 2), counts).filter(e => e.type === 'group'), [], 'one account: no headings')
	same(T.filterEntries([], {}).map(e => e.key), ['all', 'today', 'tomorrow', 'next7', 'overdue', 'nodate'])

	// filterQuickAdd: the list of a list filter, the due day of Today / Tomorrow / Next 7 days.
	same(T.filterQuickAdd('list:g::b', today), { listId: 'g::b', dueDay: '' })
	same(T.filterQuickAdd('today', today), { listId: '', dueDay: today })
	same(T.filterQuickAdd('tomorrow', today), { listId: '', dueDay: '2026-10-27' })
	same(T.filterQuickAdd('next7', today), { listId: '', dueDay: today })
	same(T.filterQuickAdd('overdue', today), { listId: '', dueDay: '' })
	same(T.filterQuickAdd('all', today), { listId: '', dueDay: '' })
}

// Drops: date sections that set a due day, lists of the same account only.
assert.strictEqual(T.sectionDueDay('today', '2026-10-31'), '2026-10-31')
assert.strictEqual(T.sectionDueDay('tomorrow', '2026-10-31'), '2026-11-01')
assert.strictEqual(T.sectionDueDay('nodate', '2026-10-31'), '')
assert.strictEqual(T.sectionDueDay('week', '2026-10-31'), null)
assert.strictEqual(T.sectionDueDay('overdue', '2026-10-31'), null)
assert.strictEqual(T.listAccount('google1::abc'), 'google1')
assert.strictEqual(T.listAccount('abc'), '')
assert.strictEqual(T.listDrop('g1::a', 'g1::b'), 'move')
assert.strictEqual(T.listDrop('g1::a', 'g1::a'), 'none')
assert.strictEqual(T.listDrop('g1::a', 'tt::b'), 'transfer', 'another account: copied and deleted')
assert.strictEqual(T.listDrop('a', 'b'), 'refuse', 'no account: no move')

// Quick add
same(T.quickAddBody('  Buy milk ', ''), { title: 'Buy milk' })
same(T.quickAddBody('Buy milk', '2026-10-27'), { title: 'Buy milk', due: '2026-10-27T00:00:00.000Z' })
assert.strictEqual(T.quickAddBody('   ', '2026-10-27'), null)
assert.strictEqual(T.quickAddList([{ id: 'a' }, { id: 'b' }], 'b'), 'b')
assert.strictEqual(T.quickAddList([{ id: 'a' }, { id: 'b' }], 'gone'), 'a')
assert.strictEqual(T.quickAddList([], 'b'), '')

// dueDay: the date part, whatever the time zone.
assert.strictEqual(T.dueDay(task({ due: '2026-10-26T00:00:00.000Z' })), '2026-10-26')
assert.strictEqual(T.dueDay(task({})), '')
assert.strictEqual(T.dueDay(task({ due: 'garbage' })), '')

// completedDay: local day of the timestamp.
assert.strictEqual(T.completedDay(task({ completed: '2026-10-25T23:30:00.000Z' })), '2026-10-26')

// isOverdue
assert.strictEqual(T.isOverdue(task({ due: '2026-10-25T00:00:00.000Z' }), now), true)
assert.strictEqual(T.isOverdue(task({ due: '2026-10-26T00:00:00.000Z' }), now), false, 'due today')
assert.strictEqual(T.isOverdue(task({ due: '2026-10-25T00:00:00.000Z', status: 'completed' }), now), false, 'done')
assert.strictEqual(T.isOverdue(task({}), now), false, 'undated')

// placementDay
assert.strictEqual(T.placementDay(task({}), now, false), '2026-10-26', 'undated: today')
assert.strictEqual(T.placementDay(task({ due: '2026-10-30T00:00:00.000Z' }), now, true), '2026-10-30')
assert.strictEqual(T.placementDay(task({ due: '2026-10-20T00:00:00.000Z' }), now, true), '2026-10-26', 'overdue on today')
assert.strictEqual(T.placementDay(task({ due: '2026-10-20T00:00:00.000Z' }), now, false), '2026-10-20', 'overdue on its day')
assert.strictEqual(T.placementDay(task({ due: '2026-10-20T00:00:00.000Z', status: 'completed',
	completed: '2026-10-24T10:00:00.000Z' }), now, true), '2026-10-20', 'done: due day')
assert.strictEqual(T.placementDay(task({ status: 'completed', completed: '2026-10-24T10:00:00.000Z' }), now, true),
	'2026-10-24', 'done, undated: completion day')
assert.strictEqual(T.placementDay(task({ status: 'completed' }), now, true), '2026-10-26', 'done, no dates: today')

// toggleBody
const at = new Date(Date.UTC(2026, 9, 26, 8, 0))
same(T.toggleBody(true, at), { status: 'completed', completed: '2026-10-26T08:00:00.000Z' })
same(T.toggleBody(false, at), { status: 'needsAction', completed: null })
assert.strictEqual(typeof T.toggleBody(true).completed, 'string')

// editBody: only the given changes.
same(T.editBody({}), {})
same(T.editBody({ title: 'A' }), { title: 'A' })
same(T.editBody({ notes: '', dueDay: '' }), { notes: '', due: null })
same(T.editBody({ title: 'A', notes: 'n', dueDay: '2026-11-01' }),
	{ title: 'A', notes: 'n', due: '2026-11-01T00:00:00.000Z' })

// restoreBody: from an undo copy (no status).
same(T.restoreBody({ title: 'A', notes: 'n', due: '2026-11-01T00:00:00.000Z', isCompleted: false }),
	{ title: 'A', notes: 'n', due: '2026-11-01T00:00:00.000Z', status: 'needsAction' })
same(T.restoreBody({ title: 'B', completed: '2026-10-24T10:00:00.000Z', isCompleted: true }),
	{ title: 'B', status: 'completed', completed: '2026-10-24T10:00:00.000Z' })

// addDays across the daylight saving change and month ends.
assert.strictEqual(T.addDays('2026-10-25', 1), '2026-10-26')
assert.strictEqual(T.addDays('2026-10-31', 1), '2026-11-01')
assert.strictEqual(T.addDays('2026-12-31', 1), '2027-01-01')

//--- TickTick
// The real TimeZone.js wall clock / toUtc, as the manager passes them.
const strip = s => s.replace(/^\.(pragma|import).*$/gm, '')
const UI = path.join(__dirname, '../package/contents/ui')
const TimeZoneData = {}
vm.runInNewContext(strip(fs.readFileSync(path.join(UI, 'code/TimeZoneData.js'), 'utf8')) + '\nObject.assign(out, { rules, recent, pickerZones })', { out: TimeZoneData })
const TZ = {}
vm.runInNewContext(strip(fs.readFileSync(path.join(UI, 'TimeZone.js'), 'utf8')) + '\nObject.assign(out, { wallClock, toUtc })',
	{ out: TZ, TimeZoneData, Date, Math })

// parse / format
assert.strictEqual(T.parseTickTickDate('2026-10-27T03:00:00+0000'), Date.UTC(2026, 9, 27, 3, 0, 0))
assert.strictEqual(T.parseTickTickDate('2026-10-27T05:00:00+0200'), Date.UTC(2026, 9, 27, 3, 0, 0))
assert.strictEqual(T.parseTickTickDate('2026-10-27T00:30:00-03:30'), Date.UTC(2026, 9, 27, 4, 0, 0))
assert.strictEqual(T.parseTickTickDate('2026-10-27T03:00:00.250Z'), Date.UTC(2026, 9, 27, 3, 0, 0, 250))
assert.ok(isNaN(T.parseTickTickDate('')))
assert.ok(isNaN(T.parseTickTickDate(null)))
assert.ok(isNaN(T.parseTickTickDate('tomorrow')))
assert.strictEqual(T.formatTickTickDate(Date.UTC(2026, 0, 2, 3, 4, 5)), '2026-01-02T03:04:05+0000')

// tickTickDue: all-day in the task's zone; local without a known zone; timed: local day + time.
// Midnight 27 October in Tokyo is still the 26th in UTC and in Warsaw.
const tokyoAllDay = { dueDate: '2026-10-26T15:00:00+0000', isAllDay: true, timeZone: 'Asia/Tokyo' }
same(T.tickTickDue(tokyoAllDay, TZ.wallClock), { day: '2026-10-27', time: '' })
same(T.tickTickDue(tokyoAllDay, null), { day: '2026-10-26', time: '' }, 'no wall clock: local day')
same(T.tickTickDue({ dueDate: '2026-10-26T23:00:00+0000', isAllDay: true }, TZ.wallClock), { day: '2026-10-27', time: '' })
same(T.tickTickDue({ dueDate: '2026-10-26T23:00:00+0000', isAllDay: true, timeZone: 'Nowhere/Unknown' }, TZ.wallClock),
	{ day: '2026-10-27', time: '' }, 'unknown zone: local')
same(T.tickTickDue({ dueDate: '2026-10-27T13:00:00+0000', isAllDay: false, timeZone: 'Asia/Tokyo' }, TZ.wallClock),
	{ day: '2026-10-27', time: '14:00' }, 'timed: local (Warsaw, UTC+1 after the switch)')
same(T.tickTickDue({ startDate: '2026-10-26T23:00:00+0000' }, null), { day: '2026-10-27', time: '' }, 'start date only')
same(T.tickTickDue({}, null), { day: '', time: '' })
same(T.tickTickDue({ dueDate: 'bad' }, null), { day: '', time: '' })

// fromTickTick: Google-shaped fields the UI reads.
const noExtras = { reminders: [], priority: 0, repeatRule: '', parentId: '', subtasks: [] }
same(T.fromTickTick({ title: 'A', content: 'n', dueDate: '2026-10-26T23:00:00+0000', isAllDay: true, status: 0 }, TZ.wallClock),
	{ title: 'A', notes: 'n', due: '2026-10-27T00:00:00.000Z', dueTime: '', status: 'needsAction', completed: null, ...noExtras })
same(T.fromTickTick({ title: 'B', status: 2, completedTime: '2026-10-25T10:00:00+0000' }, null),
	{ title: 'B', notes: '', due: null, dueTime: '', status: 'completed', completed: '2026-10-25T10:00:00.000Z', ...noExtras })
const fromTimed = T.fromTickTick({ title: 'C', dueDate: '2026-10-27T13:00:00+0000', isAllDay: false, status: 0 }, null)
assert.strictEqual(fromTimed.due, '2026-10-27T00:00:00.000Z')
assert.strictEqual(fromTimed.dueTime, '14:00')
// A converted task works with the shared helpers.
const converted = task(T.fromTickTick({ title: 'D', dueDate: '2026-10-20T22:00:00+0000', isAllDay: true, status: 0 }, null))
assert.strictEqual(T.dueDay(converted), '2026-10-21')
assert.strictEqual(T.isOverdue(converted, now), true)
assert.strictEqual(T.placementDay(converted, now, true), '2026-10-26')

// toTickTick: only what the body changes.
same(T.toTickTick(T.editBody({ title: 'New', notes: '' }), null, null), { title: 'New', content: '' })
same(T.toTickTick(T.editBody({ dueDay: '' }), null, null), { dueDate: null, startDate: null })
// New / all-day task, local zone: local midnight (Warsaw: UTC+1 on 27 October).
same(T.toTickTick(T.editBody({ dueDay: '2026-10-27' }), null, TZ.toUtc),
	{ isAllDay: true, dueDate: '2026-10-26T23:00:00+0000', startDate: '2026-10-26T23:00:00+0000' })
// All-day in the task's zone.
same(T.toTickTick(T.editBody({ dueDay: '2026-10-28' }), tokyoAllDay, TZ.toUtc),
	{ isAllDay: true, dueDate: '2026-10-27T15:00:00+0000', startDate: '2026-10-27T15:00:00+0000' })
// Round trip through the task's zone.
same(T.tickTickDue(Object.assign({}, tokyoAllDay, T.toTickTick(T.editBody({ dueDay: '2026-10-28' }), tokyoAllDay, TZ.toUtc)), TZ.wallClock),
	{ day: '2026-10-28', time: '' })
// A timed task keeps its local time on the new day (14:00 Warsaw, before and after the switch).
same(T.toTickTick(T.editBody({ dueDay: '2026-10-20' }), { dueDate: '2026-10-27T13:00:00+0000', isAllDay: false }, TZ.toUtc),
	{ isAllDay: false, dueDate: '2026-10-20T12:00:00+0000', startDate: '2026-10-20T12:00:00+0000' })
// A task that spans time (startDate before dueDate) keeps its length when its day moves.
// Timed, 2 h (12:00-14:00 Warsaw on the 27th, after the switch) to the 20th (before it): 12:00-14:00.
same(T.toTickTick(T.editBody({ dueDay: '2026-10-20' }), { startDate: '2026-10-27T11:00:00+0000', dueDate: '2026-10-27T13:00:00+0000', isAllDay: false }, TZ.toUtc),
	{ isAllDay: false, dueDate: '2026-10-20T12:00:00+0000', startDate: '2026-10-20T10:00:00+0000' })
// Only the time changes: the start moves with it.
same(T.toTickTick(T.editBody({ dueTime: '16:00' }), { startDate: '2026-10-27T11:00:00+0000', dueDate: '2026-10-27T13:00:00+0000', isAllDay: false, timeZone: 'Europe/Warsaw' }, TZ.toUtc, { wallClock: TZ.wallClock }),
	{ isAllDay: false, dueDate: '2026-10-27T15:00:00+0000', startDate: '2026-10-27T13:00:00+0000' })
// All-day over three days (27th-29th Warsaw) to the 23rd: 21st-23rd, midnights across the switch.
const span3 = { startDate: '2026-10-26T23:00:00+0000', dueDate: '2026-10-28T23:00:00+0000', isAllDay: true, timeZone: 'Europe/Warsaw' }
same(T.toTickTick(T.editBody({ dueDay: '2026-10-23' }), span3, TZ.toUtc),
	{ isAllDay: true, dueDate: '2026-10-22T22:00:00+0000', startDate: '2026-10-20T22:00:00+0000' })
// All-day span made timed: the start keeps its days, at the due's time.
same(T.toTickTick(T.editBody({ dueDay: '2026-10-29', dueTime: '10:00' }), span3, TZ.toUtc),
	{ isAllDay: false, dueDate: '2026-10-29T09:00:00+0000', startDate: '2026-10-27T09:00:00+0000' })
// Timed over two days made all-day: whole days, at the start of the day.
same(T.toTickTick(T.editBody({ dueDay: '2026-11-05', dueTime: '' }), { startDate: '2026-10-27T20:00:00+0000', dueDate: '2026-10-28T08:00:00+0000', isAllDay: false }, TZ.toUtc),
	{ isAllDay: true, dueDate: '2026-11-04T23:00:00+0000', startDate: '2026-11-03T23:00:00+0000' })
// Timed within one day made all-day: start = due.
same(T.toTickTick(T.editBody({ dueDay: '2026-11-05', dueTime: '' }), { startDate: '2026-10-27T08:00:00+0000', dueDate: '2026-10-27T10:00:00+0000', isAllDay: false }, TZ.toUtc),
	{ isAllDay: true, dueDate: '2026-11-04T23:00:00+0000', startDate: '2026-11-04T23:00:00+0000' })
// Done / not done.
same(T.toTickTick(T.toggleBody(true, new Date(Date.UTC(2026, 9, 26, 8, 0, 0))), null, null),
	{ status: 2, completedTime: '2026-10-26T08:00:00+0000' })
same(T.toTickTick(T.toggleBody(false), null, null), { status: 0 })
// Restore copy (undo a delete).
same(T.toTickTick(T.restoreBody({ title: 'R', notes: 'x', due: '2026-10-27T00:00:00.000Z', isCompleted: false }), null, null),
	{ title: 'R', content: 'x', isAllDay: true, dueDate: '2026-10-26T23:00:00+0000', startDate: '2026-10-26T23:00:00+0000', status: 0 })


//--- Priority, reminders, repeat, subtasks

// priorityOf: 0 / 1 / 3 / 5, from an item or a value.
same([0, 1, 2, 3, 4, 5, 9, -1, 'x', null, undefined, '3'].map(T.priorityOf), [0, 1, 1, 3, 3, 5, 5, 0, 0, 0, 0, 3])
assert.strictEqual(T.priorityOf(task({ priority: 5 })), 5)
assert.strictEqual(T.priorityOf(task({})), 0)

// Priority sort: the highest first, then by due day, then position.
{
	const open = [
		task({ id: 'none-today', due: '2026-10-26T00:00:00.000Z' }),
		task({ id: 'low', priority: 1 }),
		task({ id: 'high-later', priority: 5, due: '2026-11-03T00:00:00.000Z' }),
		task({ id: 'high-today', priority: 5, due: '2026-10-26T00:00:00.000Z' }),
		task({ id: 'medium', priority: 3 }),
	]
	same(T.sortOpenTasks(open, 'priority').map(t => t.id), ['high-today', 'high-later', 'medium', 'low', 'none-today'])
	// Every row builder takes it.
	const lists = [{ id: 'a::1', name: 'L', group: 'a' }]
	const byList = { 'a::1': open }
	same(T.taskRows(lists, byList, false, 'priority').filter(r => r.type === 'task').map(r => r.item.id),
		['high-today', 'high-later', 'medium', 'low', 'none-today'])
	same(T.flatRows(lists, byList, 'priority', false).filter(r => r.type === 'task').map(r => r.item.id),
		['high-today', 'high-later', 'medium', 'low', 'none-today'])
	same(T.dateRows(lists, byList, '2026-10-26', 1, false, 'priority').filter(r => r.type === 'task' && r.section === 'nodate').map(r => r.item.id),
		['medium', 'low'])
}

// subtaskTree: parents then their children (any depth), siblings in the given order.
{
	const items = [
		task({ id: 'c2', parent: 'p' }),
		task({ id: 'p' }),
		task({ id: 'g', parentId: 'c1' }),
		task({ id: 'c1', parent: 'p' }),
		task({ id: 'q' }),
		task({ id: 'orphan', parent: 'gone' }),
		task({ id: 'x', parent: 'y' }), // A loop: shown once each, top level first
		task({ id: 'y', parent: 'x' }),
	]
	same(T.subtaskTree(items).map(r => r.item.id + ':' + r.depth),
		['p:0', 'c2:1', 'c1:1', 'g:2', 'q:0', 'orphan:0', 'x:0', 'y:1'])
	same(T.subtaskTree([]), [])
	same(T.subtaskTree(null), [])
}

// editBody: the new fields only when given, cleaned.
same(T.editBody({ dueTime: '9:05', priority: 4, repeatRule: ' RRULE:FREQ=DAILY ', reminders: [15, '0', 'x', 15], subtasks: [{ id: 's1', title: 'A', done: 1 }, null, { title: 'B' }] }),
	{ dueTime: '09:05', priority: 3, repeatRule: 'RRULE:FREQ=DAILY', reminders: [15, 0], subtasks: [{ id: 's1', title: 'A', done: true }, { id: '', title: 'B', done: false }] })
same(T.editBody({ dueTime: '25:00', repeatRule: null, reminders: null, subtasks: 'x' }), { dueTime: '', repeatRule: '', reminders: [], subtasks: [] })

// googleBody: Google has no time, priority, repeat, reminders or checklist.
same(T.googleBody(T.editBody({ title: 'A', dueDay: '2026-11-01', dueTime: '10:00', priority: 5, repeatRule: 'RRULE:FREQ=DAILY', reminders: [5], subtasks: [] })),
	{ title: 'A', due: '2026-11-01T00:00:00.000Z' })
same(T.googleBody(T.toggleBody(false)), { status: 'needsAction', completed: null })

// restoreBody keeps the parent of a subtask (TickTick parentId, Google parent); Google gets it as a
// query param, never in the body.
same(T.restoreBody({ title: 'S', parentId: 'p1' }).parentId, 'p1')
same(T.restoreBody({ title: 'S', parent: 'g1', parentId: '' }).parentId, 'g1')
assert.strictEqual('parentId' in T.restoreBody({ title: 'S', parentId: '' }), false)
same(T.googleBody(T.restoreBody({ title: 'S', parentId: 'p1' })), { title: 'S', status: 'needsAction' })
same(T.toTickTick(T.restoreBody({ title: 'S', parentId: 'p1' }), null, null), { title: 'S', status: 0 })
// restoreBody keeps TickTick's fields when the copy has them (subtasks as new items).
same(T.restoreBody({ title: 'R', due: '2026-11-01T00:00:00.000Z', dueTime: '10:00', priority: 3, repeatRule: 'RRULE:FREQ=WEEKLY', reminders: [0], subtasks: [{ id: 'old', title: 'S', done: true }] }),
	{ title: 'R', due: '2026-11-01T00:00:00.000Z', status: 'needsAction', dueTime: '10:00', priority: 3, repeatRule: 'RRULE:FREQ=WEEKLY', reminders: [0], subtasks: [{ id: '', title: 'S', done: true }] })

// Reminders: TickTick triggers <-> minutes before due.
same(['TRIGGER:-PT15M', 'TRIGGER:PT0S', 'TRIGGER:P0DT9H0M0S', 'TRIGGER:-P1DT15H0M0S', '-PT1H', 'TRIGGER:-P1W', 'TRIGGER:', 'nonsense', null].map(T.parseTickTickReminder),
	[15, 0, -540, 2340, 60, 10080, null, null, null])
same([15, 0, -540, 2340, 60, 1440].map(T.formatTickTickReminder),
	['TRIGGER:-PT15M', 'TRIGGER:PT0S', 'TRIGGER:PT9H', 'TRIGGER:-P1DT15H', 'TRIGGER:-PT1H', 'TRIGGER:-P1D'])
for (const minutes of [15, 0, -540, 2340, 1441, 30]) {
	assert.strictEqual(T.parseTickTickReminder(T.formatTickTickReminder(minutes)), minutes, 'reminder round trip ' + minutes)
}

// fromTickTick: the new fields.
{
	const raw = {
		title: 'Rich', dueDate: '2026-10-27T13:30:00+0000', isAllDay: false, timeZone: 'Europe/Warsaw', status: 0,
		reminders: ['TRIGGER:PT0S', 'TRIGGER:-PT30M', 'bad', 'TRIGGER:-PT30M'], priority: 5, repeatFlag: 'RRULE:FREQ=DAILY;INTERVAL=1',
		parentId: 'par', items: [{ id: 'i2', title: 'Second', status: 0, sortOrder: 2 }, { id: 'i1', title: 'First', status: 1, sortOrder: 1 }],
	}
	const f = T.fromTickTick(raw, TZ.wallClock)
	same([f.dueTime, f.reminders, f.priority, f.repeatRule, f.parentId], ['14:30', [0, 30], 5, 'RRULE:FREQ=DAILY;INTERVAL=1', 'par'])
	same(f.subtasks, [{ id: 'i1', title: 'First', done: true }, { id: 'i2', title: 'Second', done: false }])

	// toTickTick: back again.
	same(T.toTickTick(T.editBody({ priority: 1, repeatRule: '', reminders: [0, 30] }), raw, TZ.toUtc),
		{ priority: 1, repeatFlag: '', reminders: ['TRIGGER:PT0S', 'TRIGGER:-PT30M'] })
	// Subtasks: the task's own item fields kept by id; a new one after the last.
	const items = T.toTickTick(T.editBody({ subtasks: [{ id: 'i1', title: 'First!', done: false }, { id: 'i2', title: 'Second', done: false }, { title: 'New', done: false }] }), raw, null).items
	same(items, [
		{ id: 'i1', title: 'First!', status: 0, sortOrder: 1 },
		{ id: 'i2', title: 'Second', status: 0, sortOrder: 2 },
		{ title: 'New', status: 0, sortOrder: 3 },
	])
	const checked = T.toTickTick({ subtasks: [{ id: 'i2', title: 'Second', done: true }] }, raw, null).items[0]
	assert.strictEqual(checked.status, 1)
	assert.ok(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+0000$/.test(checked.completedTime), 'checked item: completedTime')

	// Due time: timed on the day at that local time; '' makes it all-day.
	same(T.toTickTick(T.editBody({ dueDay: '2026-10-28', dueTime: '09:15' }), null, TZ.toUtc, { timeZone: 'Europe/Warsaw' }),
		{ isAllDay: false, timeZone: 'Europe/Warsaw', dueDate: '2026-10-28T08:15:00+0000', startDate: '2026-10-28T08:15:00+0000' })
	// The task's own zone is kept (not sent again).
	same(T.toTickTick(T.editBody({ dueDay: '2026-10-28', dueTime: '09:15' }), raw, TZ.toUtc, { timeZone: 'Asia/Tokyo' }),
		{ isAllDay: false, dueDate: '2026-10-28T08:15:00+0000', startDate: '2026-10-28T08:15:00+0000' })
	// Only the time changes: on the task's current day.
	same(T.toTickTick(T.editBody({ dueTime: '18:00' }), raw, TZ.toUtc, { wallClock: TZ.wallClock }),
		{ isAllDay: false, dueDate: '2026-10-27T17:00:00+0000', startDate: '2026-10-27T17:00:00+0000' })
	same(T.toTickTick(T.editBody({ dueTime: '' }), raw, TZ.toUtc, { wallClock: TZ.wallClock }),
		{ isAllDay: true, dueDate: '2026-10-26T23:00:00+0000', startDate: '2026-10-26T23:00:00+0000' })
	// No due day: no time either.
	same(T.toTickTick(T.editBody({ dueTime: '18:00' }), { status: 0 }, TZ.toUtc), {})
	same(T.toTickTick(T.editBody({ dueDay: '', dueTime: '18:00' }), raw, TZ.toUtc), { dueDate: null, startDate: null })
	// Round trip of a timed task.
	same(T.tickTickDue(Object.assign({}, raw, T.toTickTick(T.editBody({ dueDay: '2026-11-02', dueTime: '07:45' }), raw, TZ.toUtc)), TZ.wallClock),
		{ day: '2026-11-02', time: '07:45' })
}
// Without the new fields toTickTick is as before (no priority / items / reminders sent).
same(T.toTickTick(T.editBody({ title: 'Plain' }), { priority: 5, items: [{ id: 'a' }] }, null), { title: 'Plain' })

// priorityKey: the check's color.
same(['x', 0, 1, 2, 3, 4, 5, 9].map(T.priorityKey), ['none', 'none', 'low', 'low', 'medium', 'medium', 'high', 'high'])
assert.strictEqual(T.priorityKey(task({ priority: 5 })), 'high')
assert.strictEqual(T.priorityKey(null), 'none')

// dueTimeOf: only with a due day.
assert.strictEqual(T.dueTimeOf(task({ due: '2026-10-28T00:00:00.000Z', dueTime: '9:05' })), '09:05')
assert.strictEqual(T.dueTimeOf(task({ dueTime: '09:05' })), '', 'undated: no time')
assert.strictEqual(T.dueTimeOf(task({ due: '2026-10-28T00:00:00.000Z', dueTime: '' })), '')
assert.strictEqual(T.dueTimeOf(task({ due: '2026-10-28T00:00:00.000Z', dueTime: '25:00' })), '')

// subtaskProgress
same(T.subtaskProgress(task({ subtasks: [{ id: 'a', done: true }, { id: 'b' }, null, { id: 'c', done: 1 }] })), { done: 2, total: 3 })
same(T.subtaskProgress(task({})), { done: 0, total: 0 })

// capabilities: TickTick has them all, Google none.
same(T.capabilities('TickTick'), { dueTime: true, priority: true, repeat: true, reminders: true, subtasks: true })
same(T.capabilities('GoogleTasks'), { dueTime: false, priority: false, repeat: false, reminders: false, subtasks: false })

// Subtasks in the rows: right under their parent, indented.
{
	const lists = [{ id: 'g::a', name: 'A', group: 'G' }]
	const items = { 'g::a': [
		task({ id: 'kid', parentId: 'p', due: '2026-10-26T00:00:00.000Z', position: '1' }),
		task({ id: 'other', due: '2026-10-26T00:00:00.000Z', position: '0' }),
		task({ id: 'p', due: '2026-10-26T00:00:00.000Z', position: '2' }),
	] }
	same(T.taskRows(lists, items, false, 'due').filter(r => r.type === 'task').map(r => r.item.id + r.depth), ['other0', 'p0', 'kid1'])
	same(T.dateRows(lists, items, '2026-10-26', 1, false).filter(r => r.type === 'task').map(r => r.item.id + r.depth), ['other0', 'p0', 'kid1'])
	same(T.flatRows(lists, items, 'title', false).filter(r => r.type === 'task').map(r => r.item.id + r.depth), ['other0', 'p0', 'kid1'])
	// A parent in another section: its subtask is a top level task there.
	const split = { 'g::a': [task({ id: 'p', due: '2026-10-27T00:00:00.000Z' }), task({ id: 'kid', parentId: 'p', due: '2026-10-26T00:00:00.000Z' })] }
	same(T.dateRows(lists, split, '2026-10-26', 1, false).filter(r => r.type === 'task').map(r => r.item.id + r.depth), ['kid0', 'p0'])
	// dayTaskRows: open ones (with subtasks under them), then the done ones.
	const day = [
		task({ id: 'kid', parentId: 'p', due: '2026-10-26T00:00:00.000Z', position: '1' }),
		task({ id: 'p', due: '2026-10-26T00:00:00.000Z', position: '2' }),
		task({ id: 'done', due: '2026-10-26T00:00:00.000Z', status: 'completed' }),
		task({ id: 'b', due: '2026-10-26T00:00:00.000Z', position: '0' }),
	]
	same(T.dayTaskRows(day, '2026-10-26', '2026-10-26').map(r => r.item.id + r.depth), ['b0', 'p0', 'kid1', 'done0'])
}

// reorderPrevious: the task a dropped one goes after, within its list (and section), else null.
{
	const A = { id: 'g::a' }
	const B = { id: 'g::b' }
	const row = (id, list, section, done) => ({ type: 'task', key: 'task:' + list.id + ':' + id, item: { id: id }, list: list, section: section, done: !!done })
	const rows = [
		{ type: 'section', key: 'section:today', section: 'today' },
		row('a1', A, 'today'), row('a2', A, 'today'), row('b1', B, 'today'), row('a3', A, 'today'),
		{ type: 'section', key: 'section:week', section: 'week' },
		row('a4', A, 'week'),
		row('a5', A, 'today', true),
	]
	assert.strictEqual(T.reorderPrevious(rows, 1, 2, false), 'a2', 'a1 below a2')
	assert.strictEqual(T.reorderPrevious(rows, 1, 2, true), null, 'a1 above a2: where it is')
	assert.strictEqual(T.reorderPrevious(rows, 2, 1, true), '', 'a2 above a1: first')
	assert.strictEqual(T.reorderPrevious(rows, 2, 1, false), null, 'a2 below a1: where it is')
	assert.strictEqual(T.reorderPrevious(rows, 1, 4, false), 'a3')
	assert.strictEqual(T.reorderPrevious(rows, 1, 4, true), 'a2', 'above a3: after a2 (another list\'s task between them)')
	assert.strictEqual(T.reorderPrevious(rows, 1, 3, false), null, 'another list')
	assert.strictEqual(T.reorderPrevious(rows, 1, 6, false), null, 'another section')
	assert.strictEqual(T.reorderPrevious(rows, 1, 0, false), null, 'a header')
	assert.strictEqual(T.reorderPrevious(rows, 1, 1, false), null, 'itself')
	assert.strictEqual(T.reorderPrevious(rows, 1, 7, false), null, 'a done one')
	assert.strictEqual(T.reorderPrevious(rows, 7, 1, false), null, 'a done one dragged')
	assert.strictEqual(T.reorderPrevious(null, 0, 1, false), null)
	// By list: no sections.
	const byList = [{ type: 'list', key: 'list:g::a', list: A }, row('x', A), row('y', A), row('z', A)]
	byList.forEach(r => { delete r.section })
	assert.strictEqual(T.reorderPrevious(byList, 3, 1, true), '')
	assert.strictEqual(T.reorderPrevious(byList, 1, 3, false), 'z')
	assert.strictEqual(T.reorderPrevious(byList, 1, 3, true), 'y')
}

// editorChanges: only what the provider has; a new task's non-empty fields, an existing one's changes.
{
	const all = T.capabilities('TickTick')
	const none = T.capabilities('GoogleTasks')
	const form = { title: 'Buy milk', notes: '', dueDay: '2026-10-28', dueTime: '09:30', priority: 3, repeatRule: 'RRULE:FREQ=DAILY',
		reminders: [15, 0], subtasks: [{ id: '', title: ' Oat ', done: false }, { id: '', title: '  ', done: false }] }
	same(T.editorChanges(null, form, all), { title: 'Buy milk', dueDay: '2026-10-28', dueTime: '09:30', priority: 3,
		repeatRule: 'RRULE:FREQ=DAILY', reminders: [15, 0], subtasks: [{ id: '', title: 'Oat', done: false }] })
	same(T.editorChanges(null, form, none), { title: 'Buy milk', dueDay: '2026-10-28' }, 'Google: none of the TickTick fields')
	same(T.editorChanges(null, { title: 'x', dueDay: '', dueTime: '09:30', repeatRule: 'RRULE:FREQ=DAILY', priority: 0 }, all),
		{ title: 'x', dueDay: '' }, 'no time or repeat without a day')
	const item = task({ title: 'Buy milk', summary: 'Buy milk', notes: 'n', due: '2026-10-28T00:00:00.000Z', dueTime: '09:30', priority: 3,
		repeatRule: 'RRULE:FREQ=DAILY;INTERVAL=1', reminders: [15], subtasks: [{ id: 'a', title: 'Oat', done: false }] })
	const unchanged = { title: 'Buy milk', notes: 'n', dueDay: '2026-10-28', dueTime: '09:30', priority: 3, reminders: [15],
		subtasks: [{ id: 'a', title: 'Oat', done: false }] }
	same(T.editorChanges(item, unchanged, all), {}, 'nothing changed (repeat left out: not touched)')
	same(T.editorChanges(item, Object.assign({}, unchanged, { dueTime: '' }), all), { dueTime: '' }, 'all-day now')
	same(T.editorChanges(item, Object.assign({}, unchanged, { dueDay: '2026-10-29' }), all), { dueDay: '2026-10-29' }, 'day only: keeps its time')
	same(T.editorChanges(item, Object.assign({}, unchanged, { repeatRule: '' }), all), { repeatRule: '' }, 'no repeat')
	same(T.editorChanges(item, Object.assign({}, unchanged, { priority: 5, reminders: [], subtasks: [{ id: 'a', title: 'Oat', done: true }] }), all),
		{ priority: 5, reminders: [], subtasks: [{ id: 'a', title: 'Oat', done: true }] })
	same(T.editorChanges(item, Object.assign({}, unchanged, { title: 'Buy oat milk', priority: 5 }), none), { title: 'Buy oat milk' })
	same(T.editorChanges(item, Object.assign({}, unchanged, { dueDay: '' }), all), { dueDay: '', dueTime: '' }, 'undated: no time')
}

console.log('PASS tasks')
