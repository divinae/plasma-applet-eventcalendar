const assert = require('assert')

const events = require('../package/contents/ui/calendars/PlasmaCalendarEventState.js')

function event(id, summary) {
	return {
		id,
		summary,
		start: { date: '2026-05-01' },
		end: { date: '2026-05-02' },
	}
}

const deduped = events.dedupeParsedEvents([
	event('plasma_Holidays_1', 'Loyalty Day'),
	event('plasma_Holidays_1', 'Loyalty Day'),
	event('plasma_Events_1', 'Loyalty Day'),
])

assert.deepStrictEqual(
	deduped.map(item => item.id),
	['plasma_Holidays_1', 'plasma_Events_1']
)

// A Google calendar both synced by Akonadi and signed in to directly: the Akonadi copy goes.
function timed(calendarId, summary, h1, h2) {
	return {
		calendarId,
		summary,
		startDateTime: new Date(2026, 9, 28, h1),
		endDateTime: new Date(2026, 9, 28, h2),
	}
}
const mixed = [
	timed('acct::me@example.com', 'Standup', 9, 10),
	timed('plasma_Events', 'Standup', 9, 10), // Same: duplicate
	timed('plasma_Events', 'Standup', 9, 11), // Other end
	timed('plasma_Events', 'Dentist', 9, 10), // Other title
	timed('plasma_Holidays', 'Standup', 9, 10), // Not Akonadi
	timed('plasma_Events', ' Review ', 14, 15),
	timed('acct::me@example.com', 'Review', 14, 15), // Direct copy listed after
]
assert.deepStrictEqual(events.pimDuplicates(mixed), { 1: true, 5: true })
assert.deepStrictEqual(events.pimDuplicates([timed('plasma_Events', 'Solo', 9, 10)]), {})
// Only the user's own direct events count: not a followed colleague's calendar.
const own = e => e.calendarId === 'acct::me@example.com'
const followed = [
	timed('acct::colleague@example.com', 'Standup', 9, 10),
	timed('plasma_Events', 'Standup', 9, 10),
	timed('acct::me@example.com', 'Review', 14, 15),
	timed('plasma_Events', 'Review', 14, 15),
]
assert.deepStrictEqual(events.pimDuplicates(followed, own), { 3: true }, 'a followed calendar keeps the Akonadi copy')
assert.strictEqual(events.sourceDuplicateKey({ summary: 'No dates' }), '')

console.log('PASS plasma_calendar_event_state')
