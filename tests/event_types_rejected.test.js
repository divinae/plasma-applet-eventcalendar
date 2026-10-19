// GoogleCalendarManager.rejectsEventTypes: only a 400 about the eventTypes parameter makes a
// calendar be fetched without it; other 400s are real errors.
const assert = require('assert')
const fs = require('fs')
const path = require('path')

const source = fs.readFileSync(path.join(__dirname, '../package/contents/ui/calendars/GoogleCalendarManager.qml'), 'utf8')
const start = source.indexOf('function rejectsEventTypes(')
assert.ok(start >= 0, 'rejectsEventTypes is defined')
let depth = 0
let end = source.indexOf('{', start)
for (; end < source.length; end++) {
	if (source[end] === '{') {
		depth++
	} else if (source[end] === '}' && --depth === 0) {
		break
	}
}
function extract(name) {
	const at = source.indexOf('function ' + name + '(')
	assert.ok(at >= 0, name + ' is defined')
	let depth = 0
	let i = source.indexOf('{', at)
	for (; i < source.length; i++) {
		if (source[i] === '{') {
			depth++
		} else if (source[i] === '}' && --depth === 0) {
			break
		}
	}
	return source.slice(at, i + 1)
}
const rejectsEventTypes = new Function(source.slice(start, end + 1) + '\nreturn rejectsEventTypes')()

const body = (error) => JSON.stringify({ error })
assert.strictEqual(rejectsEventTypes(body({ code: 400, message: 'Invalid value for: eventTypes', errors: [{ reason: 'invalid', location: 'eventTypes' }] })), true)
assert.strictEqual(rejectsEventTypes(body({ code: 400, message: 'Bad Request', errors: [{ reason: 'invalidParameter', location: 'eventTypes' }] })), true)
assert.strictEqual(rejectsEventTypes({ error: { message: 'The requested event type is not supported.' } }), true)
assert.strictEqual(rejectsEventTypes(body({ code: 400, message: 'Bad Request', errors: [{ reason: 'timeRangeEmpty', location: 'timeMax' }] })), false)
assert.strictEqual(rejectsEventTypes(body({ code: 400, message: 'Invalid pageToken' })), false)
assert.strictEqual(rejectsEventTypes('<html>Bad Request</html>'), false)
assert.strictEqual(rejectsEventTypes(null), false)
assert.strictEqual(rejectsEventTypes(''), false)

// Paging: a calendar that rejects eventTypes is fetched again from the first page without them
// (a page token of the query with eventTypes is invalid without), keeping only the new pages.
function fetcher(answers) {
	const requests = []
	const Requests = {
		getJSON(req, cb) {
			requests.push(req.url)
			const answer = answers.shift()
			cb(answer.err || null, answer.data, { status: answer.status || 200 })
		},
	}
	const make = new Function('Requests', 'logger', 'EventTypes', 'eventTypesRejected', 'rejectsEventTypes',
		[extract('fetchGCalEvents'), extract('fetchGCalEventsPageResponse'), extract('fetchGCalEventsPage')].join('\n')
		+ '\nreturn fetchGCalEvents')
	const rejected = {}
	const logger = { debug() {}, log() {} }
	const fetch = make(Requests, logger, { FETCHED_TYPES: ['default', 'workingLocation'] }, rejected, rejectsEventTypes)
	return { fetch, requests, rejected }
}
const typesError = { error: { code: 400, message: 'Invalid value for: eventTypes' } }
// Page 1 with types fine, page 2 rejected: restart without types and without the page token.
let f = fetcher([
	{ data: { items: [{ id: 'a' }], nextPageToken: 'typed2' } },
	{ status: 400, err: 'Bad Request', data: typesError },
	{ data: { items: [{ id: 'a' }], nextPageToken: 'plain2' } },
	{ data: { items: [{ id: 'b' }] } },
])
let result = null
f.fetch({ calendarId: 'cal', start: 's', end: 'e', accessToken: 't' }, (err, data) => { result = { err, data } })
assert.strictEqual(result.err, null)
assert.deepStrictEqual(result.data.items.map(e => e.id), ['a', 'b'], 'pages of the rejected query are dropped')
assert.ok(/eventTypes=/.test(f.requests[0]) && /eventTypes=/.test(f.requests[1]))
assert.ok(/pageToken=typed2/.test(f.requests[1]))
assert.ok(!/eventTypes=/.test(f.requests[2]) && !/pageToken=/.test(f.requests[2]), 'restart: first page, no types')
assert.ok(!/eventTypes=/.test(f.requests[3]) && /pageToken=plain2/.test(f.requests[3]))
assert.strictEqual(f.rejected.cal, true)
// Rejected on the first page.
f = fetcher([
	{ status: 400, err: 'Bad Request', data: typesError },
	{ data: { items: [{ id: 'x' }] } },
])
f.fetch({ calendarId: 'cal', start: 's', end: 'e', accessToken: 't' }, (err, data) => { result = { err, data } })
assert.deepStrictEqual(result.data.items.map(e => e.id), ['x'])
assert.strictEqual(f.requests.length, 2)
// Another 400 is an error, not a retry.
f = fetcher([{ status: 400, err: 'Bad Request', data: { error: { code: 400, message: 'Invalid pageToken' } } }])
f.fetch({ calendarId: 'cal', start: 's', end: 'e', accessToken: 't' }, (err, data) => { result = { err, data } })
assert.ok(result.err)
assert.strictEqual(f.requests.length, 1)

console.log('PASS event_types_rejected')
