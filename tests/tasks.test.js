// Fixed zone with daylight saving (Europe/Warsaw switches back on 25 October 2026).
process.env.TZ = 'Europe/Warsaw'

const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const read = file => fs.readFileSync(path.join(__dirname, '../package/contents/ui', file), 'utf8')
	.replace(/^\.pragma library\s*$/m, '').replace(/^\.import .*$/mg, '')
const names = ['isTask', 'isDone', 'dueDay', 'completedDay', 'isOverdue', 'placementDay', 'toggleBody',
	'editBody', 'restoreBody', 'dayString', 'addDays']
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

console.log('PASS tasks')
