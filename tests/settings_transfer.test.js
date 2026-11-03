const test = require('node:test')
const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const source = fs.readFileSync(path.join(__dirname, '../package/contents/ui/lib/SettingsTransfer.js'), 'utf8')
	.replace(/^\.pragma library\s*/, '')
const ST = {}
vm.runInNewContext(source, ST)

const mainXml = fs.readFileSync(path.join(__dirname, '../package/contents/config/main.xml'), 'utf8')
const allKeys = [...mainXml.matchAll(/<entry name="([^"]+)"/g)].map((m) => m[1])

test('no secret or internal setting is exported', () => {
	const exported = allKeys.filter(ST.exportable)
	for (const key of ['accessToken', 'refreshToken', 'access_token', 'accessTokenType', 'accessTokenExpiresAt',
		'customClientSecret', 'latestClientSecret', 'sessionClientSecret', 'openWeatherMapAppId',
		'v182Migration', 'debugging', 'importRequest', 'invitationsNotified', 'mutedEventKeys']) {
		assert.ok(allKeys.includes(key), key + ' is a setting')
		assert.ok(!exported.includes(key), key + ' is left out')
	}
	for (const key of ['caldavAccounts', 'icalCalendarList', 'googleAccounts', 'selectedTimeZones', 'clockTimeFormat1']) {
		assert.ok(exported.includes(key), key + ' is exported')
	}
})

test('build: the exportable values, sorted', () => {
	const values = { b: 2, a: 'x', accessToken: 'secret', none: undefined }
	const data = ST.build(Object.keys(values), (k) => values[k], '1.17.0', new Date('2026-11-03T10:00:00Z'))
	assert.strictEqual(data.app, 'org.kde.plasma.eventcalendar')
	assert.strictEqual(data.version, '1.17.0')
	assert.strictEqual(data.exported, '2026-11-03T10:00:00.000Z')
	assert.deepStrictEqual(JSON.parse(JSON.stringify(data.settings)), { a: 'x', b: 2 })
})

test('parse: round trip, unknown, secret and mistyped keys skipped', () => {
	const current = { clockShowLine2: false, selectedTimeZones: ['Local'], eventsPollInterval: 15, refreshToken: '' }
	const text = JSON.stringify({ app: 'org.kde.plasma.eventcalendar', settings: {
		clockShowLine2: true,
		selectedTimeZones: ['Local', 'Asia/Tokyo'],
		eventsPollInterval: 'often',
		refreshToken: 'stolen',
		somethingElse: 1,
	} })
	const result = ST.parse(text, (k) => current[k])
	assert.deepStrictEqual(JSON.parse(JSON.stringify(result.settings)), { clockShowLine2: true, selectedTimeZones: ['Local', 'Asia/Tokyo'] })
	assert.deepStrictEqual([...result.skipped], ['eventsPollInterval', 'refreshToken', 'somethingElse'])
})

test('parse: not this widget\'s file', () => {
	assert.strictEqual(ST.parse('nope', () => 1).error, 'json')
	assert.strictEqual(ST.parse('{"app":"other","settings":{}}', () => 1).error, 'app')
	assert.strictEqual(ST.parse('{"app":"org.kde.plasma.eventcalendar","settings":[]}', () => 1).error, 'app')
})

test('fileName and chunks', () => {
	assert.strictEqual(ST.fileName(new Date(2026, 10, 3)), 'eventcalendar-settings-2026-11-03.json')
	assert.deepStrictEqual([...ST.chunks('abcdefg', 3)], ['abc', 'def', 'g'])
	assert.deepStrictEqual([...ST.chunks('', 3)], [''])
})
