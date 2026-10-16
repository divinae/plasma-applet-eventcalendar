// Fixed zone, so the UTC UNTIL values below are stable. Warsaw: UTC+1 in winter, UTC+2 in summer.
process.env.TZ = 'Europe/Warsaw'

const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const source = fs.readFileSync(
	path.join(__dirname, '../package/contents/ui/Recurrence.js'),
	'utf8'
).replace(/^\.pragma library\s*/, '')
const R = {}
vm.runInNewContext(source + '\nObject.assign(R, { presetRule, ruleOf, matchPreset, withRule, parseRule, buildRule, endOf, withEnd, untilString, parseUntil, customOf })', { R, Date })

function day(y, m, d) {
	return new Date(y, m - 1, d)
}
function sameDay(a, b) {
	return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
}

const thursday = new Date(2026, 9, 15, 10, 0) // 15 October 2026

// UNTIL formats: a date for all-day events, the end of the local day in UTC for timed ones.
assert.strictEqual(R.untilString(day(2026, 12, 31), true), '20261231')
assert.strictEqual(R.untilString(day(2026, 12, 31), false), '20261231T225959Z')
assert.strictEqual(R.untilString(day(2026, 7, 31), false), '20260731T215959Z')
assert.ok(sameDay(R.parseUntil('20261231'), day(2026, 12, 31)))
assert.ok(sameDay(R.parseUntil('20261231T225959Z'), day(2026, 12, 31)))
assert.ok(sameDay(R.parseUntil('20261231T230000Z'), day(2027, 1, 1)), 'a UTC UNTIL is read as a local day')
assert.ok(sameDay(R.parseUntil('20261231T100000'), day(2026, 12, 31)), 'floating UNTIL')
assert.strictEqual(R.parseUntil('garbage'), null)

// parseRule
let p = R.parseRule('RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE;UNTIL=20261231T225959Z')
assert.strictEqual(p.freq, 'WEEKLY')
assert.strictEqual(p.interval, 2)
assert.deepStrictEqual(Array.from(p.byDay), ['MO', 'WE'])
assert.ok(sameDay(p.until, day(2026, 12, 31)))
assert.strictEqual(p.count, 0)
assert.strictEqual(p.supported, true)

p = R.parseRule('RRULE:FREQ=DAILY;COUNT=5')
assert.strictEqual(p.count, 5)
assert.strictEqual(p.until, null)

for (const rule of [
	'RRULE:FREQ=MONTHLY;BYDAY=3FR',
	'RRULE:FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1',
	'RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=-1SU',
	'RRULE:FREQ=HOURLY',
	'RRULE:FREQ=DAILY;BYDAY=MO',
]) {
	assert.strictEqual(R.parseRule(rule).supported, false, rule + ' must not be editable as custom')
}

// buildRule round trips, timed and all-day.
for (const [rule, allDay] of [
	['RRULE:FREQ=DAILY', false],
	['RRULE:FREQ=DAILY;INTERVAL=3;COUNT=10', false],
	['RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE,FR;UNTIL=20261231T225959Z', false],
	['RRULE:FREQ=WEEKLY;BYDAY=TU;UNTIL=20270115', true],
	['RRULE:FREQ=MONTHLY;BYMONTHDAY=15;COUNT=12', false],
	['RRULE:FREQ=YEARLY;INTERVAL=2', true],
]) {
	assert.strictEqual(R.buildRule(R.parseRule(rule), allDay), rule)
}
// Days come out in week order, whatever order they were picked in.
assert.strictEqual(
	R.buildRule({ freq: 'WEEKLY', interval: 1, byDay: ['FR', 'MO'], until: null, count: 0 }, false),
	'RRULE:FREQ=WEEKLY;BYDAY=MO,FR'
)
// The UNTIL format follows the event kind.
assert.strictEqual(
	R.buildRule(R.parseRule('RRULE:FREQ=DAILY;UNTIL=20261231'), false),
	'RRULE:FREQ=DAILY;UNTIL=20261231T225959Z'
)

// endOf / withEnd
assert.deepStrictEqual(JSON.parse(JSON.stringify(R.endOf('RRULE:FREQ=DAILY'))), { type: 'never' })
assert.strictEqual(R.endOf('RRULE:FREQ=DAILY;COUNT=4').count, 4)
assert.strictEqual(R.endOf('RRULE:FREQ=DAILY;UNTIL=20261101').type, 'until')
assert.strictEqual(R.withEnd('RRULE:FREQ=DAILY;COUNT=4', { type: 'never' }, false), 'RRULE:FREQ=DAILY')
assert.strictEqual(R.withEnd('RRULE:FREQ=DAILY', { type: 'count', count: 7 }, false), 'RRULE:FREQ=DAILY;COUNT=7')
assert.strictEqual(R.withEnd('', { type: 'count', count: 7 }, false), '')
// A rule the editor can't show keeps its other parts, in order; only the end changes.
assert.strictEqual(
	R.withEnd('RRULE:FREQ=MONTHLY;UNTIL=20261231;BYDAY=3FR', { type: 'until', date: day(2027, 6, 30) }, true),
	'RRULE:FREQ=MONTHLY;BYDAY=3FR;UNTIL=20270630'
)
const unsupported = 'RRULE:FREQ=MONTHLY;BYDAY=3FR;COUNT=6'
assert.strictEqual(R.withEnd(unsupported, R.endOf(unsupported), false), unsupported)

// Presets match whatever the end, and keep it: moving a weekly event to another day used to drop it.
assert.strictEqual(R.matchPreset('RRULE:FREQ=WEEKLY;BYDAY=TH;UNTIL=20261231T225959Z', thursday), 'weekly')
assert.strictEqual(R.matchPreset('RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR;COUNT=20', thursday), 'weekdays')
assert.strictEqual(R.matchPreset('RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=TH', thursday), '')
const kept = 'RRULE:FREQ=WEEKLY;BYDAY=TH;UNTIL=20261231T225959Z'
const friday = new Date(2026, 9, 16, 10, 0)
assert.strictEqual(
	R.withEnd(R.presetRule('weekly', friday), R.endOf(kept), false),
	'RRULE:FREQ=WEEKLY;BYDAY=FR;UNTIL=20261231T225959Z'
)

// customOf seeds the custom editor.
let c = R.customOf('RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE', thursday)
assert.strictEqual(c.freq, 'WEEKLY')
assert.strictEqual(c.interval, 2)
assert.deepStrictEqual(Array.from(c.byDay), ['MO', 'WE'])
c = R.customOf('RRULE:FREQ=DAILY', thursday)
assert.deepStrictEqual(Array.from(c.byDay), ['TH'], 'switching to weekly starts on the event day')
c = R.customOf('', thursday)
assert.strictEqual(c.freq, 'WEEKLY')

// withRule keeps EXDATE lines.
assert.deepStrictEqual(
	Array.from(R.withRule(['RRULE:FREQ=DAILY', 'EXDATE:20261020T080000Z'], 'RRULE:FREQ=DAILY;COUNT=3')),
	['RRULE:FREQ=DAILY;COUNT=3', 'EXDATE:20261020T080000Z']
)

console.log('recurrence tests passed')
