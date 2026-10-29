// Weather requests: RequestCache (cache, bundling, daily budget) and OpenWeatherMap's parsing.
const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const strip = s => s.replace(/^\.pragma library\s*$/m, '').replace(/^\.import .*$/mg, '')
const weatherDir = path.join(__dirname, '../package/contents/ui/weather')
const source = name => strip(fs.readFileSync(path.join(weatherDir, name), 'utf8'))

// Requests answered by hand: sent[i] = { url, respond(err, data, xhr) }
let sent = []
const Requests = {
	getJSON(opt, callback) {
		sent.push({ url: opt.url, respond: (err, data, xhr) => callback(err, data, xhr || { status: err ? 500 : 200 }) })
	},
}
let clock = new Date(2026, 9, 29, 10, 0).getTime()
const warnings = []
const RequestCache = { Requests, console: { warn: (...args) => warnings.push(args.join(' ')) } }
vm.runInNewContext(source('RequestCache.js'), RequestCache)
RequestCache.now = () => clock

function get(url, service = 'Test', dailyLimit = 100, errorOf) {
	const answers = []
	RequestCache.getJSON({ service, url, dailyLimit, errorOf }, (err, data, xhr) => answers.push({ err, data, xhr }))
	return answers
}

//--- Cache and bundling
let a = get('u1'), b = get('u1')
assert.strictEqual(sent.length, 1, 'two at once: one request')
sent[0].respond(null, { n: 1 })
assert.deepStrictEqual([a[0].data, b[0].data], [{ n: 1 }, { n: 1 }])
clock += 9 * 60 * 1000
assert.deepStrictEqual(get('u1')[0], { err: null, data: { n: 1 }, xhr: null }, 'cached within 10 minutes')
assert.strictEqual(sent.length, 1)
clock += 2 * 60 * 1000
get('u1')
assert.strictEqual(sent.length, 2, 'requested again after 10 minutes')
sent[1].respond(null, { n: 2 })

// Errors aren't cached; errorOf turns a 200 into one.
get('u2')
sent[2].respond('HTTP 503')
get('u2')
assert.strictEqual(sent.length, 4, 'an error is not cached')
const failed = get('u3', 'Test', 100, data => data.error ? 'bad' : '')
sent[4].respond(null, { error: true })
assert.strictEqual(failed[0].err, 'bad')
get('u3', 'Test', 100, data => data.error ? 'bad' : '')
assert.strictEqual(sent.length, 6)
assert.strictEqual(RequestCache.requestsToday('Test'), 6, 'network requests counted, cached answers not')

//--- Daily budget: past it, a URL at most once an hour
sent = []
clock = new Date(2026, 9, 30, 8, 0).getTime()
assert.strictEqual(RequestCache.requestsToday('Limited'), 0, 'a new day')
for (let i = 0; i < 3; i++) {
	get('l' + i, 'Limited', 3)
	sent[i].respond(null, { i })
	clock += 11 * 60 * 1000
}
assert.strictEqual(RequestCache.requestsToday('Limited'), 3)
clock += 20 * 60 * 1000 // l0 is 53 minutes old
assert.deepStrictEqual(get('l0', 'Limited', 3)[0].data, { i: 0 }, 'over budget: the older answer')
assert.strictEqual(sent.length, 3)
assert.strictEqual(warnings.length, 1, 'warned once')
clock += 10 * 60 * 1000
get('l0', 'Limited', 3)
assert.strictEqual(sent.length, 4, 'over budget: hourly')
get('l9', 'Limited', 3)
assert.strictEqual(sent.length, 5, 'over budget: nothing cached is still requested')
assert.strictEqual(RequestCache.requestsToday('Other'), 0, 'per service')

//--- OpenWeatherMap
const plain = o => JSON.parse(JSON.stringify(o)) // Objects from the vm context
const OWM = { RequestCache, console }
vm.runInNewContext(source('OpenWeatherMap.js'), OWM)
const w = (id, icon, description) => [{ id, icon, description, main: 'Clouds' }]
assert.strictEqual(OWM.iconName(w(803, '04d')[0]), 'weather-clouds', 'broken clouds: the sun comes through')
assert.strictEqual(OWM.iconName(w(803, '04n')[0]), 'weather-clouds-night')
assert.strictEqual(OWM.iconName(w(804, '04d')[0]), 'weather-overcast')
assert.strictEqual(OWM.iconName(w(802, '03d')[0]), 'weather-clouds')
assert.strictEqual(OWM.iconName(undefined), 'weather-severe-alert')

const response = { list: [{ dt: 100, main: { temp: 14 }, weather: w(803, '04d', 'broken clouds'), rain: { '3h': 0.5 } }] }
const hourly = OWM.parseHourlyData(response, 'kelvin')
assert.deepStrictEqual(plain(hourly[0]), {
	dt: 100, temp: 287.15, iconName: 'weather-clouds', text: 'Broken clouds', description: 'broken clouds', precipitation: 0.5,
})
assert.strictEqual(response.list[0].temp, undefined, 'the cached response is left as it was')

const current = OWM.parseCurrentData({ dt: 90, main: { temp: 12.5 }, weather: w(800, '01d', 'clear sky') }, 'metric')
assert.deepStrictEqual(plain(current), { dt: 90, temp: 12.5, iconName: 'weather-clear', text: 'Clear sky', description: 'clear sky', precipitation: 0 })
assert.strictEqual(OWM.parseCurrentData({}, 'metric'), null)

// An update: the forecast and the current weather (/weather), which daily and hourly share.
sent = []
clock = new Date(2026, 10, 2, 9, 0).getTime()
const config = { openWeatherMapAppId: 'key', openWeatherMapCityId: 2948825, weatherUnits: 'metric' }
const results = []
OWM.updateHourlyWeather(config, (err, data) => results.push({ err, data }))
assert.ok(/\/forecast\?id=2948825&units=metric&appid=key$/.test(sent[0].url), sent[0].url)
sent[0].respond(null, response)
assert.ok(/\/weather\?id=2948825/.test(sent[1].url), sent[1].url)
sent[1].respond(null, { dt: 90, main: { temp: 12.5 }, weather: w(800, '01d', 'clear sky') })
assert.strictEqual(results[0].data.current.iconName, 'weather-clear')
assert.strictEqual(results[0].data.list.length, 1)
OWM.updateDailyWeather(config, (err, data) => results.push({ err, data }))
assert.strictEqual(sent.length, 3, 'daily: its forecast, the current weather from the cache')
sent[2].respond(null, { list: [{ dt: 200, temp: { min: 4, max: 14, morn: 5, day: 13, eve: 9, night: 6 }, weather: w(500, '10d', 'light rain'), rain: 2.5 }] })
assert.strictEqual(results[1].data.current.text, 'Clear sky')
assert.deepStrictEqual([results[1].data.list[0].temp.max, results[1].data.list[0].precipitation], [14, 2.5])
// Without the current weather (failed): the forecast alone.
clock += 11 * 60 * 1000
OWM.updateHourlyWeather(config, (err, data) => results.push({ err, data }))
sent[3].respond(null, response)
sent[4].respond('HTTP 401')
assert.deepStrictEqual([results[2].err, results[2].data.current], [null, null])

console.log('PASS weather_requests')
