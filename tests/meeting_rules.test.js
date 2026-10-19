// Auto-join and Do Not Disturb during meetings (package/contents/ui/MeetingRules.js).
const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const read = name => fs.readFileSync(path.join(__dirname, '../package/contents/ui', name), 'utf8')
	.replace(/^\.pragma library\s*$/m, '').replace(/^\.import .*$/mg, '')
const Shared = {}
vm.runInNewContext(read('Shared.js'), Shared)
const Guests = {}
vm.runInNewContext(read('Guests.js'), Guests)
const R = { Shared, Guests }
vm.runInNewContext(read('MeetingRules.js'), R)

const at = (h, m, s) => new Date(2026, 9, 19, h, m || 0, s || 0)
const me = status => [{ email: 'me@example.com', self: true, responseStatus: status }, { email: 'boss@example.com', organizer: true }]
const ev = extra => Object.assign({
	id: 'm', summary: 'Meeting', start: { dateTime: 'x' }, startDateTime: at(10), endDateTime: at(11),
}, extra || {})

//--- Auto-join
assert.strictEqual(R.canAutoJoin(ev({ attendees: me('accepted') }), true), true, 'accepted with a link')
assert.strictEqual(R.canAutoJoin(ev({ attendees: me('accepted') }), false), false, 'no link')
assert.strictEqual(R.canAutoJoin(ev(), true), true, 'own event without guests')
assert.strictEqual(R.canAutoJoin(ev({ attendees: [{ email: 'me@example.com', self: true, organizer: true, responseStatus: 'accepted' }, { email: 'x@example.com' }] }), true), true, 'organizer')
assert.strictEqual(R.canAutoJoin(ev({ attendees: me('tentative') }), true), false, 'maybe')
assert.strictEqual(R.canAutoJoin(ev({ attendees: me('needsAction') }), true), false, 'not answered')
assert.strictEqual(R.canAutoJoin(ev({ attendees: me('declined') }), true), false, 'declined')
assert.strictEqual(R.canAutoJoin(ev({ start: { date: '2026-10-19' } }), true), false, 'all-day')
assert.strictEqual(R.canAutoJoin(ev({ status: 'cancelled' }), true), false, 'cancelled')
assert.strictEqual(R.canAutoJoin(ev({ kind: 'tasks#task' }), true), false, 'task')

//--- Do Not Disturb: which meetings
const link = true
assert.strictEqual(R.isDoNotDisturbMeeting(ev({ attendees: me('accepted') }), !link, true), true, 'accepted, with guests')
assert.strictEqual(R.isDoNotDisturbMeeting(ev(), link, true), true, 'own event with a link')
assert.strictEqual(R.isDoNotDisturbMeeting(ev(), !link, true), false, 'own event without guests or link')
assert.strictEqual(R.isDoNotDisturbMeeting(ev({ attendees: [{ email: 'me@example.com', self: true, responseStatus: 'accepted' }] }), !link, false), false, 'only the user')
assert.strictEqual(R.isDoNotDisturbMeeting(ev({ attendees: me('tentative') }), link, true), false, 'maybe, accepted only')
assert.strictEqual(R.isDoNotDisturbMeeting(ev({ attendees: me('tentative') }), link, false), true, 'maybe, any')
assert.strictEqual(R.isDoNotDisturbMeeting(ev({ attendees: me('needsAction') }), link, false), true, 'unanswered, any')
assert.strictEqual(R.isDoNotDisturbMeeting(ev({ attendees: me('declined') }), link, false), false, 'declined never')
assert.strictEqual(R.isDoNotDisturbMeeting(ev({ attendees: me('accepted'), start: { date: '2026-10-19' } }), link, true), false, 'all-day')
assert.strictEqual(R.isDoNotDisturbMeeting(ev({ attendees: me('accepted'), status: 'cancelled' }), link, true), false, 'cancelled')

//--- Until (KConfig QDateTime: local, no leading zeros)
assert.strictEqual(R.formatUntil(at(9, 5, 7)), '2026,10,19,9,5,7')
assert.strictEqual(R.parseUntil('2026,10,19,11,53,39').getTime(), at(11, 53, 39).getTime())
assert.strictEqual(R.parseUntil('2026-10-19T11:53:39').getTime(), at(11, 53, 39).getTime(), 'ISO')
assert.strictEqual(R.parseUntil(''), null)
assert.strictEqual(R.parseUntil('x,y,z'), null)

const now = at(10)
assert.strictEqual(R.untilToWrite('', at(11), now), '2026,10,19,11,0,0', 'not on: until the end')
assert.strictEqual(R.untilToWrite('2026,10,19,9,0,0', at(11), now), '2026,10,19,11,0,0', 'expired one: until the end')
assert.strictEqual(R.untilToWrite('2026,10,19,10,30,0', at(11), now), '2026,10,19,11,0,0', 'shorter one: extended')
assert.strictEqual(R.untilToWrite('2026,10,19,12,0,0', at(11), now), '', 'longer one: not shortened')
assert.strictEqual(R.untilToWrite('2026,10,19,11,0,0', at(11), now), '', 'same end: nothing to write')
assert.strictEqual(R.untilToWrite('', at(9, 59), now), '', 'meeting over')

assert.strictEqual(R.isOwnUntil('2026,10,19,11,0,0', '2026,10,19,11,0,0'), true)
assert.strictEqual(R.isOwnUntil('2026-10-19T11:00:00', '2026,10,19,11,0,0'), true, 'same time, other format')
assert.strictEqual(R.isOwnUntil('2026,10,19,12,0,0', '2026,10,19,11,0,0'), false, 'changed by the user')
assert.strictEqual(R.isOwnUntil('', '2026,10,19,11,0,0'), false, 'turned off')
assert.strictEqual(R.isOwnUntil('2026,10,19,11,0,0', ''), false, 'widget wrote nothing')

console.log('meeting_rules ok')
