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

//--- Tasks
const task = extra => Object.assign({ kind: 'tasks#task', id: 't1', calendarId: 'acc::l1', summary: 'T', status: 'needsAction', due: '2026-10-19T00:00:00.000Z', dueTime: '', reminders: [] }, extra || {})
const tkinds = list => Array.from(list, d => d.kind + ':' + d.minutes)

assert.strictEqual(T.taskDueMs(task()), at(0, 0), 'all-day: 00:00 local of the due day')
assert.strictEqual(T.taskDueMs(task({ dueTime: '14:30' })), at(14, 30))
assert.ok(isNaN(T.taskDueMs(task({ due: null }))), 'undated')

// Who gets a reminder of its own
assert.strictEqual(T.taskHasAlert(task()), false, 'Google: date only -> morning summary')
assert.strictEqual(T.taskHasAlert(task({ dueTime: '14:00' })), true, 'due time')
assert.strictEqual(T.taskHasAlert(task({ reminders: [-540] })), true, 'all-day with a reminder')
assert.strictEqual(T.taskHasAlert(task({ dueTime: '14:00', status: 'completed' })), false, 'done')
assert.strictEqual(T.taskHasAlert(task({ due: null, reminders: [5] })), false, 'undated')

// When: due time; due time minus reminders; all-day counted from 00:00 (-540 = 09:00)
assert.deepStrictEqual(Array.from(T.taskAlertTimes(task({ dueTime: '14:00' })), a => a.at), [at(14, 0)])
assert.deepStrictEqual(Array.from(T.taskAlertTimes(task({ dueTime: '14:00', reminders: [0, 15] })), a => a.at), [at(14, 0), at(13, 45)])
assert.deepStrictEqual(Array.from(T.taskAlertTimes(task({ reminders: [-540, '-540', 'x'] })), a => a.at), [at(9, 0)], 'TickTick all-day 9:00, repeats and junk dropped')
assert.deepStrictEqual(Array.from(T.taskAlertTimes(task({ reminders: [60] })), a => a.at), [at(0, 0) - 3600000], 'the day before, 23:00')

// In the window: once, caught up, never twice
win = T.checkWindow(at(8, 59, 0), at(9, 0, 3), MAX)
assert.deepStrictEqual(tkinds(T.taskDueFor(task({ reminders: [-540] }), win)), ['task:-540'], 'at 9:00')
win = T.checkWindow(at(9, 0, 3), at(9, 0, 50), MAX)
assert.deepStrictEqual(tkinds(T.taskDueFor(task({ reminders: [-540] }), win)), [], 'same minute again')
win = T.checkWindow(at(13, 43, 59), at(13, 46, 0), MAX)
assert.deepStrictEqual(tkinds(T.taskDueFor(task({ dueTime: '14:00', reminders: [15] }), win)), ['task:15'], 'skipped minute caught up')
win = T.checkWindow(at(13, 59), at(14, 0), MAX)
assert.deepStrictEqual(tkinds(T.taskDueFor(task({ dueTime: '14:00', reminders: [15] }), win)), [], 'only the reminders, not the due time too')
assert.deepStrictEqual(tkinds(T.taskDueFor(task({ dueTime: '14:00' }), win)), ['task:0'], 'no reminders: at the due time')
assert.deepStrictEqual(tkinds(T.taskDueFor(task({ dueTime: '14:00', status: 'completed' }), win)), [], 'done: none')
const k1 = T.taskDueFor(task({ dueTime: '14:00' }), win)[0].key
const k2 = T.taskDueFor(task({ dueTime: '14:00', due: '2026-10-20T00:00:00.000Z' }), T.checkWindow(at(13, 59) + 864e5, at(14, 0) + 864e5, MAX))[0].key
assert.notStrictEqual(k1, k2, 'a repeating task due again: a new key')

// The text: Due today / tomorrow / Overdue
assert.strictEqual(T.taskDueState(task({ dueTime: '14:00' }), at(14, 0, 30)).state, 'today', 'at the due minute')
assert.strictEqual(T.taskDueState(task({ dueTime: '14:00' }), at(14, 1)).state, 'overdue')
assert.strictEqual(T.taskDueState(task({ dueTime: '14:00' }), at(14, 0)).timed, true)
assert.strictEqual(T.taskDueState(task({ reminders: [-540] }), at(9, 0)).state, 'today', 'all-day: today all day')
assert.strictEqual(T.taskDueState(task({ reminders: [-540] }), at(23, 59)).state, 'today')
assert.strictEqual(T.taskDueState(task({ reminders: [-540] }), at(0, 0) + 864e5).state, 'overdue', 'next day')
assert.strictEqual(T.taskDueState(task({ reminders: [60] }), at(0, 0) - 3600000).state, 'tomorrow', 'reminder the evening before')
assert.strictEqual(T.taskDueState(task({ due: null }), at(9, 0)).state, 'none')

console.log('notify_timing: ok')
