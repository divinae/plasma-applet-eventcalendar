process.env.TZ = 'Europe/Warsaw'

const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const source = fs.readFileSync(
	path.join(__dirname, '../package/contents/ui/IcsImport.js'),
	'utf8'
).replace(/^\.pragma library\s*/, '')
const I = {}
vm.runInNewContext(source + '\nObject.assign(I, { googleDate, googleEventBody, importOrder, toDate, lastDay, exceptionCount, errorMessage })', { I, Date, JSON })

function plain(x) {
	return JSON.parse(JSON.stringify(x))
}

// A meeting invitation with a time zone: kept as it is, no guests or organizer.
const meeting = {
	iCalUID: 'meeting-1234@example.com',
	summary: 'Project kickoff',
	start: { dateTime: '2026-10-22T14:00:00+02:00', timeZone: 'Europe/Oslo' },
	end: { dateTime: '2026-10-22T15:00:00+02:00', timeZone: 'Europe/Oslo' },
	allDay: false,
	location: 'Room 4, Oslo office',
	description: 'Agenda',
	attendeeCount: 3,
}
assert.deepStrictEqual(JSON.parse(JSON.stringify(I.googleEventBody(meeting, 'Europe/Warsaw'))), {
	iCalUID: 'meeting-1234@example.com',
	summary: 'Project kickoff',
	start: { dateTime: '2026-10-22T14:00:00+02:00', timeZone: 'Europe/Oslo' },
	end: { dateTime: '2026-10-22T15:00:00+02:00', timeZone: 'Europe/Oslo' },
	description: 'Agenda',
	location: 'Room 4, Oslo office',
})

// All-day, free (TRANSP:TRANSPARENT): dates only, no time zone.
const allDay = {
	iCalUID: 'allday', summary: 'Offsite', allDay: true, transp: 'TRANSPARENT',
	start: { date: '2026-11-02' }, end: { date: '2026-11-04' },
}
assert.deepStrictEqual(JSON.parse(JSON.stringify(I.googleEventBody(allDay, 'Europe/Warsaw'))), {
	iCalUID: 'allday', summary: 'Offsite',
	start: { date: '2026-11-02' }, end: { date: '2026-11-04' },
	transparency: 'transparent',
})
assert.strictEqual(I.lastDay(allDay).getDate(), 3)
assert.strictEqual(I.toDate(allDay.start).getDate(), 2)

// A series: the recurrence lines go along; a UTC offset without a zone name gets the calendar's zone.
const series = {
	iCalUID: 'weekly', summary: 'Standup', allDay: false, 'class': 'PRIVATE',
	start: { dateTime: '2026-10-05T09:30:00-04:00' },
	end: { dateTime: '2026-10-05T10:00:00-04:00' },
	recurrence: [
		'RRULE:FREQ=WEEKLY;UNTIL=20261231T235959Z;BYDAY=MO,WE',
		'EXDATE:20261012T133000Z,20261014T133000Z',
		'EXDATE:20261026T133000Z',
		'X-JUNK:1',
	],
}
const seriesBody = I.googleEventBody(series, 'America/New_York')
assert.deepStrictEqual(plain(seriesBody.recurrence), series.recurrence.slice(0, 3))
assert.strictEqual(seriesBody.start.timeZone, 'America/New_York')
assert.strictEqual(seriesBody.end.timeZone, 'America/New_York')
assert.strictEqual(seriesBody.start.dateTime, '2026-10-05T09:30:00-04:00')
assert.strictEqual(seriesBody.visibility, 'private')
assert.strictEqual(I.exceptionCount(series), 3)
assert.strictEqual(I.exceptionCount(meeting), 0)

// Without a zone, a one-off event with an offset is exact as it is.
const offsetOnly = { iCalUID: 'x', summary: 'x', start: { dateTime: '2026-10-05T09:30:00Z' }, end: { dateTime: '2026-10-05T10:00:00Z' } }
assert.strictEqual('timeZone' in I.googleEventBody(offsetOnly, 'Europe/Warsaw').start, false)

// A floating time (no offset) is in the calendar's time zone.
const floating = { iCalUID: 'f', summary: 'f', start: { dateTime: '2026-11-03T09:00:00' }, end: { dateTime: '2026-11-03T09:30:00' } }
assert.deepStrictEqual(plain(I.googleEventBody(floating, "Europe/Warsaw").start), { dateTime: '2026-11-03T09:00:00', timeZone: 'Europe/Warsaw' })
const floatingStart = I.toDate(floating.start)
assert.strictEqual(floatingStart.getHours(), 9)
assert.strictEqual(I.toDate({ dateTime: '2026-10-22T14:00:00+02:00' }).getTime(), Date.UTC(2026, 9, 22, 12, 0))

// A changed occurrence: originalStartTime, imported after its series.
const moved = {
	iCalUID: 'weekly', summary: 'Standup (moved)',
	start: { dateTime: '2026-10-19T11:00:00-04:00', timeZone: 'America/New_York' },
	end: { dateTime: '2026-10-19T11:30:00-04:00', timeZone: 'America/New_York' },
	recurrenceId: { dateTime: '2026-10-19T09:30:00-04:00', timeZone: 'America/New_York' },
}
assert.deepStrictEqual(plain(I.googleEventBody(moved, "Europe/Warsaw").originalStartTime), moved.recurrenceId)
assert.deepStrictEqual(Array.from(I.importOrder([moved, series, meeting])), [1, 2, 0])

// Error messages.
assert.strictEqual(I.errorMessage('HTTP Error 403', '{"error":{"code":403,"message":"Forbidden"}}', 403), '403: Forbidden')
assert.strictEqual(I.errorMessage({ error: { code: 400, errors: [{ message: 'Invalid start time.' }] } }, null, 400), '400: Invalid start time.')
assert.strictEqual(I.errorMessage('HTTP Error 500', 'not json', 500), 'HTTP Error 500')
assert.strictEqual(I.errorMessage(null, null, 0), 'HTTP 0')

console.log('ics_import tests passed')
