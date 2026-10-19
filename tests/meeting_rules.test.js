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

console.log('meeting_rules ok')
