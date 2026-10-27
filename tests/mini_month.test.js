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
