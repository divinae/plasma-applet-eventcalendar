// Morning agenda (package/contents/ui/DailyAgenda.js).
const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const read = name => fs.readFileSync(path.join(__dirname, '../package/contents/ui', name), 'utf8')
	.replace(/^\.pragma library\s*$/m, '').replace(/^\.import .*$/mg, '')
const Shared = {}
vm.runInNewContext(read('Shared.js'), Shared)
const A = { Shared }
vm.runInNewContext(read('DailyAgenda.js'), A)

// Time setting
assert.strictEqual(A.parseTime('08:00'), 480)
assert.strictEqual(A.parseTime('7:45'), 465)
assert.strictEqual(A.parseTime(600), 600)
assert.strictEqual(A.parseTime('25:00'), 480, 'invalid -> 08:00')
assert.strictEqual(A.parseTime(undefined), 480)

// Once a day, at or after the time (also later that day, eg: computer turned on at noon)
const at = (d, h, m) => new Date(2026, 9, d, h, m)
assert.strictEqual(A.isDue(at(19, 7, 59), 480, ''), false, 'before the time')
assert.strictEqual(A.isDue(at(19, 8, 0), 480, ''), true, 'at the time')
assert.strictEqual(A.isDue(at(19, 12, 30), 480, '2026-10-18'), true, 'later that day, shown yesterday')
assert.strictEqual(A.isDue(at(19, 12, 30), 480, A.dayKey(at(19, 8, 0))), false, 'already shown today')
assert.strictEqual(A.isDue(at(20, 8, 1), 480, '2026-10-19'), true, 'next day')

// Events of the day
const now = at(19, 8, 0)
const me = status => [{ email: 'me@example.com', self: true, responseStatus: status }, { email: 'boss@example.com', organizer: true }]
const ev = (id, h1, m1, extra) => Object.assign({
	id, summary: id, start: { dateTime: 'x' },
	startDateTime: at(19, h1, m1), endDateTime: at(19, h1 + 1, m1),
}, extra || {})
const allDay = (id, d1, d2) => ({ id, summary: id, start: { date: 'x' }, startDateTime: new Date(2026, 9, d1), endDateTime: new Date(2026, 9, d2) })
const titles = s => Array.from(s.items, i => (i.allDay ? 'ALL ' : '') + i.title)

let s = A.summarize([
	ev('Lunch', 12, 0),
	ev('Standup', 9, 30),
	allDay('Holiday', 19, 20),
	allDay('Trip', 17, 21),
	allDay('Yesterday', 18, 19),
	ev('Declined', 10, 0, { attendees: me('declined') }),
	ev('Maybe', 11, 0, { attendees: me('tentative') }),
	ev('Cancelled', 11, 0, { status: 'cancelled' }),
	ev('Task', 11, 0, { kind: 'tasks#task' }),
	ev('Tomorrow', 9, 0, { startDateTime: at(20, 9, 0), endDateTime: at(20, 10, 0) }),
	ev('Standup', 9, 30), // Same event in a second list
], now, 5)
assert.strictEqual(s.count, 5)
assert.deepStrictEqual(titles(s), ['ALL Trip', 'ALL Holiday', 'Standup', 'Maybe', 'Lunch'], 'all-day first, then by time; declined/cancelled/tasks/other days skipped')
assert.strictEqual(s.more, 0)

// More than 5: "+N more"
const many = []
for (let h = 9; h < 17; h++) {
	many.push(ev('E' + h, h, 0))
}
s = A.summarize(many, now, 5)
assert.strictEqual(s.count, 8)
assert.strictEqual(s.items.length, 5)
assert.strictEqual(s.more, 3)

// Nothing planned
s = A.summarize([], now, 5)
assert.strictEqual(s.count, 0)
assert.strictEqual(s.items.length, 0)

console.log('daily_agenda ok')
