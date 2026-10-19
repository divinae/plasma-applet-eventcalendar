// What the event editor sends (package/contents/ui/EventEdit.js).
const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const read = name => fs.readFileSync(path.join(__dirname, '../package/contents/ui', name), 'utf8')
	.replace(/^\.pragma library\s*$/m, '').replace(/^\.import .*$/mg, '')
const Shared = {}
vm.runInNewContext(read('Shared.js'), Shared)
const E = { Shared }
vm.runInNewContext(read('EventEdit.js'), E)
const plain = value => JSON.parse(JSON.stringify(value))

// Existing event: only changed fields, unset and empty are equal.
const item = { summary: 'Standup', location: undefined, description: 'Notes' }
assert.deepStrictEqual(plain(E.changedFields(item, { summary: 'Standup', location: '', description: 'Notes' })), {})
assert.deepStrictEqual(plain(E.changedFields(item, { summary: 'Standup 2', location: 'Room 4', description: '' })),
	{ summary: 'Standup 2', location: 'Room 4', description: '' })
// Loose comparison: a numeric field equal to its text.
assert.deepStrictEqual(plain(E.changedFields({ colorId: 5 }, { colorId: '5' })), {})

// New event: the non-empty fields, in the given order.
const data = E.changedFields(null, { summary: 'A', start: { date: '2026-10-20' }, end: { date: '2026-10-21' }, location: '', description: 'D' })
assert.deepStrictEqual(Object.keys(data), ['summary', 'start', 'end', 'description'])

// Start / end objects
assert.ok(!E.dateObjChanged({ date: '2026-10-20' }, { date: '2026-10-20' }))
assert.ok(E.dateObjChanged({ date: '2026-10-20' }, { date: '2026-10-21' }))
assert.ok(!E.dateObjChanged({ dateTime: '2026-10-20T10:00:00+02:00' }, { dateTime: '2026-10-20T08:00:00.000Z' }), 'same instant')
assert.ok(E.dateObjChanged({ dateTime: '2026-10-20T10:00:00+02:00' }, { dateTime: '2026-10-20T09:00:00.000Z' }))
assert.ok(E.dateObjChanged(undefined, { dateTime: '2026-10-20T09:00:00.000Z' }))
assert.ok(E.dateObjChanged({ date: '2026-10-20' }, { dateTime: '2026-10-20T09:00:00.000Z' }), 'all day to timed')

const timed = { start: { dateTime: '2026-10-20T10:00:00+02:00' }, end: { dateTime: '2026-10-20T11:00:00+02:00' } }
const same = [{ dateTime: '2026-10-20T08:00:00.000Z' }, { dateTime: '2026-10-20T09:00:00.000Z' }]
assert.ok(!E.timesChanged(timed, false, same[0], same[1]))
assert.ok(E.timesChanged(timed, false, same[0], { dateTime: '2026-10-20T09:30:00.000Z' }), 'end moved')
assert.ok(E.timesChanged(timed, true, { date: '2026-10-20' }, { date: '2026-10-21' }), 'now all day')
const allDay = { start: { date: '2026-10-20' }, end: { date: '2026-10-21' } }
assert.ok(!E.timesChanged(allDay, true, { date: '2026-10-20' }, { date: '2026-10-21' }))

console.log('PASS event_edit')
