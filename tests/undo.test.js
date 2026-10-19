// Undo after delete / move (package/contents/ui/Undo.js).
const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const source = fs.readFileSync(path.join(__dirname, '../package/contents/ui/Undo.js'), 'utf8')
	.replace(/^\.pragma library\s*$/m, '')
	.replace(/^\.import .*$/mg, '')
const U = {}
vm.runInNewContext(source, U)
const plain = obj => JSON.parse(JSON.stringify(obj))

// A parsed Google event as the widget keeps it.
const parsed = {
	kind: 'calendar#event',
	etag: '"3456"',
	id: 'abc123',
	status: 'confirmed',
	htmlLink: 'https://www.google.com/calendar/event?eid=xyz',
	created: '2026-10-01T10:00:00.000Z',
	updated: '2026-10-02T10:00:00.000Z',
	summary: 'Dentist',
	_summary: 'Dentist',
	description: '',
	location: 'Main St 1',
	creator: { email: 'me@example.com', self: true },
	organizer: { email: 'me@example.com', self: true },
	start: { dateTime: '2026-10-20T09:00:00+02:00', timeZone: 'Europe/Warsaw' },
	end: { dateTime: '2026-10-20T10:00:00+02:00', timeZone: 'Europe/Warsaw' },
	iCalUID: 'abc123@google.com',
	sequence: 2,
	hangoutLink: 'https://meet.google.com/aaa-bbbb-ccc',
	reminders: { useDefault: false, overrides: [{ method: 'popup', minutes: 15 }] },
	attendees: [{ email: 'me@example.com', self: true, responseStatus: 'accepted' }],
	colorId: '5',
	calendarManagerId: 'GoogleCalendar',
	calendarId: 'acc1/primary',
	startDateTime: new Date('2026-10-20T07:00:00Z'),
	endDateTime: new Date('2026-10-20T08:00:00Z'),
	canEdit: true,
	reminderMinutes: 15,
	backgroundColor: '#33b679',
	conflictsWith: [{ summary: 'Standup' }],
}

const copy = plain(U.restoreCopy(parsed))
assert.deepStrictEqual(copy, {
	summary: 'Dentist',
	location: 'Main St 1',
	start: { dateTime: '2026-10-20T09:00:00+02:00', timeZone: 'Europe/Warsaw' },
	end: { dateTime: '2026-10-20T10:00:00+02:00', timeZone: 'Europe/Warsaw' },
	reminders: { useDefault: false, overrides: [{ method: 'popup', minutes: 15 }] },
	attendees: [{ email: 'me@example.com', self: true, responseStatus: 'accepted' }],
	colorId: '5',
}, 'the POST body has no ids, server fields or parser extras')

// The copy is separate from the event.
const copy2 = U.restoreCopy(parsed)
copy2.start.dateTime = 'changed'
assert.strictEqual(parsed.start.dateTime, '2026-10-20T09:00:00+02:00')

// An untitled event: the "(No title)" placeholder isn't sent.
const untitled = U.restoreCopy({ id: 'x', _summary: undefined, summary: '(No title)', start: { date: '2026-10-20' }, end: { date: '2026-10-21' } })
assert.deepStrictEqual(plain(untitled), { start: { date: '2026-10-20' }, end: { date: '2026-10-21' } })
// A description is kept.
assert.strictEqual(U.restoreCopy({ id: 'x', description: 'Bring card' }).description, 'Bring card')
assert.strictEqual(U.restoreCopy(null), null)

// Times to put back after a move: copies of start / end.
const times = U.savedTimes(parsed)
assert.deepStrictEqual(plain(times), {
	start: { dateTime: '2026-10-20T09:00:00+02:00', timeZone: 'Europe/Warsaw' },
	end: { dateTime: '2026-10-20T10:00:00+02:00', timeZone: 'Europe/Warsaw' },
})
times.start.dateTime = 'changed'
assert.strictEqual(parsed.start.dateTime, '2026-10-20T09:00:00+02:00')
assert.deepStrictEqual(plain(U.savedTimes({ start: { date: '2026-10-20' }, end: { date: '2026-10-21' } })),
	{ start: { date: '2026-10-20' }, end: { date: '2026-10-21' } })

console.log('PASS undo')
