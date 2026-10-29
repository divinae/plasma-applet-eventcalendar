// The same event in more than one calendar shown once (package/contents/ui/Shared.js duplicateEvents).
const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const source = fs.readFileSync(path.join(__dirname, '../package/contents/ui/Shared.js'), 'utf8')
	.replace(/^\.pragma library\s*$/m, '')
	.replace(/^\.import .*$/mg, '')
const S = {}
vm.runInNewContext(source, S)
const drop = events => Object.keys(S.duplicateEvents(events)).map(Number).sort()

const at = (h) => new Date(2026, 9, 29, h)
const shared = { calendarId: 'team', id: 'x1', iCalUID: 'u1', startDateTime: at(9) }
const mine = { calendarId: 'me', id: 'x1', iCalUID: 'u1', startDateTime: at(9), canEdit: true }
const invited = { calendarId: 'me2', id: 'y1', iCalUID: 'u1', startDateTime: at(9), attendees: [{ self: true, responseStatus: 'accepted' }] }

assert.deepStrictEqual(drop([shared, mine]), [0], 'the copy you can edit is kept')
assert.deepStrictEqual(drop([mine, shared]), [1])
assert.deepStrictEqual(drop([shared, invited]), [0], 'else the one with your answer')
assert.deepStrictEqual(drop([shared, Object.assign({}, shared, { calendarId: 'other' })]), [1], 'else the first')
assert.deepStrictEqual(drop([shared, Object.assign({}, shared, { startDateTime: at(10) })]), [], 'another occurrence')
assert.deepStrictEqual(drop([shared, Object.assign({}, shared)]), [], 'the same calendar: not a copy')
assert.deepStrictEqual(drop([shared, Object.assign({}, shared, { calendarId: 'b', kind: 'tasks#task' })]), [], 'tasks alone')
assert.deepStrictEqual(drop([{ calendarId: 'a', id: 'n1', startDateTime: at(9) }, { calendarId: 'b', id: 'n1', startDateTime: at(9) }]), [1], 'no iCalUID: by id')

// One calendar's copies are separate events, also when another calendar's copy is the best.
const a = { calendarId: 'cal1', id: 'a', iCalUID: 'u2', startDateTime: at(11) }
const b = { calendarId: 'cal2', id: 'b', iCalUID: 'u2', startDateTime: at(11), canEdit: true }
const c = { calendarId: 'cal1', id: 'c', iCalUID: 'u2', startDateTime: at(11) }
assert.deepStrictEqual(drop([a, b, c]), [0, 2], "the other calendar's copies go, both")
// preferred(): a shown calendar's copy first.
assert.deepStrictEqual(Object.keys(S.duplicateEvents([mine, shared], e => e.calendarId === 'team')).map(Number), [0], 'the preferred copy is kept')

console.log('PASS duplicate_events')
