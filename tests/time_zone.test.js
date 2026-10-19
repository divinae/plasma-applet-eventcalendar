// The editor's local zone for the wall date helpers.
process.env.TZ = 'Europe/Warsaw'

const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const UI = path.join(__dirname, '../package/contents/ui')
function strip(source) {
	return source.replace(/^\.(pragma|import).*$/gm, '')
}
const TimeZoneData = {}
vm.runInNewContext(strip(fs.readFileSync(path.join(UI, 'code/TimeZoneData.js'), 'utf8')) + '\nObject.assign(out, { rules, recent, pickerZones })', { out: TimeZoneData })
const T = {}
vm.runInNewContext(strip(fs.readFileSync(path.join(UI, 'TimeZone.js'), 'utf8'))
	+ '\nObject.assign(out, { parsePosix, offsetAt, abbreviation, wallClock, toUtc, toWallDate, fromWallDate, matchesLocal, guessLocal, cityName, offsetText, search, knows })',
	{ out: T, TimeZoneData, Date, Math })

const plain = x => JSON.parse(JSON.stringify(x))

// Offset (minutes east) from the platform's ICU data.
const formats = {}
function intlOffset(zone, ms) {
	if (!formats[zone]) {
		formats[zone] = new Intl.DateTimeFormat('en-US', { timeZone: zone, timeZoneName: 'longOffset' })
	}
	const part = formats[zone]
		.formatToParts(new Date(ms)).find(p => p.type === 'timeZoneName').value
	const m = /GMT(?:([+-])(\d\d):(\d\d))?/.exec(part)
	if (!m[1]) {
		return 0
	}
	const minutes = parseInt(m[2], 10) * 60 + parseInt(m[3], 10)
	return m[1] === '-' ? -minutes : minutes
}

// Parsing
assert.deepStrictEqual(plain(T.parsePosix('IST-5:30')), { std: { abbr: 'IST', offset: 330 }, dst: null })
const ny = T.parsePosix('EST5EDT,M3.2.0,M11.1.0')
assert.strictEqual(ny.std.offset, -300)
assert.strictEqual(ny.dst.offset, -240)
assert.deepStrictEqual(plain(ny.start), { type: 'M', month: 3, week: 2, day: 0, time: 7200 })
const nuuk = T.parsePosix('<-02>2<-01>,M3.5.0/-1,M10.5.0/0')
assert.strictEqual(nuuk.std.abbr, '-02')
assert.strictEqual(nuuk.start.time, -3600)
assert.strictEqual(T.parsePosix('<+1245>-12:45<+1345>,M9.5.0/2:45,M4.1.0/3:45').dst.offset, 825)
assert.strictEqual(T.parsePosix('XXX3YYY,J60/2,300/2').start.type, 'J')
assert.strictEqual(T.parsePosix('garbage'), null)

// Exact transitions (America/New_York 2026: 8 March 07:00 UTC, 1 November 06:00 UTC).
const H = 3600000
const dstStart = Date.UTC(2026, 2, 8, 7)
assert.strictEqual(T.offsetAt('America/New_York', dstStart - 1), -300)
assert.strictEqual(T.offsetAt('America/New_York', dstStart), -240)
const dstEnd = Date.UTC(2026, 10, 1, 6)
assert.strictEqual(T.offsetAt('America/New_York', dstEnd - 1), -240)
assert.strictEqual(T.offsetAt('America/New_York', dstEnd), -300)
assert.strictEqual(T.abbreviation('America/New_York', dstEnd - 1), 'EDT')
assert.strictEqual(T.abbreviation('America/Sao_Paulo', dstEnd), 'GMT-3')
assert.strictEqual(T.abbreviation('Asia/Kolkata', dstEnd), 'IST')
assert.strictEqual(T.abbreviation('Asia/Kathmandu', dstEnd), 'GMT+5:45')
assert.strictEqual(T.offsetAt('Nowhere/Nothing', dstEnd), null)

// Against ICU, hour by hour around every transition, for some zones of each kind.
const keyZones = ['America/New_York', 'America/Los_Angeles', 'Europe/Warsaw', 'Europe/London', 'Europe/Dublin',
	'Australia/Sydney', 'Australia/Lord_Howe', 'Pacific/Auckland', 'Pacific/Chatham', 'America/Santiago',
	'Asia/Kolkata', 'Asia/Tokyo', 'America/Nuuk', 'America/Havana', 'Asia/Jerusalem', 'UTC', 'America/Sao_Paulo']
for (const zone of keyZones) {
	for (let t = Date.UTC(2026, 0, 1); t < Date.UTC(2028, 0, 1); t += H / 2) {
		assert.strictEqual(T.offsetAt(zone, t), intlOffset(zone, t), zone + ' at ' + new Date(t).toISOString())
	}
}
// All zones, twice a day for a year. The system tz data may be newer than node's ICU data: zones
// whose rules changed lately are compared until their last change (the transitions table).
let mismatched = []
for (const zone of Object.keys(TimeZoneData.rules)) {
	let ok = true
	const table = TimeZoneData.recent[zone]
	const until = table ? table[table.length - 1][0] * 60000 : Date.UTC(2027, 0, 1)
	for (let t = Date.UTC(2026, 0, 1, 1); t < until && ok; t += 12 * H) {
		try {
			ok = T.offsetAt(zone, t) === intlOffset(zone, t)
		} catch (e) { // Unknown to ICU
			ok = true
			break
		}
	}
	if (!ok) {
		mismatched.push(zone)
	}
}
assert.ok(mismatched.length <= 3, 'Zones that differ from ICU: ' + mismatched.join(', '))

// Wall clock -> UTC, across DST: every 15 minutes over the switch days.
function intlWallToUtc(zone, y, mo, d, h, mi) {
	// The first instant whose wall clock in `zone` is the given one (brute force).
	const wall = Date.UTC(y, mo, d, h, mi)
	for (let t = wall - 15 * H; t <= wall + 15 * H; t += 15 * 60000) {
		if (t + intlOffset(zone, t) * 60000 === wall) {
			return t
		}
	}
	return null
}
for (const [zone, y, mo, d] of [['America/New_York', 2026, 2, 8], ['America/New_York', 2026, 10, 1],
	['Europe/Warsaw', 2026, 2, 29], ['Europe/Warsaw', 2026, 9, 25], ['Australia/Sydney', 2026, 3, 5],
	['Australia/Sydney', 2026, 9, 4], ['Europe/Dublin', 2026, 9, 25], ['Pacific/Chatham', 2026, 8, 27]]) {
	for (let minutes = 0; minutes < 24 * 60; minutes += 15) {
		const h = Math.floor(minutes / 60)
		const mi = minutes % 60
		const expected = intlWallToUtc(zone, y, mo, d, h, mi)
		const got = T.toUtc(zone, y, mo, d, h, mi)
		if (expected !== null) {
			assert.strictEqual(got, expected, zone + ' ' + h + ':' + mi)
		} else {
			// In the gap: read with the offset before (02:30 -> 03:30 New York time).
			const w = T.wallClock(zone, got)
			assert.ok(w.hours * 60 + w.minutes > minutes, zone + ' gap ' + h + ':' + mi)
		}
	}
}
assert.strictEqual(T.toUtc('America/New_York', 2026, 2, 8, 2, 30), Date.UTC(2026, 2, 8, 7, 30))
assert.strictEqual(T.toUtc('America/New_York', 2026, 10, 1, 1, 30), Date.UTC(2026, 10, 1, 5, 30)) // First 01:30 (EDT)
assert.strictEqual(T.toUtc('Nowhere/Nothing', 2026, 10, 1, 1, 30), null)

// Wall dates (local = Europe/Warsaw): New York 14:00 on 20 October = 20:00 in Warsaw.
const wallDate = new Date(2026, 9, 20, 14, 0)
const instant = T.fromWallDate('America/New_York', wallDate)
assert.strictEqual(instant.toISOString(), '2026-10-20T18:00:00.000Z')
assert.strictEqual(T.toWallDate('America/New_York', instant).getTime(), wallDate.getTime())
// Between the European (25 Oct) and US (1 Nov) switch: 5 hours apart instead of 6.
assert.strictEqual(T.fromWallDate('America/New_York', new Date(2026, 9, 28, 14, 0)).toISOString(), '2026-10-28T18:00:00.000Z')
assert.strictEqual(T.fromWallDate('America/New_York', new Date(2026, 10, 3, 14, 0)).toISOString(), '2026-11-03T19:00:00.000Z')
// Unknown zone: unchanged (local)
assert.strictEqual(T.fromWallDate('', wallDate).getTime(), wallDate.getTime())

// A wall time in the local DST gap: Tokyo 02:30 on 29 March 2026, when Warsaw skips 02:00-03:00.
const tokyoGap = T.toUtc('Asia/Tokyo', 2026, 2, 29, 2, 30)
assert.strictEqual(new Date(tokyoGap).toISOString(), '2026-03-28T17:30:00.000Z')
const memo = {}
const gapWall = T.toWallDate('Asia/Tokyo', tokyoGap, memo)
assert.strictEqual(gapWall.getHours(), 3) // The local Date can't show 02:30 that night
assert.strictEqual(T.fromWallDate('Asia/Tokyo', gapWall, memo).getTime(), tokyoGap) // Same instant back
assert.strictEqual(T.fromWallDate('Asia/Tokyo', gapWall).getTime(), tokyoGap + 3600000) // Without the memo: 03:30
// Other times don't need the memo.
const tokyoMorning = T.toUtc('Asia/Tokyo', 2026, 2, 29, 9, 0)
const memo2 = {}
const morningWall = T.toWallDate('Asia/Tokyo', tokyoMorning, memo2)
assert.deepStrictEqual(Object.keys(memo2), [])
assert.strictEqual(T.fromWallDate('Asia/Tokyo', morningWall, memo2).getTime(), tokyoMorning)
// The memo is per zone: the same local Date in another zone is read normally.
assert.strictEqual(T.fromWallDate('Asia/Seoul', gapWall, memo).toISOString(), '2026-03-28T18:30:00.000Z')

// Local zone detection
assert.ok(T.matchesLocal('Europe/Warsaw', Date.UTC(2026, 5, 1)))
assert.ok(T.matchesLocal('Europe/Berlin', Date.UTC(2026, 5, 1)))
assert.ok(!T.matchesLocal('Europe/London', Date.UTC(2026, 5, 1)))
assert.ok(!T.matchesLocal('Africa/Lagos', Date.UTC(2026, 5, 1))) // +1 all year
assert.ok(T.matchesLocal(T.guessLocal(Date.UTC(2026, 5, 1)), Date.UTC(2026, 5, 1)))

// Names and search
assert.strictEqual(T.cityName('America/Argentina/Buenos_Aires'), 'Buenos Aires')
assert.strictEqual(T.offsetText(330), '+05:30')
assert.strictEqual(T.offsetText(-570), '-09:30')
assert.deepStrictEqual(plain(T.search('new york', 10)), ['America/New_York'])
assert.strictEqual(T.search('tok', 10)[0], 'Asia/Tokyo') // Before Antarctica/Vostok
assert.strictEqual(T.search('york', 10)[0], 'America/New_York') // A word of the city
assert.strictEqual(T.search('war', 10)[0], 'Europe/Warsaw')
assert.deepStrictEqual(plain(T.search('a+(b', 10)), []) // No regexp errors
assert.ok(T.search('', 1000).length >= 300)
assert.ok(T.search('america', 1000).every(z => /america/i.test(z)))
assert.deepStrictEqual(plain(T.search('calcutta', 10, 'Asia/Calcutta')), ['Asia/Calcutta']) // An alias, when it's the event's
assert.ok(T.knows('UTC'))

// Every generated rule parses, every picker zone has one.
for (const zone of Object.keys(TimeZoneData.rules)) {
	assert.ok(T.parsePosix(TimeZoneData.rules[zone]), zone)
}
assert.ok(TimeZoneData.pickerZones.every(z => T.knows(z)))

console.log('time zone ok')
