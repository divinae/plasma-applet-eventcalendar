// GoogleError.googleErrorBody: Google's JSON error body of a failed request, wherever it is.
const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const source = fs.readFileSync(path.join(__dirname, '../package/contents/ui/lib/GoogleError.js'), 'utf8')
	.replace(/^\.pragma library\s*$/m, '')
	.replace(/^\.import .*$/mg, '')
const G = {}
vm.runInNewContext(source, G)
const { googleErrorBody } = G
const plain = x => JSON.parse(JSON.stringify(x))

const body = { error: { code: 403, message: 'Rate Limit Exceeded', errors: [{ reason: 'rateLimitExceeded', domain: 'usageLimits', message: 'Rate Limit Exceeded' }] } }

// A 2xx answer with an error body: googleRequest makes err the body.
assert.strictEqual(googleErrorBody(body, body), body)
// An HTTP error: err is a string, the body is the response text.
assert.deepStrictEqual(plain(googleErrorBody('HTTP Error 403', JSON.stringify(body))), body)
// Already parsed.
assert.strictEqual(googleErrorBody('HTTP Error 403', body), body)
// No JSON (an HTML page, a timeout, nothing).
assert.strictEqual(googleErrorBody('HTTP Error 502', '<html>Bad Gateway</html>'), null)
assert.strictEqual(googleErrorBody('Timeout', null), null)
assert.strictEqual(googleErrorBody('HTTP Error 0', ''), null)
assert.strictEqual(googleErrorBody(null, undefined), null)
// JSON without an error.
assert.strictEqual(googleErrorBody('HTTP Error 500', '{"items": []}'), null)
assert.strictEqual(googleErrorBody('HTTP Error 500', 'null'), null)
// OAuth style: error is a string. Still the body; callers read error.errors / message.
assert.deepStrictEqual(plain(googleErrorBody('HTTP Error 400', '{"error": "invalid_grant"}')), { error: 'invalid_grant' })

console.log('PASS google_error_body')
