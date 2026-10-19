// Google event types: out of office, focus time, working location (package/contents/ui/EventTypes.js).
const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const source = fs.readFileSync(path.join(__dirname, '../package/contents/ui/EventTypes.js'), 'utf8')
	.replace(/^\.pragma library\s*$/m, '')
const T = {}
vm.runInNewContext(source, T)
const plain = (value) => JSON.parse(JSON.stringify(value))

// Types
assert.deepStrictEqual(Array.from(T.FETCHED_TYPES), ['default', 'birthday', 'focusTime', 'fromGmail', 'outOfOffice', 'workingLocation'])
assert.strictEqual(T.eventType({}), 'default')
assert.strictEqual(T.eventType(null), 'default')
assert.ok(T.isOutOfOffice({ eventType: 'outOfOffice' }))
assert.ok(T.isFocusTime({ eventType: 'focusTime' }))
assert.ok(T.isWorkingLocation({ eventType: 'workingLocation' }))
assert.ok(!T.isWorkingLocation({ eventType: 'default' }))

// Working location: type and label
const words = { home: 'Hjemme', office: 'Kontor', custom: 'Annet sted' }
const home = { eventType: 'workingLocation', summary: 'Home', workingLocationProperties: { type: 'homeOffice', homeOffice: {} } }
const office = { eventType: 'workingLocation', summary: 'Office', workingLocationProperties: { type: 'officeLocation', officeLocation: { label: 'Oslo HQ', buildingId: 'b1' } } }
const officeNoLabel = { eventType: 'workingLocation', workingLocationProperties: { type: 'officeLocation', officeLocation: {} } }
const custom = { eventType: 'workingLocation', workingLocationProperties: { type: 'customLocation', customLocation: { label: ' Café ' } } }
const customNoLabel = { eventType: 'workingLocation', workingLocationProperties: { customLocation: {} } }
const noProps = { eventType: 'workingLocation', summary: 'Somewhere' }
assert.deepStrictEqual(plain(T.workingLocation(home)), { type: 'home', label: '' })
assert.deepStrictEqual(plain(T.workingLocation(office)), { type: 'office', label: 'Oslo HQ' })
assert.deepStrictEqual(plain(T.workingLocation(custom)), { type: 'custom', label: 'Café' })
assert.deepStrictEqual(plain(T.workingLocation(customNoLabel)), { type: 'custom', label: '' }, 'type from the sub-object')
assert.deepStrictEqual(plain(T.workingLocation(noProps)), { type: '', label: '' })
assert.strictEqual(T.workingLocationText(home, words), 'Hjemme')
assert.strictEqual(T.workingLocationText(office, words), 'Oslo HQ')
assert.strictEqual(T.workingLocationText(officeNoLabel, words), 'Kontor')
assert.strictEqual(T.workingLocationText(custom, words), 'Café')
assert.strictEqual(T.workingLocationText(customNoLabel, words), 'Annet sted')
assert.strictEqual(T.workingLocationText(noProps, words), 'Somewhere', 'falls back to the title')

// Per-day map
const at = (d, h) => new Date(2026, 9, d, h)
const ev = (base, start, end, extra) => Object.assign({}, base, { startDateTime: start, endDateTime: end }, extra || {})
const key = (d) => 2026 * 10000 + 9 * 100 + d
// splitWorkingLocations: working locations apart from the events, once at parse time.
{
	const data = { items: [{ id: 'a' }, { id: 'w', eventType: 'workingLocation' }, { id: 'o', eventType: 'outOfOffice' }] }
	assert.strictEqual(T.splitWorkingLocations(data), data)
	assert.deepStrictEqual(plain(data.items.map(e => e.id)), ['a', 'o'])
	assert.deepStrictEqual(plain(data.workingLocations.map(e => e.id)), ['w'])
	assert.deepStrictEqual(plain(T.splitWorkingLocations({ items: [] })), { items: [], workingLocations: [] })
	// Split again: the ones found before are kept.
	T.splitWorkingLocations(data)
	assert.deepStrictEqual(plain(data.items.map(e => e.id)), ['a', 'o'])
	assert.deepStrictEqual(plain(data.workingLocations.map(e => e.id)), ['w'])
}

let map = T.workingLocationMap([
	ev(home, at(19, 0), at(20, 0), { start: { date: '2026-10-19' }, recurringEventId: 'r1' }), // all-day, recurring
	ev(home, at(20, 0), at(21, 0), { recurringEventId: 'r1' }),
	ev(office, at(20, 0), at(21, 0)), // single entry wins over the recurring one
	ev(home, at(21, 9), at(21, 12)), // split day: in start order
	ev(custom, at(21, 13), at(21, 17)),
	ev(home, at(21, 14), at(21, 15)), // same text twice: once
	ev(office, at(22, 22), at(23, 2)), // timed across midnight: both days
	ev(custom, at(24, 9), at(24, 17), { status: 'cancelled' }),
	{ eventType: 'default', summary: 'Meeting', startDateTime: at(19, 9), endDateTime: at(19, 10) },
	ev(officeNoLabel, at(25, 9), at(26, 0)), // ends at midnight: one day
], words)
assert.deepStrictEqual(plain(map), {
	[key(19)]: 'Hjemme',
	[key(20)]: 'Oslo HQ',
	[key(21)]: 'Hjemme / Café',
	[key(22)]: 'Oslo HQ',
	[key(23)]: 'Oslo HQ',
	[key(25)]: 'Kontor',
})
// Multi-day all-day entry
map = T.workingLocationMap([ev(home, at(26, 0), at(29, 0))], words)
assert.deepStrictEqual(Object.keys(plain(map)).map(Number), [key(26), key(27), key(28)])
assert.deepStrictEqual(plain(T.workingLocationMap([], words)), {})
assert.deepStrictEqual(plain(T.workingLocationMap(null, words)), {})
assert.deepStrictEqual(plain(T.workingLocationMap([ev(home, new Date('x'), new Date('x'))], words)), {}, 'bad dates')

// Auto-decline
assert.deepStrictEqual(plain(T.autoDecline({ eventType: 'outOfOffice', outOfOfficeProperties: { autoDeclineMode: 'declineAllConflictingInvitations', declineMessage: ' On holiday ' } })), { declines: 'all', message: 'On holiday' })
assert.deepStrictEqual(plain(T.autoDecline({ eventType: 'focusTime', focusTimeProperties: { autoDeclineMode: 'declineOnlyNewConflictingInvitations' } })), { declines: 'new', message: '' })
assert.deepStrictEqual(plain(T.autoDecline({ eventType: 'outOfOffice', outOfOfficeProperties: { autoDeclineMode: 'declineNone', declineMessage: 'x' } })), { declines: '', message: '' })
assert.deepStrictEqual(plain(T.autoDecline({ eventType: 'outOfOffice' })), { declines: '', message: '' })
assert.deepStrictEqual(plain(T.autoDecline({ outOfOfficeProperties: { autoDeclineMode: 'declineAllConflictingInvitations' } })), { declines: '', message: '' }, 'not out of office')

console.log('event_types: ok')
