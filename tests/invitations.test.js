// Invitations to answer today (package/contents/ui/Invitations.js).
const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const read = name => fs.readFileSync(path.join(__dirname, '../package/contents/ui', name), 'utf8')
	.replace(/^\.pragma library\s*$/m, '').replace(/^\.import .*$/mg, '')
const Shared = {}
vm.runInNewContext(read('Shared.js'), Shared)
const I = { Shared }
vm.runInNewContext(read('Invitations.js'), I)

const now = new Date(2026, 9, 19, 10, 0)
const me = status => [{ email: 'me@example.com', self: true, responseStatus: status }, { email: 'boss@example.com', organizer: true }]
const ev = (id, h1, h2, status, extra) => Object.assign({
	id, calendarId: 'acct::work', summary: id,
	start: { dateTime: 'x' }, startDateTime: new Date(2026, 9, 19, h1), endDateTime: new Date(2026, 9, 19, h2),
	attendees: me(status),
}, extra || {})
const ids = list => Array.from(list, e => e.id)

const events = [
	ev('later', 14, 15, 'needsAction'),
	ev('soon', 11, 12, 'needsAction'),
	ev('accepted', 11, 12, 'accepted'),
	ev('ended', 8, 9, 'needsAction'),
	ev('now', 9, 11, 'needsAction'),
	ev('tomorrow', 11, 12, 'needsAction', { startDateTime: new Date(2026, 9, 20, 11), endDateTime: new Date(2026, 9, 20, 12) }),
	ev('allday', 0, 0, 'needsAction', { start: { date: '2026-10-19' }, startDateTime: new Date(2026, 9, 19), endDateTime: new Date(2026, 9, 20) }),
	ev('cancelled', 13, 14, 'needsAction', { status: 'cancelled' }),
	ev('mine', 13, 14, 'needsAction', { attendees: [{ email: 'me@example.com', self: true, organizer: true, responseStatus: 'needsAction' }] }),
	ev('noguests', 13, 14, null, { attendees: undefined }),
]
assert.deepStrictEqual(ids(I.pendingToday(events, now, [])), ['now', 'soon', 'later'], 'unanswered today, not ended, by start')

// Once notified (also after a restart: the list is persisted), not again; other days are dropped.
let notified = I.markNotified(['2026-10-18|old'], I.pendingToday(events, now, []), now)
assert.strictEqual(notified.length, 3, 'yesterday dropped')
assert.deepStrictEqual(ids(I.pendingToday(events, now, notified)), [], 'not repeated')
const another = ev('new', 16, 17, 'needsAction')
assert.deepStrictEqual(ids(I.pendingToday(events.concat([another]), now, notified)), ['new'], 'a new one still comes')
assert.strictEqual(I.markNotified(notified, [another], now).length, 4)
assert.strictEqual(I.markNotified(notified, [events[0]], now).length, 3, 'no duplicates')

console.log('invitations: ok')
