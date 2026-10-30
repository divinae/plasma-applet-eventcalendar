// The signed-in user's answer to an invitation (package/contents/ui/Shared.js myResponse).
const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const source = fs.readFileSync(path.join(__dirname, '../package/contents/ui/Shared.js'), 'utf8')
	.replace(/^\.pragma library\s*$/m, '')
	.replace(/^\.import .*$/mg, '')
const S = {}
vm.runInNewContext(source, S)

const me = status => ({ email: 'me@example.com', self: true, responseStatus: status })
const boss = { email: 'boss@example.com', organizer: true, responseStatus: 'accepted' }

assert.strictEqual(S.myResponse(null), '', 'no event')
assert.strictEqual(S.myResponse({}), '', 'no attendees')
assert.strictEqual(S.myResponse({ attendees: [boss] }), '', 'not on the guest list')
for (const status of ['needsAction', 'tentative', 'declined', 'accepted']) {
	assert.strictEqual(S.myResponse({ attendees: [boss, me(status)] }), status, status)
}
assert.strictEqual(S.myResponse({ attendees: [Object.assign(me('accepted'), { organizer: true })] }), '',
	'organizer: not an invitation')

// In a ListModel (agenda) the attendees are a nested model with count/get.
const model = list => ({ count: list.length, get: i => list[i] })
assert.strictEqual(S.myResponse({ attendees: model([boss, me('tentative')]) }), 'tentative', 'ListModel attendees')

assert.strictEqual(S.isUnconfirmedResponse('needsAction'), true)
assert.strictEqual(S.isUnconfirmedResponse('tentative'), true)
assert.strictEqual(S.isUnconfirmedResponse('declined'), true)
assert.strictEqual(S.isUnconfirmedResponse('accepted'), false)
assert.strictEqual(S.isUnconfirmedResponse(''), false)

// Declined events left out of the views only when set to Hide.
assert.strictEqual(S.isHiddenDeclined({ attendees: [me('declined')] }, false), true, 'declined, hidden')
assert.strictEqual(S.isHiddenDeclined({ attendees: [me('declined')] }, true), false, 'declined, shown')
assert.strictEqual(S.isHiddenDeclined({ attendees: [me('tentative')] }, false), false, 'maybe stays')
assert.strictEqual(S.isHiddenDeclined({ summary: 'Own' }, false), false, 'not invited stays')

// Calendars hidden with the popup header's toggles.
assert.strictEqual(S.isHiddenCalendar('work', ['work', 'home']), true, 'hidden')
assert.strictEqual(S.isHiddenCalendar('other', ['work']), false, 'shown')
assert.strictEqual(S.isHiddenCalendar('work', []), false, 'nothing hidden')
assert.strictEqual(S.isHiddenCalendar('plasma_EventsColor_9a9cff', ['plasma_Events']), true, 'Akonadi hidden as one: every color too')
assert.strictEqual(S.isHiddenCalendar('plasma_EventsColor_9a9cff', ['plasma_EventsColor_aaaaaa']), false, 'another color')
assert.strictEqual(S.isHiddenCalendar('work', undefined), false, 'no config')
assert.strictEqual(S.isHiddenCalendar('', ['']), false, 'no calendar')

console.log('my_response: ok')
