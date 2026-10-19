// Async.settleAll: every task's result, failed ones included, in task order.
const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const source = fs.readFileSync(path.join(__dirname, '../package/contents/ui/lib/Async.js'), 'utf8')
	.replace(/^\.pragma library\s*$/m, '')
	.replace(/^\.import .*$/mg, '')
const A = {}
vm.runInNewContext(source, A)
const plain = x => JSON.parse(JSON.stringify(x))

// No tasks: done right away.
let got = null
A.settleAll([], results => { got = results })
assert.deepStrictEqual(plain(got), [])

// Out of order, one failing: results in task order, done once, after the last.
const callbacks = []
let calls = 0
A.settleAll([
	cb => callbacks.push(() => cb(null, 'a')),
	cb => callbacks.push(() => cb('boom')),
	cb => callbacks.push(() => cb(null, 'c')),
], results => { calls++; got = results })
callbacks[2]()
callbacks[1]()
assert.strictEqual(calls, 0, 'waits for every task')
callbacks[0]()
assert.strictEqual(calls, 1)
assert.deepStrictEqual(plain(got), [
	{ err: null, data: 'a' },
	{ err: 'boom' },
	{ err: null, data: 'c' },
])

// Synchronous tasks, and a task calling back twice.
calls = 0
A.settleAll([
	cb => { cb(null, 1); cb(null, 2) },
	cb => cb(null, 3),
], results => { calls++; got = results })
assert.strictEqual(calls, 1)
assert.deepStrictEqual(plain(got).map(r => r.data), [1, 3])

console.log('PASS async_settle_all')
