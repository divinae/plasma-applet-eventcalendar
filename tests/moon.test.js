// The moon on a day (package/contents/ui/Moon.js): phase, lit share, rise and set, the next full or
// new moon. Local days in Berlin.
process.env.TZ = 'Europe/Berlin'
const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const M = {}
vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../package/contents/ui/Moon.js'), 'utf8')
	.replace(/^\.pragma library\s*$/m, ''), M)

const hours = ms => Math.abs(ms) / 3600000
function near(actual, expected, maxHours, what) {
	assert.ok(actual, what + ': none found')
	assert.ok(hours(actual - expected) <= maxHours,
		what + ': ' + actual.toISOString() + ' vs ' + expected.toISOString())
}

// The main phases of January 2024 (UTC, as published), from a week before each: within an hour.
const main = [
	[0, '2024-01-11T11:57:00Z', 'new moon'],
	[0.25, '2024-01-18T03:52:00Z', 'first quarter'],
	[0.5, '2024-01-25T17:54:00Z', 'full moon'],
	[0.75, '2024-02-02T23:18:00Z', 'last quarter'],
]
main.forEach(([target, iso, what]) => {
	const at = new Date(iso)
	near(M.nextPhase(new Date(at - 7 * 86400000), target), at, 1, what)
})

// Lit share: full at the full moon, none at the new moon.
assert.ok(M.illumination(new Date('2024-01-25T17:54:00Z')).fraction > 0.99, 'full: all lit')
assert.ok(M.illumination(new Date('2024-01-11T11:57:00Z')).fraction < 0.01, 'new: none lit')

// A day's phase: the main one only on its day, else between them.
const full = M.dayInfo(new Date(2024, 0, 25))
assert.strictEqual(full.phaseKey, 'full')
assert.strictEqual(full.glyph, 14, 'the full moon glyph')
near(full.mainAt, new Date('2024-01-25T17:54:00Z'), 1, 'its time')
assert.strictEqual(full.next.key, 'new', 'after a full moon: the new moon')
near(full.next.at, new Date('2024-02-09T22:59:00Z'), 1, 'the next new moon')
assert.strictEqual(M.dayInfo(new Date(2024, 0, 21)).phaseKey, 'waxingGibbous')
assert.strictEqual(M.dayInfo(new Date(2024, 0, 14)).phaseKey, 'waxingCrescent')
assert.strictEqual(M.dayInfo(new Date(2024, 0, 29)).phaseKey, 'waningGibbous')
assert.strictEqual(M.dayInfo(new Date(2024, 1, 6)).phaseKey, 'waningCrescent')
const glyph = M.dayInfo(new Date(2024, 0, 21)).glyph
assert.ok(glyph > 7 && glyph < 14, 'a waxing gibbous glyph: ' + glyph)
assert.strictEqual(M.dayInfo(new Date(2024, 0, 21)).riseSet, null, 'no place: no rise and set')

// Rise and set in Berlin: within the day, the moon's upper edge on the horizon then.
const berlin = [52.52, 13.405]
for (let day = 1; day <= 28; day += 3) {
	const date = new Date(2024, 0, day)
	const rs = M.dayInfo(date, berlin[0], berlin[1]).riseSet
	assert.ok(rs.rise || rs.set, 'rises or sets on 2024-01-' + day)
	;[rs.rise, rs.set].filter(Boolean).forEach(t => {
		assert.ok(t >= date && t < new Date(2024, 0, day + 1), 'within the day')
		const edge = (M.moonAltitude(t, berlin[0], berlin[1]) / M.rad) - 0.133
		assert.ok(Math.abs(edge) < 0.25, 'on the horizon (within a minute) at ' + t.toISOString() + ': ' + edge)
	})
}
// Close to the pole the moon can stay up or down all day.
const polar = []
for (let day = 1; day <= 28; day++) {
	const rs = M.riseSet(new Date(2024, 0, day), 78.2, 15.6) // Longyearbyen
	polar.push(rs.alwaysUp ? 'up' : rs.alwaysDown ? 'down' : '')
}
assert.ok(polar.includes('up') && polar.includes('down'), 'days always up and always down: ' + polar.join())

// The sun: high at noon on the June solstice (Berlin: 90 - 52.5 + 23.4 = about 61 degrees), and
// in Bingen on 3 November 2026 still down at 07:00, up at 08:00 (it rises about 07:20).
const noon = M.sunAltitude(new Date(2024, 5, 21, 13, 10), berlin[0], berlin[1])
assert.ok(Math.abs(noon - 61) < 1, 'June noon: ' + noon)
const bingen = M.sunDownAt(49.967, 7.899)
assert.deepStrictEqual([bingen(new Date(2026, 10, 3, 7).getTime()), bingen(new Date(2026, 10, 3, 8).getTime())], [true, false])
assert.strictEqual(M.sunDownAt(NaN, 7.9), null, 'no place: none')

// Sunrise and sunset (published for Berlin on 21 June 2024: 04:43 and 21:33 CEST), within 3 minutes.
const june = M.sunRiseSet(new Date(2024, 5, 21), berlin[0], berlin[1])
near(june.rise, new Date(2024, 5, 21, 4, 43), 0.05, 'sunrise')
near(june.set, new Date(2024, 5, 21, 21, 33), 0.05, 'sunset')
// Close to the pole: the midnight sun in June, the polar night in December.
assert.ok(M.sunRiseSet(new Date(2024, 5, 21), 78.2, 15.6).alwaysUp, 'midnight sun')
assert.ok(M.sunRiseSet(new Date(2024, 11, 21), 78.2, 15.6).alwaysDown, 'polar night')
assert.strictEqual(M.sunRiseSet(new Date(2024, 5, 21), NaN, 13.4), null, 'no place: none')

// A day's glyph within its named phase (not a main phase's glyph on a day without it).
;[[2024, 11, 31], [2024, 6, 13], [2024, 3, 23]].forEach(([y, m, d]) => {
	const info = M.dayInfo(new Date(y, m, d))
	if (!info.mainAt) {
		assert.ok(info.glyph % 7 !== 0, y + '-' + (m + 1) + '-' + d + ': glyph ' + info.glyph + ' for ' + info.phaseKey)
	}
})
for (let day = 0; day < 400; day++) {
	const info = M.dayInfo(new Date(2025, 0, 1 + day))
	const quarter = { waxingCrescent: 0, waxingGibbous: 1, waningGibbous: 2, waningCrescent: 3 }[info.phaseKey]
	if (quarter !== undefined) {
		assert.ok(info.glyph >= quarter * 7 + 1 && info.glyph <= quarter * 7 + 6, 'glyph ' + info.glyph + ' in ' + info.phaseKey)
	}
}

// Daylight saving change days (23 and 25 hours): rise and set only within the local day.
;[new Date(2043, 2, 29), new Date(2013, 9, 27), new Date(2026, 2, 29), new Date(2026, 9, 25)].forEach(date => {
	const end = new Date(date.getFullYear(), date.getMonth(), date.getDate() + 1)
	;[M.riseSet(date, berlin[0], berlin[1]), M.sunRiseSet(date, berlin[0], berlin[1])].forEach(rs => {
		;[rs.rise, rs.set].filter(Boolean).forEach(t => assert.ok(t >= date && t < end, 'within ' + date.toDateString() + ': ' + t.toISOString()))
	})
})
// The 25-hour day's last hour is scanned: 27 Oct 2013, the moon rose at about 23:45 in Berlin.
near(M.riseSet(new Date(2013, 9, 27), berlin[0], berlin[1]).rise, new Date(2013, 9, 27, 23, 45), 0.5, '23:45 moonrise')

console.log('PASS moon')
