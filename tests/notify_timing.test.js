// When event notifications are due (package/contents/ui/NotifyTiming.js).
const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const source = fs.readFileSync(path.join(__dirname, '../package/contents/ui/NotifyTiming.js'), 'utf8')
	.replace(/^\.pragma library\s*$/m, '')
const T = {}
vm.runInNewContext(source, T)

const at = (h, m, s) => new Date(2026, 9, 19, h, m, s || 0).getTime()
const ev = (h, m, extra) => Object.assign({ id: 'e1', calendarId: 'c', startDateTime: new Date(2026, 9, 19, h, m) }, extra || {})
const kinds = list => Array.from(list, d => d.kind + (d.minutes ? ':' + d.minutes : ''))
const MAX = 10 * 60000

// First check: only the current minute.
let win = T.checkWindow(null, at(9, 0, 5), MAX)
assert.deepStrictEqual(kinds(T.dueFor(ev(9, 0), [10], win, at(9, 0, 5))), ['start'], 'starts this minute')
assert.deepStrictEqual(kinds(T.dueFor(ev(9, 1), [10], win, at(9, 0, 5))), [], 'not yet')

// The time engine fired at 8:59:59.9 and then 9:01:00: 9:00 must not be skipped.
win = T.checkWindow(at(8, 59, 59), at(9, 1, 0), MAX)
assert.deepStrictEqual(kinds(T.dueFor(ev(9, 0), [], win, at(9, 1, 0))), ['start'], 'skipped minute caught up')
assert.deepStrictEqual(kinds(T.dueFor(ev(9, 1), [], win, at(9, 1, 0))), ['start'], 'and the current minute')
assert.deepStrictEqual(kinds(T.dueFor(ev(8, 59), [], win, at(9, 1, 0))), [], 'last check covered 8:59')

// Two checks in the same minute: the second covers nothing.
win = T.checkWindow(at(9, 0, 2), at(9, 0, 40), MAX)
assert.deepStrictEqual(kinds(T.dueFor(ev(9, 0), [], win, at(9, 0, 40))), [], 'same minute twice')

// Reminders, also caught up; none once the event started.
win = T.checkWindow(at(8, 49, 59), at(8, 51, 0), MAX)
assert.deepStrictEqual(kinds(T.dueFor(ev(9, 0), [10, 30], win, at(8, 51, 0))), ['reminder:10'], '10 min reminder at 8:50')
win = T.checkWindow(at(9, 4, 0), at(9, 5, 0), MAX)
assert.deepStrictEqual(kinds(T.dueFor(ev(9, 0), [-5, 0], win, at(9, 5, 0))), [], 'no reminder after the start')

// After a long sleep only the last 10 minutes are caught up.
win = T.checkWindow(at(7, 0), at(9, 3, 0), MAX)
assert.deepStrictEqual(kinds(T.dueFor(ev(8, 0), [], win, at(9, 3, 0))), [], 'old start skipped')
assert.deepStrictEqual(kinds(T.dueFor(ev(8, 55), [], win, at(9, 3, 0))), ['start'], 'recent start caught up')

// Keys: per event, start and each reminder; pruning drops day-old ones.
const due = T.dueFor(ev(9, 0), [10], T.checkWindow(at(8, 49), at(8, 51), MAX), at(8, 51)).concat(T.dueFor(ev(9, 0), [10], T.checkWindow(at(8, 59), at(9, 0, 1), MAX), at(9, 0, 1)))
assert.strictEqual(new Set(Array.from(due, d => d.key)).size, 2, 'distinct keys')
const sent = T.pruneSent({ a: at(9, 0), b: at(9, 0) - 25 * 3600000 }, at(9, 1))
assert.deepStrictEqual(Object.keys(sent), ['a'])

console.log('notify_timing: ok')
