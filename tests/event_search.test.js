// Event search helpers (package/contents/ui/EventSearch.js).
const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const source = fs.readFileSync(path.join(__dirname, '../package/contents/ui/EventSearch.js'), 'utf8')
	.replace(/^\.pragma library\s*$/m, '')
const sandbox = { module: { exports: {} } }
vm.runInNewContext(source, sandbox)
const S = sandbox.module.exports

const now = new Date(2026, 9, 16, 10, 0)
function ev(id, summary, start, end, extra) {
	return Object.assign({ id, calendarId: 'cal', summary, startDateTime: start, endDateTime: end }, extra || {})
}
const items = [
	ev('1', 'Team standup', new Date(2026, 9, 16, 9, 30), new Date(2026, 9, 16, 9, 45), { location: 'Google Meet' }),
	ev('2', 'Lunch with Anna', new Date(2026, 9, 16, 12, 30), new Date(2026, 9, 16, 13, 30), { location: 'Café Central' }),
	ev('3', 'Trip to Kraków', new Date(2026, 9, 23), new Date(2026, 9, 26)),
	ev('4', 'Dentist', new Date(2026, 9, 13, 16), new Date(2026, 9, 13, 17), { description: '<b>Bring</b> the insurance card' }),
	ev('5', 'Team retro', new Date(2026, 9, 2, 16), new Date(2026, 9, 2, 17)),
]
const ids = list => Array.from(list, e => e.id) // arrays from the vm context have another Array prototype

assert.deepStrictEqual(ids(S.searchLocal(items, '', now)), [], 'empty query finds nothing')
assert.deepStrictEqual(ids(S.searchLocal(items, '   ', now)), [], 'blank query finds nothing')
assert.deepStrictEqual(ids(S.searchLocal(items, 'ANNA', now)), ['2'], 'case-insensitive title match')
assert.deepStrictEqual(ids(S.searchLocal(items, 'krakow', now)), ['3'], 'diacritics are ignored')
assert.deepStrictEqual(ids(S.searchLocal(items, 'Kraków', now)), ['3'], 'diacritics in the query too')
assert.deepStrictEqual(ids(S.searchLocal(items, 'cafe', now)), ['2'], 'location matches')
assert.deepStrictEqual(ids(S.searchLocal(items, 'insurance', now)), ['4'], 'description matches')
assert.deepStrictEqual(ids(S.searchLocal(items, 'bring insurance', now)), ['4'], 'HTML tags are ignored')
assert.deepStrictEqual(ids(S.searchLocal(items, 'team anna', now)), [], 'all words must match')
assert.deepStrictEqual(ids(S.searchLocal(items, 'team', now)), ['1', '5'], 'past: most recent first')

// Upcoming first (soonest first), then past (most recent first)
assert.deepStrictEqual(ids(S.sortResults(items, now)), ['2', '3', '1', '4', '5'], 'order')

// Merge removes duplicates (same calendar + id) and applies the limit
assert.deepStrictEqual(ids(S.merge([items[1]], [items[1], items[2]], now, 10)), ['2', '3'], 'merge dedupes')
const sameIdOtherCalendar = Object.assign({}, items[1], { calendarId: 'other' })
assert.strictEqual(S.merge([items[1]], [sameIdOtherCalendar], now, 10).length, 2, 'dedupe is per calendar')
assert.strictEqual(S.merge(items, [], now, 2).length, 2, 'limit')

console.log('event_search ok')
