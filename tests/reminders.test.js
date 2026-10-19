// An event's own reminders (package/contents/ui/Reminders.js).
const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const source = fs.readFileSync(path.join(__dirname, '../package/contents/ui/Reminders.js'), 'utf8')
	.replace(/^\.pragma library\s*$/m, '')
const R = {}
vm.runInNewContext(source, R)
const plain = value => JSON.parse(JSON.stringify(value))

assert.deepStrictEqual(plain(R.split(10)), { value: 10, unit: 'minutes' })
assert.deepStrictEqual(plain(R.split(90)), { value: 90, unit: 'minutes' })
assert.deepStrictEqual(plain(R.split(120)), { value: 2, unit: 'hours' })
assert.deepStrictEqual(plain(R.split(1440)), { value: 1, unit: 'days' })
assert.deepStrictEqual(plain(R.split(20160)), { value: 2, unit: 'weeks' })
assert.deepStrictEqual(plain(R.split(0)), { value: 0, unit: 'minutes' })
assert.strictEqual(R.toMinutes({ value: 3, unit: 'days' }), 4320)
assert.strictEqual(R.toMinutes({ value: 9, unit: 'weeks' }), 40320, 'capped at 4 weeks')

assert.deepStrictEqual(plain(R.fromEvent({})), { custom: false, items: [], others: [] }, 'no reminders: default')
assert.deepStrictEqual(plain(R.fromEvent({ reminders: { useDefault: true } })).custom, false)
const own = R.fromEvent({ reminders: { useDefault: false, overrides: [
	{ method: 'popup', minutes: 60 }, { method: 'email', minutes: 1440 }, { method: 'popup', minutes: 10 }] } })
assert.deepStrictEqual(plain(own), {
	custom: true,
	items: [{ value: 10, unit: 'minutes' }, { value: 1, unit: 'hours' }],
	others: [{ method: 'email', minutes: 1440 }],
}, 'popups sorted, email kept')
assert.deepStrictEqual(plain(R.toGoogle(own)), { useDefault: false, overrides: [
	{ method: 'popup', minutes: 10 }, { method: 'popup', minutes: 60 }, { method: 'email', minutes: 1440 }] })
assert.deepStrictEqual(plain(R.toGoogle({ custom: false })), { useDefault: true })
assert.deepStrictEqual(plain(R.toGoogle({ custom: true, items: [], others: [] })), { useDefault: false, overrides: [] }, 'no reminders')
assert.deepStrictEqual(plain(R.toGoogle({ custom: true, items: [{ value: 10, unit: 'minutes' }, { value: 10, unit: 'minutes' }], others: [] })).overrides.length, 1, 'duplicates dropped')
const six = { custom: true, items: [1, 2, 3, 4, 5, 6].map(v => ({ value: v, unit: 'minutes' })), others: [] }
assert.strictEqual(R.toGoogle(six).overrides.length, 5, "Google's limit")
assert.strictEqual(R.sameAs(own, R.fromEvent({ reminders: R.toGoogle(own) })), true, 'round trip')
assert.strictEqual(R.sameAs(own, { custom: false }), false)
assert.deepStrictEqual(plain(R.popupMinutes(own)), [10, 60])
assert.strictEqual(R.popupMinutes({ custom: false }), null)

console.log('reminders: ok')
