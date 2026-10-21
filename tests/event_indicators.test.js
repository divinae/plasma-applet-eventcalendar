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
// Overlaps another meeting: shown first.
const overlapping = Object.assign({ conflictsWith: [{ summary: 'Standup' }, { summary: '1:1' }] }, full)
assert.deepStrictEqual(keys(overlapping, true), ['conflict', 'location', 'meeting', 'guests', 'repeat', 'description'], 'conflict first')
assert.deepStrictEqual(keys({ conflictsWith: [] }), [], 'no conflicts')
assert.deepStrictEqual(keys({ conflictsWith: model([{ summary: 'Standup' }]) }), ['conflict'], 'ListModel conflicts')
assert.deepStrictEqual(keys(overlapping, false, { conflict: true, location: true }), ['guests', 'repeat', 'description'], 'conflict hidden')
assert.deepStrictEqual(Array.from(S.conflictTitles(overlapping)), ['Standup', '1:1'])
assert.deepStrictEqual(Array.from(S.conflictTitles({ conflictsWith: model([{ summary: 'Standup' }]) })), ['Standup'])
assert.deepStrictEqual(Array.from(S.conflictTitles(null)), [])
// Google event types: their icon first.
assert.deepStrictEqual(keys(Object.assign({ eventType: 'outOfOffice' }, overlapping), true), ['outOfOffice', 'conflict', 'location', 'meeting', 'guests', 'repeat', 'description'], 'out of office first')
assert.deepStrictEqual(keys({ eventType: 'focusTime' }), ['focusTime'])
assert.deepStrictEqual(keys({ eventType: 'focusTime' }, false, { focusTime: true }), [], 'focus time hidden')
assert.deepStrictEqual(keys({ eventType: 'default' }), [])
assert.deepStrictEqual(keys({ attendees: [{ self: true, responseStatus: 'needsAction' }, { email: 'a@example.com' }] }), ['needsAction', 'guests'], 'not answered first')
assert.deepStrictEqual(keys({ attendees: [{ self: true, responseStatus: 'accepted' }] }), [], 'answered: no icon')
assert.deepStrictEqual(keys({ attendees: [{ self: true, responseStatus: 'needsAction' }] }, false, { needsAction: true }), [], 'not answered hidden')
for (const k of ['needsAction', 'outOfOffice', 'focusTime', 'conflict', 'location', 'meeting', 'guests', 'repeat', 'description']) {
	assert.ok(S.EVENT_INDICATOR_ICONS[k], 'icon for ' + k)
}
console.log('event_indicators: ok')

// Scaled icons get an even pixel size; others keep theirs.
assert.strictEqual(S.eventIndicatorIconSize('location', 16), 12)
assert.strictEqual(S.eventIndicatorIconSize('location', 22), 16)
assert.strictEqual(S.eventIndicatorIconSize('guests', 16), 16)
assert.strictEqual(S.eventIndicatorIconSize('guests', 13), 13)
console.log('event_indicators sizes: ok')
