// The Day view's small month: the days with events (package/contents/ui/Shared.js eventDayKeys).
const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const source = fs.readFileSync(path.join(__dirname, '../package/contents/ui/Shared.js'), 'utf8')
	.replace(/^\.pragma library\s*$/m, '')
	.replace(/^\.import .*$/mg, '')
const S = {}
vm.runInNewContext(source, S)

const d = (day, h, m) => new Date(2026, 9, day, h || 0, m || 0)
const key = day => S.dayKey(d(day))
const days = keys => Object.keys(keys).map(Number).sort((a, b) => a - b)
const timed = (day, h1, h2, day2) => ({ startDateTime: d(day, h1), endDateTime: d(day2 || day, h2), start: { dateTime: 'x' } })
const allDay = (day, n) => ({ startDateTime: d(day), endDateTime: d(day + n), start: { date: 'x' } })
const from = d(1)
const to = d(32) // 1 Nov

assert.deepStrictEqual(days(S.eventDayKeys([timed(5, 9, 10)], from, to)), [key(5)], 'a timed event: its day')
assert.deepStrictEqual(days(S.eventDayKeys([allDay(14, 3)], from, to)), [key(14), key(15), key(16)], 'all-day: its days, the end excluded')
assert.deepStrictEqual(days(S.eventDayKeys([timed(20, 22, 2, 21)], from, to)), [key(20), key(21)], 'past midnight: both days')
assert.deepStrictEqual(days(S.eventDayKeys([timed(22, 23, 0, 23)], from, to)), [key(22)], 'ending at midnight: not the next day')
assert.deepStrictEqual(days(S.eventDayKeys([allDay(30, 5)], from, to)), [key(30), key(31)], 'clipped to the range')
assert.deepStrictEqual(days(S.eventDayKeys([{ summary: 'no dates' }, null], from, to)), [], 'items without dates')
assert.deepStrictEqual(days(S.eventDayKeys([], from, to)), [])

// eventDayCounts: how busy each day is (the small month's 1-3 dots).
const counts = S.eventDayCounts([timed(5, 9, 10), timed(5, 12, 13), allDay(5, 2), timed(6, 9, 10)], from, to)
assert.strictEqual(counts[key(5)], 3, 'two timed and an all-day event')
assert.strictEqual(counts[key(6)], 2, "the all-day event's second day and a timed one")
assert.strictEqual(counts[key(7)], undefined)

// upcomingEvents: from a time on, earliest first, at most limit ("Up next", "Next: …").
const later = [timed(29, 9, 10), timed(28, 14, 15), timed(26, 9, 10), timed(28, 9, 10)]
later.forEach((e, i) => { e.id = 'e' + i })
assert.deepStrictEqual(S.upcomingEvents(later, d(28), 0).map(e => e.item.id), ['e3', 'e1', 'e0'], 'sorted, the earlier one left out')
assert.deepStrictEqual(S.upcomingEvents(later, d(28), 2).map(e => e.item.id), ['e3', 'e1'], 'limit')
assert.strictEqual(S.dayKey(S.upcomingEvents(later, d(28), 1)[0].day), key(28), 'the day of its start')
assert.deepStrictEqual(S.upcomingEvents([], d(28), 3), [])
