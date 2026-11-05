const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const source = fs.readFileSync(path.join(__dirname, '../package/contents/ui/GlancePublisher.js'), 'utf8')
	.replace(/^\.pragma library\s*/, '')
const G = {}
vm.runInNewContext(source + '\nObject.assign(out, { plain, select, payload, windowOf, MAX_BYTES, gvariantString })', { out: G, Date, Math, JSON, isNaN })

const now = new Date(2026, 10, 4, 10, 0).getTime()
const at = (d, h, m) => new Date(2026, 10, 4 + d, h, m || 0)

// A meeting: times in ms, the link and your answer, guests counted, no description
const meeting = G.plain({
	id: 'm1', summary: 'Standup', startDateTime: at(0, 10, 30), endDateTime: at(0, 11),
	start: { dateTime: '…' }, location: 'Room 1', backgroundColor: '#3366cc', description: 'secret',
	htmlLink: 'https://calendar.google.com/x', transparency: 'opaque',
}, { url: 'https://meet.google.com/abc-defg-hij', label: 'Google Meet' }, 'accepted', 3, 'Work', 'acc::work')
assert.strictEqual(meeting.start, at(0, 10, 30).getTime())
assert.strictEqual(meeting.end, at(0, 11).getTime())
assert.strictEqual(meeting.allDay, false)
assert.strictEqual(meeting.meetingUrl, 'https://meet.google.com/abc-defg-hij')
assert.strictEqual(meeting.response, 'accepted')
assert.strictEqual(meeting.guests, 3)
assert.strictEqual(meeting.calendar, 'Work')
assert.strictEqual(meeting.calendarId, 'acc::work')
assert.strictEqual(meeting.busy, true)
assert.strictEqual('description' in meeting, false)

// All-day from start.date; free time; a link that isn't http(s) is dropped
const holiday = G.plain({
	id: 'h', summary: 'Holiday', start: { date: '2026-11-05' }, startDateTime: at(1, 0), endDateTime: at(2, 0),
	transparency: 'transparent',
}, { url: 'javascript:alert(1)', label: 'x' }, '', 0, '')
assert.strictEqual(holiday.allDay, true)
assert.strictEqual(holiday.busy, false)
assert.strictEqual(holiday.meetingUrl, '')

// No usable start: left out; an end before the start: the start
assert.strictEqual(G.plain({ id: 'x', summary: 'x', startDateTime: 'bogus' }, null, '', 0, ''), null)
assert.strictEqual(G.plain({ id: 'y', summary: 'y', startDateTime: at(0, 12), endDateTime: at(0, 11) }, null, '', 0, '').end, at(0, 12).getTime())

// Tasks (Google Tasks, TickTick) and cancelled events aren't events for Glance
assert.strictEqual(G.plain({ id: 't', kind: 'tasks#task', summary: 'Task', startDateTime: at(0, 12) }, null, '', 0, ''), null)
assert.strictEqual(G.plain({ id: 'c', status: 'cancelled', summary: 'Gone', startDateTime: at(0, 12) }, null, '', 0, ''), null)

// The window: today and tomorrow, sorted; yesterday and the day after out
const items = [
	{ start: at(1, 9).getTime(), end: at(1, 10).getTime(), summary: 'tomorrow' },
	{ start: at(-1, 9).getTime(), end: at(-1, 10).getTime(), summary: 'yesterday' },
	{ start: at(0, 9).getTime(), end: at(0, 10).getTime(), summary: 'today' },
	{ start: at(2, 9).getTime(), end: at(2, 10).getTime(), summary: 'later' },
	{ start: at(-1, 23).getTime(), end: at(0, 1).getTime(), summary: 'overnight' },
]
assert.deepStrictEqual(G.select(items, now).map(e => e.summary), ['overnight', 'today', 'tomorrow'])

// The payload: Glance's shape, and kept under the size limit by dropping the latest first
const one = JSON.parse(G.payload([meeting], now))
assert.strictEqual(one.version, 1)
assert.strictEqual(one.events.length, 1)
const many = []
for (let i = 0; i < 2000; i++) {
	many.push(Object.assign({}, meeting, { id: 'e' + i, summary: 'Event ' + i + ' '.repeat(40) }))
}
const capped = G.payload(many, now)
assert.ok(capped.length <= G.MAX_BYTES)
const kept = JSON.parse(capped).events
assert.ok(kept.length > 0 && kept.length < many.length)
assert.strictEqual(kept[0].id, 'e0')

// The cap counts UTF-8 bytes (the command line), not characters: Polish titles take more
{
	const titles = Array.from({ length: 400 }, (_, i) => ({ id: 'e' + i, summary: 'Spotkanie zażółć gęślą jaźń ' + 'ą'.repeat(100), start: now, end: now }))
	const text = G.payload(titles, now)
	assert.ok(Buffer.byteLength(text, 'utf8') <= G.MAX_BYTES, 'within the cap in bytes: ' + Buffer.byteLength(text, 'utf8'))
}

// The weather: now and today's high / low, rounded; nothing without either
vm.runInNewContext(source + '\nObject.assign(out, { weather })', { out: G, Date, Math, JSON, isNaN, isFinite })
const w = G.weather({ temp: 7.6, text: 'Broken clouds', iconName: 'weather-clouds', place: 'Warsaw, PL' },
	{ temp: { max: 10.4, min: 2.5 }, iconName: 'weather-few-clouds' }, 'metric')
assert.strictEqual(w.temp, 8)
assert.strictEqual(w.high, 10)
assert.strictEqual(w.low, 3)
assert.strictEqual(w.iconName, 'weather-clouds')
assert.strictEqual(G.weather(null, null, 'metric'), null)
assert.strictEqual(G.weather(null, { temp: { max: 5, min: 1 }, iconName: 'weather-snow' }, 'imperial').temp, null)
const withWeather = JSON.parse(G.payload([], now, w))
assert.strictEqual(withWeather.weather.temp, 8)
assert.strictEqual('weather' in JSON.parse(G.payload([], now, null)), false)

// As a GVariant string for gdbus: quotes and backslashes escaped, the rest as it is
assert.strictEqual(G.gvariantString('{"a":"it\'s \\ x"}'), '\'{"a":"it\\\'s \\\\ x"}\'')
assert.strictEqual(G.gvariantString('426'), "'426'")
