const assert = require('assert')

const cache = require('../package/contents/ui/EventCacheUtil.js')

const NOW = new Date(2026, 9, 16, 12, 0, 0)

function fullEvent(overrides) {
	return Object.assign({
		kind: 'calendar#event',
		id: 'ev1',
		calendarManagerId: 'GoogleCalendar',
		calendarId: 'acc_1::work@example.test',
		summary: 'Standup',
		_summary: 'Standup',
		description: 'Secret agenda, call +47 123',
		location: 'Room 1',
		start: { dateTime: '2026-10-16T09:00:00+02:00', timeZone: 'Europe/Oslo' },
		end: { dateTime: '2026-10-16T09:15:00+02:00', timeZone: 'Europe/Oslo' },
		startDateTime: new Date(2026, 9, 16, 9, 0),
		endDateTime: new Date(2026, 9, 16, 9, 15),
		colorId: '5',
		reminderMinutes: [10, 'x', 0],
		backgroundColor: '#ff0000',
		recurringEventId: 'series1',
		canEdit: true,
		status: 'confirmed',
		htmlLink: 'https://www.google.com/calendar/event?eid=abc',
		hangoutLink: 'https://meet.google.com/abc-defg-hij',
		creator: { email: 'boss@example.test' },
		organizer: { email: 'boss@example.test', displayName: 'Boss' },
		attendees: [
			{ email: 'boss@example.test', responseStatus: 'accepted', organizer: true },
			{ email: 'me@example.test', displayName: 'Me', self: true, responseStatus: 'declined' },
		],
		conferenceData: {
			conferenceId: 'abc-defg-hij',
			entryPoints: [
				{ entryPointType: 'video', uri: 'https://meet.google.com/abc-defg-hij', pin: '1234', passcode: 'pw' },
				{ entryPointType: 'phone', uri: 'tel:+47-123', pin: '999' },
			],
			conferenceSolution: { name: 'Google Meet', iconUri: 'https://x/icon.png' },
		},
		transparency: 'transparent',
		visibility: 'private',
		attachments: [{ title: 'Budget sheet', fileUrl: 'https://drive.google.com/file/d/xyz', mimeType: 'application/pdf', fileId: 'xyz' }],
		conflictsWith: [{ summary: 'Overlapping meeting' }],
		accessToken: 'ya29.must-not-leak',
		extendedProperties: { private: { refreshToken: '1//nope' } },
	}, overrides || {})
}

function fullTask(overrides) {
	return Object.assign({
		kind: 'tasks#task',
		id: 't1',
		calendarId: 'acc_1::tasks1',
		calendarManagerId: 'TickTick',
		title: 'Buy milk',
		summary: 'Buy milk',
		_summary: 'Buy milk',
		notes: 'Private task note',
		description: 'Private task note',
		due: '2026-10-16T00:00:00.000Z',
		dueTime: '14:30',
		status: 'needsAction',
		completed: null,
		priority: 5,
		parentId: 'p0',
		repeatRule: 'RRULE:FREQ=DAILY;INTERVAL=1',
		reminders: [15, 0],
		subtasks: [{ id: 's1', title: 'Checklist secret', done: false }],
		projectId: 'proj1',
		position: '00001',
		backgroundColor: '#00ff00',
		htmlLink: 'https://ticktick.com/webapp/#p/proj1/tasks/t1',
		tickTick: { items: [{ id: 's1', title: 'Checklist secret' }], reminders: ['TRIGGER:-PT15M'] },
		start: { date: '2026-10-16' },
		end: { date: '2026-10-17' },
		startDateTime: new Date(2026, 9, 16),
		accessToken: 'tt-token-must-not-leak',
	}, overrides || {})
}

function sampleCalendars() {
	return {
		'acc_1::work@example.test': { items: [fullEvent()] },
		'acc_1::tasks1': { items: [fullTask()] },
		'plasma_Holidays': { items: [fullEvent({ id: 'holiday' })] },
		'https://example.test/cal.ics': { items: [fullEvent({ id: 'ics' })] },
	}
}

function testWhitelist() {
	const text = cache.serialize(sampleCalendars(), new Date(2026, 9, 1), new Date(2026, 10, 1), NOW)
	for (const word of ['Private task note', 'Checklist secret', 'TRIGGER', 'notes', 'subtasks', 'reminders', 'tt-token', 'webapp', 'description', 'Secret agenda', 'email', 'boss@', 'me@example', 'token', 'Token', 'ya29', '1//nope', 'pin', 'passcode', 'organizer', 'creator', 'iconUri', 'conferenceId', 'displayName', 'conflictsWith', 'Overlapping meeting', 'attachments', 'Budget sheet', 'drive.google.com']) {
		assert.ok(text.indexOf(word) === -1, 'cache contains ' + word)
	}
	const data = JSON.parse(text)
	assert.deepStrictEqual(Object.keys(data.calendars), ['acc_1::work@example.test', 'acc_1::tasks1'])
	// Tasks are cached too (whitelisted: no notes, checklist, reminders or links).
	assert.deepStrictEqual(data.calendars['acc_1::tasks1'], [{
		kind: 'tasks#task', id: 't1', title: 'Buy milk', summary: 'Buy milk',
		start: { date: '2026-10-16' }, end: { date: '2026-10-17' },
		due: '2026-10-16T00:00:00.000Z', dueTime: '14:30', status: 'needsAction', parentId: 'p0',
		repeatRule: 'RRULE:FREQ=DAILY;INTERVAL=1', projectId: 'proj1', backgroundColor: '#00ff00',
		priority: 5, fromCache: true,
	}])
	const event = data.calendars['acc_1::work@example.test'][0]
	assert.deepStrictEqual(Object.keys(event).sort(), [
		'attendees', 'backgroundColor', 'canEdit', 'colorId', 'conferenceData', 'end', 'fromCache', 'hangoutLink',
		'htmlLink', 'id', 'location', 'recurringEventId', 'reminderMinutes', 'start', 'status', 'summary', 'transparency', 'visibility',
	])
	assert.deepStrictEqual(event.attendees, [{ self: true, responseStatus: 'declined' }])
	assert.deepStrictEqual(event.reminderMinutes, [10, 0])
	assert.deepStrictEqual(event.conferenceData, {
		entryPoints: [
			{ entryPointType: 'video', uri: 'https://meet.google.com/abc-defg-hij' },
			{ entryPointType: 'phone', uri: 'tel:+47-123' },
		],
		conferenceSolution: { name: 'Google Meet' },
	})
	assert.deepStrictEqual(event.start, { dateTime: '2026-10-16T09:00:00+02:00', timeZone: 'Europe/Oslo' })
	assert.strictEqual(data.savedAt, NOW.getTime())
	assert.strictEqual(data.dateMin, new Date(2026, 9, 1).getTime())
}

function testEventTypes() {
	const ooo = fullEvent({ eventType: 'outOfOffice', outOfOfficeProperties: { autoDeclineMode: 'declineAllConflictingInvitations', declineMessage: 'Away, ask Ola' } })
	const wl = fullEvent({
		id: 'wl', eventType: 'workingLocation',
		workingLocationProperties: { type: 'officeLocation', officeLocation: { label: 'Oslo HQ', buildingId: 'b-secret', deskId: 'd-7' } },
	})
	// Working locations are kept apart from the events (EventTypes.splitWorkingLocations): stored too.
	const text = cache.serialize({ 'a::c': { items: [ooo], workingLocations: [wl] } }, 0, 0, NOW)
	for (const word of ['Away, ask Ola', 'outOfOfficeProperties', 'b-secret', 'd-7', 'buildingId']) {
		assert.ok(text.indexOf(word) === -1, 'cache contains ' + word)
	}
	const events = JSON.parse(text).calendars['a::c']
	assert.strictEqual(events[0].eventType, 'outOfOffice')
	assert.strictEqual(events[1].eventType, 'workingLocation')
	assert.deepStrictEqual(events[1].workingLocationProperties, { type: 'officeLocation', officeLocation: { label: 'Oslo HQ' } })
	const home = cache.pickEvent(fullEvent({ eventType: 'workingLocation', workingLocationProperties: { type: 'homeOffice', homeOffice: { x: 1 } } }))
	assert.deepStrictEqual(home.workingLocationProperties, { type: 'homeOffice', homeOffice: {} })
}

function testSummaryUsesRawTitle() {
	// GoogleCalendarManager can decorate summary for display; _summary is the real title.
	const text = cache.serialize({ 'a::c': { items: [fullEvent({ summary: '✓ Standup', _summary: 'Standup' })] } }, 0, 0, NOW)
	assert.strictEqual(JSON.parse(text).calendars['a::c'][0].summary, 'Standup')
}

function testRoundTripAndSelection() {
	const text = cache.serialize(sampleCalendars(), new Date(2026, 9, 1), new Date(2026, 10, 1), NOW)
	const all = cache.deserialize(text, NOW)
	assert.strictEqual(all.calendars['acc_1::work@example.test'][0].summary, 'Standup')
	assert.strictEqual(all.dateMax, new Date(2026, 10, 1).getTime())

	const selected = cache.deserialize(text, NOW, function(id) { return id === 'acc_1::tasks1' })
	assert.deepStrictEqual(Object.keys(selected.calendars), ['acc_1::tasks1'])
}

function testTasks() {
	// A done Google task, a task without optional fields; tampered fields dropped on read too.
	const text = cache.serialize({ 'g::L1': { items: [
		fullTask({ id: 'd', calendarManagerId: 'GoogleTasks', status: 'completed', completed: '2026-10-15T10:00:00.000Z', priority: 0, dueTime: '', repeatRule: '', parentId: '' }),
		{ kind: 'tasks#task', id: 'bare', title: '', start: { date: '2026-10-16' }, end: { date: '2026-10-17' } },
		{ kind: 'tasks#task', id: 'nostart' },
	] } }, 0, 0, NOW)
	const tasks = JSON.parse(text).calendars['g::L1']
	assert.deepStrictEqual(tasks.map(t => t.id), ['d', 'bare'])
	assert.strictEqual(tasks[0].completed, '2026-10-15T10:00:00.000Z')
	assert.strictEqual(tasks[0].status, 'completed')
	assert.ok(!('priority' in tasks[0]) && !('dueTime' in tasks[0]) && !('parentId' in tasks[0]))
	assert.deepStrictEqual(Object.keys(tasks[1]).sort(), ['end', 'fromCache', 'id', 'kind', 'start', 'summary', 'title'])

	const tampered = JSON.stringify({ version: cache.VERSION, savedAt: NOW.getTime(), calendars: {
		'tt::p1': [fullTask({ repeatRule: { evil: true } })],
	} })
	const read = cache.deserialize(tampered, NOW).calendars['tt::p1'][0]
	assert.strictEqual(read.notes, undefined)
	assert.strictEqual(read.description, undefined)
	assert.strictEqual(read.subtasks, undefined)
	assert.strictEqual(read.reminders, undefined)
	assert.strictEqual(read.tickTick, undefined)
	assert.strictEqual(read.accessToken, undefined)
	assert.strictEqual(read.repeatRule, undefined, 'repeatRule: a string only')
	assert.strictEqual(read.title, 'Buy milk')
}

function testRejectsOldBrokenOrForeign() {
	const text = cache.serialize(sampleCalendars(), 0, 0, NOW)
	assert.strictEqual(cache.deserialize(text, new Date(NOW.getTime() + cache.MAX_AGE_MS + 1)), null, 'too old')
	assert.strictEqual(cache.deserialize(text, new Date(NOW.getTime() - 60000)), null, 'from the future')
	assert.strictEqual(cache.deserialize('', NOW), null)
	assert.strictEqual(cache.deserialize('{not json', NOW), null)
	assert.strictEqual(cache.deserialize(JSON.stringify({ version: 999, savedAt: NOW.getTime(), calendars: {} }), NOW), null)
}

function testReadIsWhitelistedToo() {
	const tampered = JSON.stringify({
		version: cache.VERSION,
		savedAt: NOW.getTime(),
		calendars: {
			'a::c': [fullEvent()],
			'plasma_Holidays': [fullEvent()],
		},
	})
	const data = cache.deserialize(tampered, NOW)
	assert.deepStrictEqual(Object.keys(data.calendars), ['a::c'])
	const event = data.calendars['a::c'][0]
	assert.strictEqual(event.description, undefined)
	assert.strictEqual(event.accessToken, undefined)
	assert.deepStrictEqual(event.attendees, [{ self: true, responseStatus: 'declined' }])
}

function testSelectedCalendarIds() {
	const ids = cache.selectedCalendarIds([
		{ id: 'acc_1', calendarIdList: ['primary', 'team@group.test'], calendarList: [{ id: 'me@example.test', primary: true }, { id: 'team@group.test' }], tasklistIdList: ['L1'] },
		{ id: 'acc_2', calendarIdList: [], calendarList: [] },
		{ id: 'tt_1', projectIdList: ['inbox', 'p1'] },
		null,
	])
	assert.deepStrictEqual(Object.keys(ids).sort(), ['acc_1::L1', 'acc_1::me@example.test', 'acc_1::primary', 'acc_1::team@group.test', 'tt_1::inbox', 'tt_1::p1'])
}

testWhitelist()
testSummaryUsesRawTitle()
testEventTypes()
testRoundTripAndSelection()
testTasks()
testRejectsOldBrokenOrForeign()
testReadIsWhitelistedToo()
testSelectedCalendarIds()
console.log('event_cache tests passed')
