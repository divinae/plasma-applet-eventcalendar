// Fixed zone with daylight saving (Europe/Warsaw switches back on 25 October 2026).
process.env.TZ = 'Europe/Warsaw'

const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

function load(file, names) {
	const source = fs.readFileSync(path.join(__dirname, '../package/contents/ui', file), 'utf8')
		.replace(/^\.pragma library\s*/, '')
	const out = {}
	vm.runInNewContext(source + '\nObject.assign(out, { ' + names.join(', ') + ' })', { out, Date })
	return out
}
const D = load('WeekDrag.js', ['timeAtY', 'dayIndexAtX', 'moved', 'resized'])
const S = load('SeriesEdit.js', ['shiftedTimes', 'instant'])

const monday = new Date(2026, 9, 12).getTime()
const hourHeight = 40
const firstHour = 7

// timeAtY is the inverse of WeekView.hourY, snapped to 15 minutes.
function hourY(ms, dayStart) {
	return ((ms - dayStart) / 3600000 - firstHour) * hourHeight
}
for (const [h, m] of [[7, 0], [9, 15], [11, 45], [23, 30]]) {
	const t = new Date(2026, 9, 12, h, m)
	assert.strictEqual(D.timeAtY(hourY(t.getTime(), monday), monday, firstHour, hourHeight).getTime(), t.getTime())
}
function snapped(h, m) {
	return D.timeAtY(hourY(new Date(2026, 9, 12, h, m).getTime(), monday), monday, firstHour, hourHeight).getTime()
}
assert.strictEqual(snapped(9, 7), new Date(2026, 9, 12, 9, 0).getTime(), '9:07 snaps to 9:00')
assert.strictEqual(snapped(9, 8), new Date(2026, 9, 12, 9, 15).getTime(), '9:08 snaps to 9:15')
// A daylight saving day: still the wall clock hour under the pointer.
const dstDay = new Date(2026, 9, 25).getTime()
const t = D.timeAtY(3 * hourHeight, dstDay, firstHour, hourHeight)
assert.strictEqual(t.getHours(), 10)
assert.strictEqual(t.getDate(), 25)

// dayIndexAtX, clamped to the shown days.
assert.strictEqual(D.dayIndexAtX(50 + 0, 50, 100, 7), 0)
assert.strictEqual(D.dayIndexAtX(50 + 99, 50, 100, 7), 0)
assert.strictEqual(D.dayIndexAtX(50 + 100, 50, 100, 7), 1)
assert.strictEqual(D.dayIndexAtX(50 + 650, 50, 100, 7), 6)
assert.strictEqual(D.dayIndexAtX(5000, 50, 100, 7), 6)
assert.strictEqual(D.dayIndexAtX(10, 50, 100, 7), 0)
assert.strictEqual(D.dayIndexAtX(400, 50, 300, 1), 0, 'day view: one column')

// moved keeps the duration, resized keeps at least 15 minutes.
const start = new Date(2026, 9, 12, 10, 0)
const end = new Date(2026, 9, 12, 10, 45)
let r = D.moved(start, end, new Date(2026, 9, 14, 11, 15))
assert.strictEqual(r.end.getTime(), new Date(2026, 9, 14, 12, 0).getTime())
r = D.resized(start, end, new Date(2026, 9, 12, 12, 30))
assert.strictEqual(r.start, start)
assert.strictEqual(r.end.getTime(), new Date(2026, 9, 12, 12, 30).getTime())
r = D.resized(start, end, new Date(2026, 9, 12, 9, 0))
assert.strictEqual(r.end.getTime(), new Date(2026, 9, 12, 10, 15).getTime())

// SeriesEdit.shiftedTimes: an occurrence of a weekly series (from Friday 4 September, 9:45 local)
// moved from Friday 16 October 9:45 to Monday 19 October 11:00, 30 min long.
const series = {
	start: { dateTime: '2026-09-04T07:45:00Z', timeZone: 'Europe/Warsaw' },
	end: { dateTime: '2026-09-04T08:00:00Z', timeZone: 'Europe/Warsaw' },
}
let s = S.shiftedTimes(series, new Date(2026, 9, 16, 9, 45),
	{ dateTime: new Date(2026, 9, 19, 11, 0).toISOString() },
	{ dateTime: new Date(2026, 9, 19, 11, 30).toISOString() }, 'UTC')
// 4 September + 3 days = 7 September, 11:00 local (summer time, UTC+2) = 09:00Z.
assert.strictEqual(s.start.dateTime, '2026-09-07T09:00:00.000Z')
assert.strictEqual(s.end.dateTime, '2026-09-07T09:30:00.000Z')
assert.strictEqual(s.start.timeZone, 'Europe/Warsaw', 'keeps the series time zone')
// The occurrence is in winter time, the series start in summer: the local hour still matches.
s = S.shiftedTimes(series, new Date(2026, 9, 30, 9, 45),
	{ dateTime: new Date(2026, 9, 30, 10, 0).toISOString() },
	{ dateTime: new Date(2026, 9, 30, 10, 15).toISOString() }, 'UTC')
assert.strictEqual(new Date(s.start.dateTime).getHours(), 10)
assert.strictEqual(new Date(s.start.dateTime).getDate(), 4)
// No time zone on the series: the calendar's.
s = S.shiftedTimes({ start: { dateTime: '2026-09-04T07:45:00Z' }, end: { dateTime: '2026-09-04T08:00:00Z' } },
	new Date(2026, 9, 16, 9, 45),
	{ dateTime: new Date(2026, 9, 16, 9, 45).toISOString() },
	{ dateTime: new Date(2026, 9, 16, 10, 0).toISOString() }, 'America/New_York')
assert.strictEqual(s.start.timeZone, 'America/New_York')
// All-day: dates only.
s = S.shiftedTimes({ start: { date: '2026-09-04' }, end: { date: '2026-09-05' } },
	new Date(2026, 9, 16), { date: '2026-10-17' }, { date: '2026-10-18' }, 'UTC')
assert.deepStrictEqual(JSON.parse(JSON.stringify(s)), { start: { date: '2026-09-05' }, end: { date: '2026-09-06' } })

// All-day over the spring daylight saving change (29 March 2026 in Warsaw is 23 h long): still
// whole days, never an empty range.
s = S.shiftedTimes({ start: { date: '2026-03-22' }, end: { date: '2026-03-23' } },
	new Date(2026, 2, 28), { date: '2026-03-29' }, { date: '2026-03-30' }, 'UTC')
assert.deepStrictEqual(JSON.parse(JSON.stringify(s)), { start: { date: '2026-03-23' }, end: { date: '2026-03-24' } })
s = S.shiftedTimes({ start: { date: '2026-03-28' }, end: { date: '2026-03-29' } },
	new Date(2026, 3, 4), { date: '2026-04-05' }, { date: '2026-04-06' }, 'UTC')
assert.deepStrictEqual(JSON.parse(JSON.stringify(s)), { start: { date: '2026-03-29' }, end: { date: '2026-03-30' } })
s = S.shiftedTimes({ start: { date: '2026-03-21' }, end: { date: '2026-03-23' } },
	new Date(2026, 2, 28), { date: '2026-03-28' }, { date: '2026-03-30' }, 'UTC')
assert.deepStrictEqual(JSON.parse(JSON.stringify(s)), { start: { date: '2026-03-21' }, end: { date: '2026-03-23' } }, 'two days over the change')

//--- Whole day moves (month view, all-day row)
const W = load('WeekDrag.js', ['canMove', 'dayDelta', 'movedByDays', 'timedTimes'])
// dayDelta counts calendar days, also over the daylight saving change (25 October).
assert.strictEqual(W.dayDelta(new Date(2026, 9, 12), new Date(2026, 9, 12, 23, 59)), 0)
assert.strictEqual(W.dayDelta(new Date(2026, 9, 24), new Date(2026, 9, 26)), 2)
assert.strictEqual(W.dayDelta(new Date(2026, 9, 26).getTime(), new Date(2026, 9, 24).getTime()), -2)
assert.strictEqual(W.dayDelta(new Date(2026, 9, 30), new Date(2026, 10, 2)), 3, 'into the next month')

// A timed event keeps its local time of day across the daylight saving change, and its zone.
const timedEvent = {
	start: { dateTime: new Date(2026, 9, 23, 9, 30).toISOString(), timeZone: 'Europe/Warsaw' },
	end: { dateTime: new Date(2026, 9, 23, 11, 0).toISOString(), timeZone: 'Europe/Warsaw' },
}
let m = W.movedByDays(timedEvent, 3)
assert.strictEqual(m.startDateTime.getTime(), new Date(2026, 9, 26, 9, 30).getTime())
assert.strictEqual(m.endDateTime.getTime(), new Date(2026, 9, 26, 11, 0).getTime())
assert.strictEqual(m.start.dateTime, new Date(2026, 9, 26, 9, 30).toISOString())
assert.strictEqual(m.start.timeZone, 'Europe/Warsaw')
assert.strictEqual(m.end.timeZone, 'Europe/Warsaw')
m = W.movedByDays({ start: { dateTime: '2026-10-12T08:00:00Z' }, end: { dateTime: '2026-10-12T09:00:00Z' } }, -1)
assert.strictEqual(m.start.dateTime, '2026-10-11T08:00:00.000Z')
assert.strictEqual(m.start.timeZone, undefined, 'no zone when the event had none')
// Over midnight: the same duration.
m = W.movedByDays({ start: { dateTime: new Date(2026, 9, 12, 23, 0).toISOString() }, end: { dateTime: new Date(2026, 9, 13, 1, 0).toISOString() } }, 1)
assert.strictEqual(m.endDateTime.getTime(), new Date(2026, 9, 14, 1, 0).getTime())
// All-day events keep their length in days (exclusive end date), over month ends too.
m = W.movedByDays({ start: { date: '2026-10-30' }, end: { date: '2026-11-02' } }, 2)
assert.deepStrictEqual(JSON.parse(JSON.stringify({ start: m.start, end: m.end })), { start: { date: '2026-11-01' }, end: { date: '2026-11-04' } })
assert.strictEqual(m.startDateTime.getTime(), new Date(2026, 10, 1).getTime())
m = W.movedByDays({ start: { date: '2026-10-24' }, end: { date: '2026-10-25' } }, 2)
assert.strictEqual(m.start.date, '2026-10-26')
assert.strictEqual(m.end.date, '2026-10-27')
m = W.movedByDays({ start: { date: '2026-01-01' }, end: { date: '2026-01-02' } }, -1)
assert.strictEqual(m.start.date, '2025-12-31')

// timedTimes keeps the zones.
const tt = W.timedTimes(timedEvent, new Date(2026, 9, 12, 10), new Date(2026, 9, 12, 11))
assert.strictEqual(tt.start.dateTime, new Date(2026, 9, 12, 10).toISOString())
assert.strictEqual(tt.end.timeZone, 'Europe/Warsaw')

// Only editable events, not tasks.
assert.strictEqual(W.canMove({ canEdit: true, start: { date: '2026-10-12' } }), true)
assert.strictEqual(W.canMove({ canEdit: false, start: { date: '2026-10-12' } }), false)
assert.strictEqual(W.canMove({ canEdit: true, kind: 'tasks#task', start: { date: '2026-10-12' } }), false)
assert.strictEqual(W.canMove({ canEdit: true }), false)
assert.strictEqual(W.canMove(null), false)

console.log('week drag tests passed')
