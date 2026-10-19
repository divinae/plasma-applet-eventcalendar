// Year view helpers (package/contents/ui/YearCounts.js).
const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const read = name => fs.readFileSync(path.join(__dirname, '../package/contents/ui', name), 'utf8')
	.replace(/^\.pragma library\s*$/m, '').replace(/^\.import .*$/mg, '')
const Y = {}
vm.runInNewContext(read('YearCounts.js'), Y)

const ev = (s, e) => ({ startDateTime: s, endDateTime: e })
const plain = o => JSON.parse(JSON.stringify(o))

// Timed events, two on one day; an all-day event (end exclusive); a multi-day event.
let counts = plain(Y.countsByDay([
	ev(new Date(2026, 9, 19, 9), new Date(2026, 9, 19, 10)),
	ev(new Date(2026, 9, 19, 13), new Date(2026, 9, 19, 14)),
	ev(new Date(2026, 9, 20), new Date(2026, 9, 21)),
	ev(new Date(2026, 9, 22, 22), new Date(2026, 9, 24, 1)),
], 2026))
assert.deepStrictEqual(counts, { '2026-10-19': 2, '2026-10-20': 1, '2026-10-22': 1, '2026-10-23': 1, '2026-10-24': 1 })

// Clipped to the year; events of other years ignored; zero-length events on their start day;
// broken items skipped.
counts = plain(Y.countsByDay([
	ev(new Date(2025, 11, 30), new Date(2026, 0, 2)),
	ev(new Date(2026, 11, 31, 20), new Date(2027, 0, 1, 2)),
	ev(new Date(2025, 5, 1, 9), new Date(2025, 5, 1, 10)),
	ev(new Date(2026, 4, 5, 9), new Date(2026, 4, 5, 9)),
	{ summary: 'no dates' },
	null,
], 2026))
assert.deepStrictEqual(counts, { '2026-1-1': 1, '2026-12-31': 1, '2026-5-5': 1 })

// A month-long event over the March DST change counts every day once.
counts = Y.countsByDay([ev(new Date(2026, 2, 1), new Date(2026, 3, 1))], 2026)
assert.strictEqual(Object.keys(counts).length, 31)
assert.strictEqual(counts['2026-3-29'], 1)
assert.strictEqual(Y.countsByDay(null, 2026) && Object.keys(Y.countsByDay(null, 2026)).length, 0)

// Levels.
assert.deepStrictEqual([0, 1, 2, 3, 4, 9].map(n => Y.level(n)), [0, 1, 2, 2, 3, 3])

// Month grid: October 2026 starts on a Thursday.
let cells = plain(Y.monthCells(2026, 9, 1)) // Monday first
assert.strictEqual(cells.length, 42)
assert.deepStrictEqual(cells.slice(0, 5), [0, 0, 0, 1, 2])
assert.strictEqual(cells[3 + 30], 31)
assert.strictEqual(cells[3 + 31], 0)
cells = plain(Y.monthCells(2026, 9, 0)) // Sunday first
assert.deepStrictEqual(cells.slice(0, 5), [0, 0, 0, 0, 1])
cells = plain(Y.monthCells(2026, 1, 0)) // February 2026 starts on a Sunday
assert.deepStrictEqual(cells.slice(0, 2), [1, 2])
assert.strictEqual(cells.filter(d => d).length, 28)

// Fetch range: the year; the current year also covers the agenda days after today.
const ymd = d => [d.getFullYear(), d.getMonth() + 1, d.getDate()]
let r = Y.fetchRange(2027, new Date(2026, 9, 19), 14)
assert.deepStrictEqual([ymd(r.min), ymd(r.max)], [[2027, 1, 1], [2028, 1, 1]])
r = Y.fetchRange(2026, new Date(2026, 11, 25), 14)
assert.deepStrictEqual([ymd(r.min), ymd(r.max)], [[2026, 1, 1], [2027, 1, 8]])
r = Y.fetchRange(2026, new Date(2026, 5, 1), 14)
assert.deepStrictEqual([ymd(r.min), ymd(r.max)], [[2026, 1, 1], [2027, 1, 1]])

console.log('year_counts ok')
