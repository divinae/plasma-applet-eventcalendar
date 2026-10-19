const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const source = fs.readFileSync(path.join(__dirname, '../package/contents/ui/FreeSlots.js'), 'utf8')
	.replace(/^\.pragma library\s*/, '')
const F = {}
vm.runInNewContext(source + '\nObject.assign(out, { parseResponse, merge, blocks, freeSlots })', { out: F, Date, Math })
const plain = x => JSON.parse(JSON.stringify(x))

const H = 3600000
const M = 60000
const day = Date.UTC(2026, 9, 20)
const at = (h, m) => day + h * H + (m || 0) * M

// Google's answer: busy times, errors per calendar, ids it doesn't list.
const parsed = F.parseResponse({
	kind: 'calendar#freeBusy',
	calendars: {
		primary: { busy: [
			{ start: '2026-10-20T11:00:00Z', end: '2026-10-20T12:00:00Z' },
			{ start: '2026-10-20T07:00:00Z', end: '2026-10-20T08:30:00Z' },
			{ start: '2026-10-20T08:00:00Z', end: '2026-10-20T09:00:00Z' }, // Overlaps
			{ start: 'bogus', end: '2026-10-20T09:00:00Z' },
		] },
		'anna@example.com': { busy: [] },
		'ext@other.org': { errors: [{ domain: 'global', reason: 'notFound' }] },
		'group@example.com': { errors: [{ domain: 'calendar', reason: 'groupTooBig' }], busy: [] },
	},
}, ['primary', 'anna@example.com', 'ext@other.org', 'group@example.com', 'missing@example.com'])
assert.deepStrictEqual(plain(parsed.primary), { busy: [{ start: at(7), end: at(9) }, { start: at(11), end: at(12) }], error: '' })
assert.deepStrictEqual(plain(parsed['anna@example.com']), { busy: [], error: '' })
assert.strictEqual(parsed['ext@other.org'].error, 'notFound')
assert.strictEqual(parsed['group@example.com'].error, 'groupTooBig')
assert.strictEqual(parsed['missing@example.com'].error, 'notFound')
assert.deepStrictEqual(plain(F.parseResponse(null, ['a'])), { a: { busy: [], error: 'notFound' } })

// Merge: touching intervals join
assert.deepStrictEqual(plain(F.merge([{ start: 3, end: 4 }, { start: 1, end: 2 }, { start: 2, end: 3 }, { start: 6, end: 7 }])),
	[{ start: 1, end: 4 }, { start: 6, end: 7 }])

// Blocks: clipped to the range, as fractions
assert.deepStrictEqual(plain(F.blocks([{ start: at(7), end: at(9) }, { start: at(12), end: at(13) }, { start: at(20), end: at(21) }], at(8), at(18))),
	[{ x: 0, width: 0.1 }, { x: 0.4, width: 0.1 }])
assert.deepStrictEqual(plain(F.blocks([{ start: 0, end: 1 }], 5, 5)), [])

// Free slots of 1 hour, every 30 minutes, 8:00-18:00, for two people.
const me = [{ start: at(7), end: at(9) }, { start: at(11), end: at(12) }]
const anna = [{ start: at(9, 30), end: at(10) }, { start: at(13, 15), end: at(14) }]
const slots = F.freeSlots([me, anna], at(8), at(18), H, 30 * M, 0, 100)
assert.deepStrictEqual(plain(slots).map(s => (s.start - day) / H), [10, 12, 14, 14.5, 15, 15.5, 16, 16.5, 17])
assert.ok(slots.every(s => s.end - s.start === H))
// Limit, and not before a time (now): rounded up to the step
assert.deepStrictEqual(plain(F.freeSlots([me, anna], at(8), at(18), H, 30 * M, at(14, 10), 2)).map(s => (s.start - day) / H), [14.5, 15])
// Nothing free / no duration
assert.deepStrictEqual(plain(F.freeSlots([[{ start: at(0), end: at(24) }]], at(8), at(18), H, 30 * M, 0, 5)), [])
assert.deepStrictEqual(plain(F.freeSlots([], at(8), at(9), 0, 30 * M, 0, 5)), [])
// A slot that just fits at the end of the range
assert.deepStrictEqual(plain(F.freeSlots([[{ start: at(8), end: at(17) }]], at(8), at(18), H, 30 * M, 0, 5)).map(s => (s.start - day) / H), [17])
// 45 minute event between meetings
assert.deepStrictEqual(plain(F.freeSlots([[{ start: at(8), end: at(9) }, { start: at(9, 45), end: at(18) }]], at(8), at(18), 45 * M, 15 * M, 0, 5)).map(s => (s.start - day) / H), [9])

console.log('free slots ok')
