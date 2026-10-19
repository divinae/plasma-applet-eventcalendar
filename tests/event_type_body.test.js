const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const source = fs.readFileSync(path.join(__dirname, '../package/contents/ui/EventTypes.js'), 'utf8')
	.replace(/^\.pragma library\s*$/m, '').replace(/^\.import .*$/mg, '')
const T = {}
vm.runInNewContext(source + '\nObject.assign(out, { isSpecial, properties, applyTo, optionsOf, DECLINE_MODES })', { out: T })
const plain = x => JSON.parse(JSON.stringify(x))

function body() {
	return {
		summary: 'X',
		start: { dateTime: '2026-10-20T08:00:00.000Z' },
		end: { dateTime: '2026-10-20T16:00:00.000Z' },
		location: 'Office',
		transparency: 'transparent',
		attendees: [{ email: 'a@example.com' }],
		conferenceData: { createRequest: {} },
	}
}

// A normal event: unchanged
assert.deepStrictEqual(plain(T.applyTo(body(), 'default', {})), body())
assert.ok(!T.isSpecial('default'))
assert.ok(T.isSpecial('focusTime'))

// Out of office: decline mode and message, no guests / video call / location, busy.
assert.deepStrictEqual(plain(T.applyTo(body(), 'outOfOffice', {
	autoDeclineMode: 'declineOnlyNewConflictingInvitations',
	declineMessage: '  On holiday  ',
	chatStatus: 'available', // Not for out of office
})), {
	summary: 'X',
	start: { dateTime: '2026-10-20T08:00:00.000Z' },
	end: { dateTime: '2026-10-20T16:00:00.000Z' },
	transparency: 'opaque',
	eventType: 'outOfOffice',
	outOfOfficeProperties: { autoDeclineMode: 'declineOnlyNewConflictingInvitations', declineMessage: 'On holiday' },
})
// No auto-decline: no message
assert.deepStrictEqual(plain(T.properties('outOfOffice', { autoDeclineMode: 'declineNone', declineMessage: 'Hi' })),
	{ autoDeclineMode: 'declineNone' })
// Unknown values fall back to the defaults
assert.deepStrictEqual(plain(T.properties('outOfOffice', { autoDeclineMode: 'bogus' })), { autoDeclineMode: 'declineNone' })

// Focus time: chat status
const focus = T.applyTo(body(), 'focusTime', { autoDeclineMode: 'declineAllConflictingInvitations', declineMessage: '', chatStatus: 'available' })
assert.strictEqual(focus.eventType, 'focusTime')
assert.deepStrictEqual(plain(focus.focusTimeProperties), { autoDeclineMode: 'declineAllConflictingInvitations', chatStatus: 'available' })
assert.strictEqual(focus.outOfOfficeProperties, undefined)
assert.strictEqual(focus.attendees, undefined)
assert.deepStrictEqual(plain(T.properties('focusTime', {})), { autoDeclineMode: 'declineNone', chatStatus: 'doNotDisturb' })

// From an event (duplicate)
assert.strictEqual(T.optionsOf({ eventType: 'default' }), null)
assert.strictEqual(T.optionsOf(null), null)
assert.deepStrictEqual(plain(T.optionsOf({ eventType: 'focusTime', focusTimeProperties: { autoDeclineMode: 'declineAllConflictingInvitations', chatStatus: 'available' } })),
	{ type: 'focusTime', autoDeclineMode: 'declineAllConflictingInvitations', declineMessage: '', chatStatus: 'available' })
assert.deepStrictEqual(plain(T.optionsOf({ eventType: 'outOfOffice' })),
	{ type: 'outOfOffice', autoDeclineMode: 'declineNone', declineMessage: '', chatStatus: 'doNotDisturb' })

console.log('event types ok')
