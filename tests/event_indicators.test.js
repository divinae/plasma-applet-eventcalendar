// Icons for what an event has set (package/contents/ui/Shared.js eventIndicatorKeys).
const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const source = fs.readFileSync(path.join(__dirname, '../package/contents/ui/Shared.js'), 'utf8')
	.replace(/^\.pragma library\s*$/m, '')
	.replace(/^\.import .*$/mg, '')
const S = {}
vm.runInNewContext(source, S)
const keys = (e, meeting, hide) => Array.from(S.eventIndicatorKeys(e, meeting, hide))

assert.deepStrictEqual(keys(null), [])
assert.deepStrictEqual(keys({ summary: 'Plain' }), [], 'nothing set')
const full = {
	location: 'Café Central',
	description: 'Agenda: <b>plans</b>',
	recurringEventId: 'series1',
	attendees: [{ email: 'me@example.com', self: true }, { email: 'anna@example.com' }],
}
assert.deepStrictEqual(keys(full, true), ['location', 'meeting', 'guests', 'repeat', 'description'], 'all, in order')
assert.deepStrictEqual(keys(full, false, { location: true, description: true }), ['guests', 'repeat'], 'hidden ones left out')
assert.deepStrictEqual(keys({ description: '   ' }), [], 'blank description')
assert.deepStrictEqual(keys({ attendees: [{ email: 'me@example.com', self: true }] }), [], 'only the user: no guests')
assert.deepStrictEqual(keys({ attendees: [{ email: 'room@resource.calendar.google.com', resource: true }] }), [], 'a room is not a guest')
assert.deepStrictEqual(keys({ recurrence: ['RRULE:FREQ=WEEKLY'] }), ['repeat'], 'series master')
// Agenda: attendees as a ListModel.
const model = list => ({ count: list.length, get: i => list[i] })
assert.deepStrictEqual(keys({ attendees: model([{ self: true }, { email: 'sam@example.com' }]) }), ['guests'], 'ListModel attendees')
for (const k of ['location', 'meeting', 'guests', 'repeat', 'description']) {
	assert.ok(S.EVENT_INDICATOR_ICONS[k], 'icon for ' + k)
}
console.log('event_indicators: ok')

// Scaled icons get an even pixel size; others keep theirs.
assert.strictEqual(S.eventIndicatorIconSize('location', 16), 12)
assert.strictEqual(S.eventIndicatorIconSize('location', 22), 16)
assert.strictEqual(S.eventIndicatorIconSize('guests', 16), 16)
assert.strictEqual(S.eventIndicatorIconSize('guests', 13), 13)
console.log('event_indicators sizes: ok')
