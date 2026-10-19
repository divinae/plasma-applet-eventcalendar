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

console.log('PASS event_types_rejected')
