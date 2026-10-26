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
	'fromTickTick', 'toTickTick', 'withoutTasks', 'sortOpenTasks', 'sortDoneTasks', 'dueInfo', 'firstLine', 'taskRows', 'dayTasks']
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
	same(rows.map(r => r.key), ['group:Work', 'list:g::a', 'task:g::a:2', 'task:g::a:1', 'list:g::b', 'empty:g::b',
		'group:TickTick', 'list:t::x', 'empty:t::x'])
	assert.strictEqual(rows[1].openCount, 2)
	assert.strictEqual(rows[1].doneCount, 1)
	const withDone = T.taskRows(lists, items, true)
	same(withDone.filter(r => r.type === 'task').map(r => r.item.id + (r.done ? '+' : '')), ['2', '1', '3+', '4+'])
	same(T.taskRows([lists[0]], items, false).filter(r => r.type === 'group'), [], 'one account: no heading')
}

// dayTasks: due that day; on today also open overdue and undated ones; done after open.
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
	same(T.dayTasks(items, '2026-10-26', '2026-10-26').map(t => t.id), ['overdue', 'today', 'undated', 'done-today'])
	same(T.dayTasks(items, '2026-10-27', '2026-10-26').map(t => t.id), ['tomorrow'])
	same(T.dayTasks(items, '2026-10-20', '2026-10-26').map(t => t.id), ['overdue'], 'its own day too')
	same(T.dayTasks(null, '2026-10-26', '2026-10-26'), [])
}

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
same(T.fromTickTick({ title: 'A', content: 'n', dueDate: '2026-10-26T23:00:00+0000', isAllDay: true, status: 0 }, TZ.wallClock),
	{ title: 'A', notes: 'n', due: '2026-10-27T00:00:00.000Z', dueTime: '', status: 'needsAction', completed: null })
same(T.fromTickTick({ title: 'B', status: 2, completedTime: '2026-10-25T10:00:00+0000' }, null),
	{ title: 'B', notes: '', due: null, dueTime: '', status: 'completed', completed: '2026-10-25T10:00:00.000Z' })
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
// Done / not done.
same(T.toTickTick(T.toggleBody(true, new Date(Date.UTC(2026, 9, 26, 8, 0, 0))), null, null),
	{ status: 2, completedTime: '2026-10-26T08:00:00+0000' })
same(T.toTickTick(T.toggleBody(false), null, null), { status: 0 })
// Restore copy (undo a delete).
same(T.toTickTick(T.restoreBody({ title: 'R', notes: 'x', due: '2026-10-27T00:00:00.000Z', isCompleted: false }), null, null),
	{ title: 'R', content: 'x', isAllDay: true, dueDate: '2026-10-26T23:00:00+0000', startDate: '2026-10-26T23:00:00+0000', status: 0 })

console.log('PASS tasks')
