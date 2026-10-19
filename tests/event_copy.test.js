const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const source = fs.readFileSync(path.join(__dirname, '../package/contents/ui/EventCopy.js'), 'utf8')
	.replace(/^\.pragma library\s*/, '')
const out = {}
vm.runInNewContext(source + '\nObject.assign(out, { copyBody })', { out })
const { copyBody } = out

function plain(x) {
	return JSON.parse(JSON.stringify(x))
}

const start = { dateTime: '2026-10-20T08:00:00.000Z', timeZone: 'Europe/Warsaw' }
const end = { dateTime: '2026-10-20T09:00:00.000Z', timeZone: 'Europe/Warsaw' }
const event = {
	id: 'abc', etag: '"1"', iCalUID: 'abc@google.com', htmlLink: 'https://example.com', status: 'confirmed',
	calendarId: 'work', calendarManagerId: 'google', canEdit: true, backgroundColor: '#039be5',
	startDateTime: new Date(), endDateTime: new Date(),
	summary: 'Review', _summary: 'Review', location: 'Room 1', description: 'Notes',
	colorId: 5, transparency: 'transparent', visibility: 'private',
	reminders: { useDefault: false, overrides: [{ method: 'popup', minutes: 10 }] },
	attendees: [{ email: 'me@example.com', self: true }, { email: 'guest@example.com' }],
	hangoutLink: 'https://meet.google.com/abc', conferenceData: { conferenceId: 'abc' },
	attachments: [{ fileUrl: 'https://example.com/f' }],
	recurringEventId: 'series', originalStartTime: { dateTime: '2026-10-19T08:00:00Z' },
	start: { dateTime: '2026-10-19T08:00:00Z' }, end: { dateTime: '2026-10-19T09:00:00Z' },
}
let body = copyBody(event, start, end)
assert.deepStrictEqual(plain(body), {
	summary: 'Review',
	location: 'Room 1',
	description: 'Notes',
	colorId: '5',
	reminders: { useDefault: false, overrides: [{ method: 'popup', minutes: 10 }] },
	transparency: 'transparent',
	visibility: 'private',
	start: start,
	end: end,
})
// Copies, not the same objects.
assert.notStrictEqual(body.reminders, event.reminders)
assert.notStrictEqual(body.start, start)

// Defaults are left out; an untitled event stays untitled.
body = copyBody({ summary: '(No title)', _summary: '', description: '', transparency: 'opaque', visibility: 'default',
	start: { date: '2026-10-19' }, end: { date: '2026-10-20' } }, { date: '2026-10-21' }, { date: '2026-10-22' })
assert.deepStrictEqual(plain(body), { start: { date: '2026-10-21' }, end: { date: '2026-10-22' } })
// No _summary (other parsers): summary.
assert.strictEqual(copyBody({ summary: 'X' }, start, end).summary, 'X')

// Out of office / focus time keep their type and settings; other types become plain events.
body = copyBody({ summary: 'Away', eventType: 'outOfOffice',
	outOfOfficeProperties: { autoDeclineMode: 'declineAllConflictingInvitations', declineMessage: 'Away' } }, start, end)
assert.strictEqual(body.eventType, 'outOfOffice')
assert.deepStrictEqual(plain(body.outOfOfficeProperties), { autoDeclineMode: 'declineAllConflictingInvitations', declineMessage: 'Away' })
body = copyBody({ summary: 'Focus', eventType: 'focusTime' }, start, end)
assert.strictEqual(body.eventType, 'focusTime')
assert.strictEqual(body.focusTimeProperties, undefined)
body = copyBody({ summary: 'Mail', eventType: 'fromGmail' }, start, end)
assert.strictEqual(body.eventType, undefined)
body = copyBody({ summary: 'Event', eventType: 'default' }, start, end)
assert.strictEqual(body.eventType, undefined)

console.log('event copy tests passed')
