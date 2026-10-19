// Overlapping meetings (package/contents/ui/Conflicts.js).
const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const read = name => fs.readFileSync(path.join(__dirname, '../package/contents/ui', name), 'utf8')
	.replace(/^\.pragma library\s*$/m, '').replace(/^\.import .*$/mg, '')
const Shared = {}
vm.runInNewContext(read('Shared.js'), Shared)
const C = { Shared }
vm.runInNewContext(read('Conflicts.js'), C)

// Times as hours (with fractions) on 2026-10-19.
const at = h => new Date(2026, 9, 19, Math.floor(h), Math.round((h % 1) * 60))
const ev = (id, h1, h2, extra) => Object.assign({
	id, calendarId: 'acct::work', summary: id,
	start: { dateTime: 'x' }, startDateTime: at(h1), endDateTime: at(h2),
}, extra || {})
const conflicts = events => {
	const found = C.find(events)
	const byId = {}
	for (const e of events) {
		const titles = found[C.eventKey(e)]
		if (titles) {
			byId[e.id] = Array.from(titles).sort()
		}
	}
	return byId
}

assert.deepStrictEqual(conflicts([]), {}, 'nothing')
assert.deepStrictEqual(conflicts([ev('a', 9, 10), ev('b', 11, 12)]), {}, 'apart')
assert.deepStrictEqual(conflicts([ev('a', 9, 10), ev('b', 10, 11)]), {}, 'touching ends')
assert.deepStrictEqual(conflicts([ev('a', 9, 10), ev('b', 9.5, 11)]), { a: ['b'], b: ['a'] }, 'overlap')
assert.deepStrictEqual(conflicts([ev('b', 9.5, 11), ev('a', 9, 10)]), { a: ['b'], b: ['a'] }, 'any order')
assert.deepStrictEqual(conflicts([ev('long', 9, 17), ev('x', 10, 11), ev('y', 13, 14), ev('z', 13.5, 15)]), {
	long: ['x', 'y', 'z'], x: ['long'], y: ['long', 'z'], z: ['long', 'y'],
}, 'several overlaps')
assert.deepStrictEqual(conflicts([ev('a', 9, 10), ev('inside', 9.25, 9.75)]), { a: ['inside'], inside: ['a'] }, 'contained')

// Left out: declined, all-day, free, tasks, cancelled.
const me = status => ({ attendees: [{ email: 'me@example.com', self: true, responseStatus: status }] })
assert.deepStrictEqual(conflicts([ev('a', 9, 10), ev('no', 9, 10, me('declined'))]), {}, 'declined ignored')
assert.deepStrictEqual(conflicts([ev('a', 9, 10), ev('maybe', 9, 10, me('tentative'))]), { a: ['maybe'], maybe: ['a'] }, 'maybe counts')
assert.deepStrictEqual(conflicts([ev('a', 9, 10), ev('day', 0, 0, {
	start: { date: '2026-10-19' }, startDateTime: new Date(2026, 9, 19), endDateTime: new Date(2026, 9, 20),
})]), {}, 'all-day ignored')
assert.deepStrictEqual(conflicts([ev('a', 9, 10), ev('free', 9, 10, { transparency: 'transparent' })]), {}, 'free ignored')
assert.deepStrictEqual(conflicts([ev('a', 9, 10), ev('task', 9, 10, { kind: 'tasks#task' })]), {}, 'task ignored')
assert.deepStrictEqual(conflicts([ev('a', 9, 10), ev('gone', 9, 10, { status: 'cancelled' })]), {}, 'cancelled ignored')
assert.deepStrictEqual(conflicts([ev('a', 9, 10), ev('empty', 9.5, 9.5)]), {}, 'zero length ignored')

// The same meeting in two calendars is not a conflict; same titles are listed once.
assert.deepStrictEqual(conflicts([ev('a', 9, 10), ev('a', 9, 10, { calendarId: 'acct::team' })]), {}, 'same event twice')
assert.deepStrictEqual(conflicts([ev('a', 9, 12), ev('s1', 9, 10, { summary: 'Sync' }), ev('s2', 11, 12, { summary: 'Sync' })]), {
	a: ['Sync'], s1: ['a'], s2: ['a'],
}, 'titles once')

// Keys tell occurrences of a series apart.
assert.notStrictEqual(C.eventKey(ev('a', 9, 10)), C.eventKey(ev('a', 11, 12)))

console.log('conflicts: ok')
