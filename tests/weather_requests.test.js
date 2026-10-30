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
const IconSeverity = {}
vm.runInNewContext(source('IconSeverity.js'), IconSeverity)
const OWM = { RequestCache, IconSeverity, Requests, console }
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
assert.deepStrictEqual(plain(current), { dt: 90, temp: 12.5, iconName: 'weather-clear', text: 'Clear sky', description: 'clear sky', precipitation: 0, place: '' })
assert.strictEqual(OWM.parseCurrentData({ dt: 90, main: { temp: 1 }, name: 'Warsaw', sys: { country: 'PL' } }, 'metric').place, 'Warsaw, PL', 'the city as the location')
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

//--- Free API without the 16 days (401): the days from the 3 hour steps, the refusal remembered
sent = []
clock = new Date(2026, 10, 3, 9, 0).getTime()
const freeKey = { openWeatherMapAppId: 'free-key', openWeatherMapCityId: 2948825, weatherUnits: 'metric' }
const step = (d, h, temp, id, icon, description, rain) => ({
	dt: new Date(2026, 10, d, h).getTime() / 1000, main: { temp }, weather: w(id, icon, description), rain: rain ? { '3h': rain } : undefined,
})
const steps = { list: [
	step(3, 6, 2, 800, '01n', 'clear sky'),
	step(3, 9, 5, 801, '02d', 'few clouds'),
	step(3, 12, 11, 500, '10d', 'light rain', 1.2),
	step(3, 15, 9, 803, '04d', 'broken clouds', 0.4),
	step(3, 21, 4, 800, '01n', 'clear sky'),
	step(4, 0, 1, 800, '01n', 'clear sky'),
	step(4, 12, 7, 800, '01d', 'clear sky'),
] }
const days = []
OWM.updateDailyWeather(freeKey, (err, data) => days.push({ err, data }))
assert.ok(/\/forecast\/daily\?/.test(sent[0].url))
sent[0].respond('HTTP Error 401', '{"cod":401}', { status: 401 })
assert.ok(/\/forecast\?/.test(sent[1].url), 'refused: the 3 hour steps')
sent[1].respond(null, steps)
sent[2].respond(null, { dt: 1, main: { temp: 6 }, weather: w(800, '01d', 'clear sky') })
assert.strictEqual(days[0].err, null)
const [nov3, nov4] = plain(days[0].data.list)
assert.deepStrictEqual([nov3.temp.min, nov3.temp.max, nov3.precipitation], [2, 11, 1.6])
assert.strictEqual(nov3.iconName, 'weather-showers', 'the most severe of the daytime')
assert.strictEqual(nov3.description, 'light rain')
assert.strictEqual(new Date(nov3.dt * 1000).getHours(), 12, 'at noon of its day')
assert.deepStrictEqual([nov4.temp.min, nov4.temp.max, nov4.iconName], [1, 7, 'weather-clear'])
assert.strictEqual(days[0].data.current.temp, 6)
clock += 11 * 60 * 1000
OWM.updateDailyWeather(freeKey, (err, data) => days.push({ err, data }))
assert.ok(/\/forecast\?/.test(sent[3].url), 'the refusal is remembered: no /forecast/daily again')
assert.strictEqual(OWM.dataPointDuration(freeKey), 3)

//--- One Call 3.0: the city's coordinates once, then one request for the current weather, hours and days
sent = []
clock = new Date(2026, 10, 4, 9, 0).getTime()
const oneCall = Object.assign({}, freeKey, { openWeatherMapAppId: 'onecall-key', openWeatherMapApi: 'onecall' })
const oneCallData = {
	current: { dt: 50, temp: 12, weather: w(801, '02d', 'few clouds'), rain: { '1h': 0.3 } },
	hourly: [{ dt: 60, temp: 12.5, weather: w(803, '04d', 'broken clouds'), rain: { '1h': 0.2 } }, { dt: 3660, temp: 13, weather: w(800, '01d', 'clear sky') }],
	daily: [{ dt: 70, temp: { min: 4, max: 14, morn: 5, day: 13, eve: 9, night: 6 }, weather: w(500, '10d', 'light rain'), rain: 2.5 }],
}
const oneCallResults = []
OWM.updateHourlyWeather(oneCall, (err, data) => oneCallResults.push({ err, data }))
assert.ok(/data\/2\.5\/weather\?id=2948825/.test(sent[0].url), 'the coordinates')
sent[0].respond(null, { coord: { lat: 49.97, lon: 7.9 }, main: { temp: 12 } })
assert.ok(/data\/3\.0\/onecall\?lat=49\.97&lon=7\.9&exclude=minutely,alerts&units=metric&appid=onecall-key$/.test(sent[1].url), sent[1].url)
sent[1].respond(null, oneCallData)
const hours = plain(oneCallResults[0].data)
assert.deepStrictEqual(hours.list.map(h => [h.temp, h.iconName, h.precipitation]), [[12.5, 'weather-clouds', 0.2], [13, 'weather-clear', 0]])
assert.deepStrictEqual([hours.current.temp, hours.current.text, hours.current.precipitation], [12, 'Few clouds', 0.3])
OWM.updateDailyWeather(oneCall, (err, data) => oneCallResults.push({ err, data }))
assert.strictEqual(sent.length, 2, 'the days from the same (cached) request, the coordinates known')
const oneCallDay = plain(oneCallResults[1].data.list[0])
assert.deepStrictEqual([oneCallDay.temp.max, oneCallDay.precipitation, oneCallDay.iconName], [14, 2.5, 'weather-showers'])
assert.ok(/Morning:<\/b> 5°/.test(oneCallDay.notes))
assert.strictEqual(OWM.dataPointDuration(oneCall), 1)
// Not subscribed: the error reaches the caller (Logic says what to do).
clock += 11 * 60 * 1000
OWM.updateDailyWeather(oneCall, (err, data, xhr) => oneCallResults.push({ err, status: xhr && xhr.status }))
sent[2].respond('HTTP Error 401', '{"cod":401}', { status: 401 })
assert.deepStrictEqual(oneCallResults[2], { err: 'HTTP Error 401', status: 401 })

//--- Check App Id: what the app id may use, sent directly (not cached)
const direct = []
let check = null
OWM.checkAppId('k', 2948825, result => { check = plain(result) }, (url, callback) => direct.push({ url, callback }))
direct[0].callback(null, { coord: { lat: 1.5, lon: 2.5 } })
assert.ok(/forecast\/daily\?.*&cnt=1$/.test(direct[1].url), direct[1].url)
direct[1].callback('HTTP Error 401', null, { status: 401 })
assert.ok(/onecall\?lat=1\.5&lon=2\.5&exclude=minutely,hourly,daily,alerts/.test(direct[2].url), direct[2].url)
direct[2].callback('Timeout', null, { status: 0 })
assert.deepStrictEqual(check, { current: true, daily: false, oneCall: 'Timeout' })

//--- The weather texts in the widget's language
const args = { cityId: 1, units: 'metric', appId: 'k' }
assert.ok(/\/weather\?id=1&units=metric&appid=k$/.test(OWM.apiUrl('weather', args)), 'English: no lang')
OWM.setLanguage('de')
assert.ok(/\/weather\?id=1&units=metric&lang=de&appid=k$/.test(OWM.apiUrl('weather', args)))
OWM.setLanguage('pt_br')
assert.ok(/&units=metric&lang=pt_br&appid=k$/.test(OWM.oneCallUrl({ lat: 1, lon: 2 }, args)))
OWM.setLanguage('')
assert.ok(!/lang=/.test(OWM.apiUrl('forecast', args)), 'no translation: English')
// Open-Meteo's texts are ours: all of them in the translation template.
const OpenMeteo = { RequestCache, Requests, console }
vm.runInNewContext(source('OpenMeteo.js'), OpenMeteo)
assert.strictEqual(OpenMeteo.codeInfo(2, 1).text, 'Partly cloudy')
assert.strictEqual(OpenMeteo.codeInfo(1234, 1).text, 'Unknown')
const template = fs.readFileSync(path.join(__dirname, '../package/translate/template.pot'), 'utf8')
const texts = new Set(Object.keys(OpenMeteo.codeMap).map(code => OpenMeteo.codeMap[code][2]).concat('Unknown'))
texts.forEach(text => assert.ok(template.includes('\nmsgid "' + text + '"\n'), 'in template.pot: ' + text))

console.log('PASS weather_requests')
