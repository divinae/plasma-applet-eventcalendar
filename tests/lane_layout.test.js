// Lanes for multi-day events (package/contents/ui/EventBuckets.js layoutLanes / layoutMonth).
process.env.TZ = 'Europe/Warsaw'

const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

function read(file) {
	return fs.readFileSync(path.join(__dirname, '../package/contents/ui', file), 'utf8')
		.replace(/^\.pragma library\s*$/m, '')
		.replace(/^\.import .*$/mg, '')
}
const Shared = {}
vm.runInNewContext(read('Shared.js'), Shared)
const B = {}
vm.runInNewContext(read('EventBuckets.js') + '\nObject.assign(out, { layoutLanes, layoutTiles, layoutMonth, bucketByDay })', { out: B, Shared, Date })

const d = (day, h, m) => new Date(2026, 9, day, h || 0, m || 0)
function allDay(summary, day, days) {
	const pad = n => String(n).padStart(2, '0')
	return { summary, start: { date: '2026-10-' + pad(day) }, end: { date: '2026-10-' + pad(day + days) }, startDateTime: d(day), endDateTime: d(day + days) }
}
function timed(summary, day1, h1, day2, h2) {
	return { summary, start: { dateTime: '' }, end: { dateTime: '' }, startDateTime: d(day1, h1), endDateTime: d(day2, h2) }
}
// Results come from another realm: compare as plain JSON.
const eq = (actual, expected, msg) => assert.deepStrictEqual(JSON.parse(JSON.stringify(actual)), expected, msg)
const brief = bars => bars.map(b => [b.eventItem.summary, b.first, b.last, b.lane])

//--- layoutLanes (week view all-day row)
const a = { summary: 'A' }, b = { summary: 'B' }, c = { summary: 'C' }, e = { summary: 'E' }, f = { summary: 'F' }
// A: Mon-Wed, B: Tue-Fri (overlaps A), C: Thu (fits under A again), E: Mon (third lane).
let days = [[a, e], [a, b], [a, b], [b, c], [b], [], []]
let r = B.layoutLanes(days, 3)
eq(brief(r.bars), [['A', 0, 2, 0], ['E', 0, 0, 1], ['B', 1, 4, 1], ['C', 3, 3, 0]])
assert.strictEqual(r.laneCount, 2)
eq(r.hiddenPerDay, [0, 0, 0, 0, 0, 0, 0])
// Longer first on the same start day.
r = B.layoutLanes([[e, a], [a], [a]], 3)
eq(brief(r.bars), [['A', 0, 2, 0], ['E', 0, 0, 1]], 'longer bar gets the upper lane')
// Equal bars keep their order.
r = B.layoutLanes([[a, b]], 3)
eq(brief(r.bars), [['A', 0, 0, 0], ['B', 0, 0, 1]])
// Too many lanes: maxRows - 1 lanes shown, the rest counted per day.
days = [[a, b, c, e], [a, b, c, e, f], [f], [], [], [], []]
r = B.layoutLanes(days, 3)
assert.strictEqual(r.laneCount, 5)
eq(brief(r.bars), [['A', 0, 1, 0], ['B', 0, 1, 1]])
eq(r.hiddenPerDay, [2, 3, 1, 0, 0, 0, 0])
// Exactly maxRows lanes all fit.
r = B.layoutLanes([[a, b, c]], 3)
assert.strictEqual(r.bars.length, 3)
eq(r.hiddenPerDay, [0])

//--- layoutMonth
// Monday 28 Sep 2026 .. Sunday 8 Nov 2026: 6 week rows. Europe/Warsaw switches back on 25 Oct.
const dayTimes = []
for (let i = 0; i < 42; i++) {
	dayTimes.push(new Date(2026, 8, 28 + i).getTime())
}
const col = date => dayTimes.indexOf(new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime())
assert.strictEqual(col(d(14)), 16)

const conference = allDay('Conference', 14, 3) // Wed-Fri, week 2
const holiday = allDay('Holiday', 17, 1) // single day: stays in the cell
const vacation = allDay('Vacation', 22, 9) // Thu 22 - Fri 30 Oct: crosses into week 4, over the DST change
const night = timed('Night shift', 15, 22, 16, 6) // crosses midnight: a bar
const untilMidnight = timed('Late', 15, 20, 16, 0) // ends at midnight: single day
const long = timed('Hackathon', 19, 9, 20, 9) // 24 h
const standup = timed('Standup', 14, 9, 14, 10)
let items = [standup, conference, holiday, vacation, night, untilMidnight, long]
let m = B.layoutMonth(items, dayTimes, 7, 4)
eq(m.bars.map(bar => [bar.eventItem.summary, bar.week, bar.first, bar.last, bar.lane, bar.continuesBefore, bar.continuesAfter]), [
	['Conference', 2, 2, 4, 0, false, false],
	['Night shift', 2, 3, 4, 1, false, false],
	['Hackathon', 3, 0, 1, 0, false, false],
	['Vacation', 3, 3, 6, 0, false, true],
	['Vacation', 4, 0, 4, 0, true, false],
])
const vacationBars = m.bars.filter(bar => bar.eventItem === vacation)
assert.strictEqual(vacationBars[0].firstTime, d(22).getTime())
assert.strictEqual(vacationBars[0].lastTime, d(25).getTime())
assert.strictEqual(vacationBars[1].firstTime, d(26).getTime())
assert.strictEqual(vacationBars[1].lastTime, d(30).getTime())
// Single-day events stay in their cells; bars don't.
eq(m.dayEvents[col(d(14))].map(x => x.summary), ['Standup'])
eq(m.dayEvents[col(d(15))].map(x => x.summary), ['Late'])
eq(m.dayEvents[col(d(17))].map(x => x.summary), ['Holiday'])
eq(m.dayEvents[col(d(16))], [])
// Rows reserved for bars: highest lane used on the day + 1.
eq(m.reservedRows.slice(14, 21), [0, 0, 1, 2, 2, 0, 0])
eq(m.reservedRows.slice(21, 35), [1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0])
assert.ok(m.hiddenSpanCount.every(n => n === 0))
assert.strictEqual(m.reservedRows.length, 42)
assert.strictEqual(m.dayEvents.length, 42)

// Busy week: more lanes than fit. With 3 rows per cell, 2 lanes are shown and the third row
// stays free for the day's own events or "+N".
const span = (name, day, n) => allDay(name, day, n)
const s1 = span('S1', 5, 3), s2 = span('S2', 5, 2), s3 = span('S3', 6, 2), s4 = span('S4', 6, 2)
const lunch = timed('Lunch', 6, 12, 6, 13)
m = B.layoutMonth([s1, s2, s3, s4, lunch], dayTimes, 7, 3)
// Week 1 is Mon 5 - Sun 11 Oct.
eq(m.bars.map(bar => [bar.eventItem.summary, bar.week, bar.first, bar.last, bar.lane]), [
	['S1', 1, 0, 2, 0],
	['S2', 1, 0, 1, 1],
])
eq(m.hiddenSpanCount.slice(7, 14), [0, 2, 2, 0, 0, 0, 0])
eq(m.reservedRows.slice(7, 14), [2, 2, 1, 0, 0, 0, 0])
eq(m.dayEvents[col(d(6))].map(x => x.summary), ['Lunch'])

// All lanes fit when the cells under the last lane have nothing else to show.
m = B.layoutMonth([s1, s2, s3], dayTimes, 7, 3)
assert.strictEqual(m.bars.length, 3)
assert.ok(m.hiddenSpanCount.every(n => n === 0))
// ... but not when one of them has its own events (no room for them or "+N").
m = B.layoutMonth([s1, s2, s3, lunch], dayTimes, 7, 3)
assert.strictEqual(m.bars.length, 2)
eq(m.hiddenSpanCount.slice(7, 14), [0, 1, 1, 0, 0, 0, 0])
// No room at all: everything is counted.
m = B.layoutMonth([s1, lunch], dayTimes, 7, 1)
assert.strictEqual(m.bars.length, 0)
eq(m.hiddenSpanCount.slice(7, 10), [1, 1, 1])

// Events outside the grid, events cut at the grid edges, events without times.
const before = allDay('Before', 1, 0) // ends where it starts
const edge = { summary: 'Edge', startDateTime: new Date(2026, 8, 25), endDateTime: new Date(2026, 8, 30), start: { date: '2026-09-25' } }
m = B.layoutMonth([edge, { summary: 'No times' }, before], dayTimes, 7, 4)
eq(m.bars.map(bar => [bar.eventItem.summary, bar.week, bar.first, bar.last, bar.continuesBefore, bar.continuesAfter]), [
	['Edge', 0, 0, 1, true, false],
])
eq(m.dayEvents[col(d(1))].map(x => x.summary), ['Before'])

// bucketByDay is unchanged: every covered day lists the event.
const buckets = B.bucketByDay([conference, night, untilMidnight], dayTimes)
eq(buckets[col(d(15))].map(x => x.summary), ['Conference', 'Late', 'Night shift'])
eq(buckets[col(d(16))].map(x => x.summary), ['Conference', 'Night shift'])

//--- layoutTiles (Day view all-day tiles)
const six = ['a', 'b', 'c', 'd', 'e', 'f'].map(summary => ({ summary }))
const tiles = B.layoutTiles(six, 3, 3)
eq(tiles.bars.map(b => [b.eventItem.summary, b.lane, b.slot]), [['a', 0, 0], ['b', 0, 1], ['c', 0, 2], ['d', 1, 0], ['e', 1, 1], ['f', 1, 2]])
eq([tiles.laneCount, tiles.hiddenCount], [2, 0], 'six: two full rows')
eq([B.layoutTiles(six.slice(0, 4), 3, 3).laneCount, B.layoutTiles(six.slice(0, 4), 3, 3).hiddenCount], [2, 0], 'four: the second row has one')
const many = B.layoutTiles(six.concat(six), 3, 3)
eq([many.bars.length, many.laneCount, many.hiddenCount], [8, 3, 4], 'twelve: eight and +4 in the ninth place')

console.log('lane_layout ok')
