.pragma library

.import "RequestCache.js" as RequestCache
.import "IconSeverity.js" as IconSeverity
.import "../lib/Requests.js" as Requests

// OpenWeatherMap, one of two APIs (Settings > Weather > OpenWeatherMap > API, openWeatherMapApi):
// - 'free' (2.5, any app id): the current weather (/weather), 3 hour steps for 5 days (/forecast) and
//   16 days (/forecast/daily). The days need a paid plan: an app id without one is refused (401),
//   then they're made from the 3 hour steps (5 days).
// - 'onecall' (3.0, the "One Call by Call" subscription, 1000 free calls a day): the current weather,
//   48 hours by the hour and 8 days in one request, for the city's coordinates.
// The requests go through RequestCache: the daily and hourly updates share them, and an app id is
// shared by every widget using it (the built-in one by everyone who didn't enter their own), so its
// budget is kept low.
var DAILY_LIMIT = 500

// The language of the weather texts ("light rain"), OpenWeatherMap's code for it (de, pt_br, zh_cn,
// ...): Logic.qml sets it from the widget's translation (setLanguage). Not asked for with 'en'.
var language = 'en'
function setLanguage(code) {
	language = String(code || 'en')
}
function langParam() {
	return language && language !== 'en' ? '&lang=' + encodeURIComponent(language) : ''
}

function weatherIsSetup(config) {
	return !!config.openWeatherMapCityId
}

function usesOneCall(config) {
	return config.openWeatherMapApi === 'onecall'
}

function unitsParam(units) {
	return units === 'imperial' ? 'imperial' : 'metric'
}

function apiUrl(endpoint, args) {
	var url = 'https://api.openweathermap.org/data/2.5/'
	url += endpoint + '?id=' + args.cityId
	url += '&units=' + unitsParam(args.units)
	url += langParam()
	url += '&appid=' + args.appId
	return url
}

function oneCallUrl(coord, args) {
	var url = 'https://api.openweathermap.org/data/3.0/onecall'
	url += '?lat=' + coord.lat + '&lon=' + coord.lon
	url += '&exclude=minutely,alerts'
	url += '&units=' + unitsParam(args.units)
	url += langParam()
	url += '&appid=' + args.appId
	return url
}

function checkArgs(args) {
	if (!args.appId) return 'OpenWeatherMap AppId not set'
	if (!args.cityId) return 'OpenWeatherMap CityId not set'
	return ''
}

function getJSON(url, callback) {
	RequestCache.getJSON({
		service: 'OpenWeatherMap',
		url: url,
		dailyLimit: DAILY_LIMIT,
	}, callback)
}

function fetch(endpoint, args, callback) {
	var err = checkArgs(args)
	if (err) return callback(err)
	getJSON(apiUrl(endpoint, args), callback)
}

//--- Units
// Kelvin: requested in Celsius (like Open-Meteo), the API's own Kelvin would skip the conversion
// the rest of the widget expects.
function temperature(t, units) {
	return units === 'kelvin' ? t + 273.15 : t
}

//--- Conditions
// https://openweathermap.org/weather-conditions
var weatherIconMap = {
	'01d': 'weather-clear',
	'02d': 'weather-few-clouds',
	'03d': 'weather-clouds',
	'04d': 'weather-overcast',
	'09d': 'weather-showers-scattered',
	'10d': 'weather-showers',
	'11d': 'weather-storm',
	'13d': 'weather-snow',
	'50d': 'weather-fog',
	'01n': 'weather-clear-night',
	'02n': 'weather-few-clouds-night',
	'03n': 'weather-clouds-night',
	'04n': 'weather-overcast',
	'09n': 'weather-showers-scattered-night',
	'10n': 'weather-showers-night',
	'11n': 'weather-storm-night',
	'13n': 'weather-snow',
	'50n': 'weather-fog',
}

// 04d is both "broken clouds" (803: 51-84 % clouds, the sun comes through) and "overcast clouds"
// (804): only overcast gets the cloud without a sun.
var BROKEN_CLOUDS = 803
function iconName(weather) {
	if (!weather) {
		return 'weather-severe-alert'
	}
	var night = /n$/.test(weather.icon || '')
	if (weather.id === BROKEN_CLOUDS) {
		return night ? 'weather-clouds-night' : 'weather-clouds'
	}
	return weatherIconMap[weather.icon] || 'weather-severe-alert'
}

// "broken clouds" -> "Broken clouds"
function sentence(text) {
	text = String(text || '')
	return text.charAt(0).toUpperCase() + text.substr(1)
}

// Rain and snow in mm: a number (days) or { '1h': mm } / { '3h': mm } (hours).
function amount(value, key) {
	if (typeof value === 'number') {
		return value
	}
	return value && value[key] || 0
}

//--- Parsing (new objects: the responses stay in RequestCache)
function dayNotes(temp) {
	if (!isFinite(temp.morn)) {
		return ''
	}
	var lines = []
	lines.push('<b>Morning:</b> ' + Math.round(temp.morn) + '°')
	lines.push('<b>Day:</b> ' + Math.round(temp.day) + '°')
	lines.push('<b>Evening:</b> ' + Math.round(temp.eve) + '°')
	lines.push('<b>Night:</b> ' + Math.round(temp.night) + '°')
	return lines.join('<br>')
}

// A day of /forecast/daily or of One Call's daily.
function parseDay(item, units) {
	var weather = item.weather && item.weather[0]
	var temp = {}
	for (var key in item.temp) {
		temp[key] = temperature(item.temp[key], units)
	}
	return {
		dt: item.dt,
		temp: temp,
		iconName: iconName(weather),
		text: weather ? weather.main : '',
		description: weather ? weather.description : '',
		precipitation: amount(item.rain) + amount(item.snow),
		notes: dayNotes(temp),
	}
}

function parseDailyData(weatherData, units) {
	return weatherData.list.map(function(item) {
		return parseDay(item, units)
	})
}

// An hour (step) of /forecast (stepKey '3h') or of One Call's hourly ('1h').
function parseHour(item, units, stepKey) {
	var weather = item.weather && item.weather[0]
	return {
		dt: item.dt,
		temp: temperature(item.main ? item.main.temp : item.temp, units),
		iconName: iconName(weather),
		text: sentence(weather ? weather.description : ''),
		description: weather ? weather.description : '',
		precipitation: amount(item.rain, stepKey) + amount(item.snow, stepKey),
	}
}

function parseHourlyData(weatherData, units) {
	return weatherData.list.map(function(item) {
		return parseHour(item, units, '3h')
	})
}

// The current weather (/weather, or One Call's current): what the Weather panel shows as "Now".
function parseCurrentData(data, units) {
	if (!data || (!data.main && !isFinite(data.temp))) {
		return null
	}
	var weather = data.weather && data.weather[0]
	return {
		dt: data.dt, // When it was measured
		temp: temperature(data.main ? data.main.temp : data.temp, units),
		iconName: iconName(weather),
		text: sentence(weather ? weather.description : ''),
		description: weather ? weather.description : '',
		precipitation: amount(data.rain, '1h') + amount(data.snow, '1h'),
		// The city's name (/weather; One Call has none), shown as the panel's location.
		place: data.name ? String(data.name) + (data.sys && data.sys.country ? ', ' + data.sys.country : '') : '',
	}
}

// The days from the 3 hour steps (no /forecast/daily): per local day the low and the high, the rain,
// and the most severe daytime icon (the day's weather, not a clear night).
function daysFromSteps(steps) {
	var days = []
	var byKey = {}
	steps.forEach(function(step) {
		var date = new Date(step.dt * 1000)
		var key = date.getFullYear() + '-' + date.getMonth() + '-' + date.getDate()
		var day = byKey[key]
		if (!day) {
			var noon = new Date(date.getFullYear(), date.getMonth(), date.getDate(), 12)
			day = byKey[key] = { dt: noon.getTime() / 1000, temp: { min: step.temp, max: step.temp }, precipitation: 0, steps: [] }
			days.push(day)
		}
		day.temp.min = Math.min(day.temp.min, step.temp)
		day.temp.max = Math.max(day.temp.max, step.temp)
		day.precipitation += step.precipitation || 0
		day.steps.push(step)
	})
	return days.map(function(day) {
		var daytime = day.steps.filter(function(step) {
			var hour = new Date(step.dt * 1000).getHours()
			return hour >= 8 && hour <= 18
		})
		var shown = daytime.length ? daytime : day.steps
		var icon = IconSeverity.mostSevere(shown.map(function(step) { return step.iconName }))
		var described = shown.filter(function(step) { return step.iconName === icon })[0] || shown[0]
		return {
			dt: day.dt,
			temp: day.temp,
			iconName: icon,
			text: described.text,
			description: described.description,
			precipitation: Math.round(day.precipitation * 10) / 10,
			notes: '',
		}
	})
}

function handleError(funcName, callback, err, data, xhr) {
	console.error('[eventcalendar]', funcName + '.err', err, xhr && xhr.status)
	return callback(err, data, xhr)
}

function configArgs(config) {
	return {
		appId: config.openWeatherMapAppId,
		cityId: config.openWeatherMapCityId,
		units: config.weatherUnits,
	}
}

//--- Free API (2.5)
// App ids /forecast/daily refused (no paid plan): their days come from the 3 hour steps right away,
// for 6 hours (then asked again: the plan may have changed).
var dailyRefused = {}
var dailyRefusedFor = 6 * 60 * 60 * 1000

// The forecast, then the current weather; without the current weather (it failed): the forecast
// alone, the panel shows its first step then.
function withCurrent(args, list, xhr, callback) {
	var result = { list: list, current: null }
	fetch('weather', args, function(currentErr, currentData) {
		if (!currentErr) {
			result.current = parseCurrentData(currentData, args.units)
		}
		callback(null, result, xhr)
	})
}

function updateFreeDaily(config, callback) {
	var args = configArgs(config)
	function fromSteps() {
		fetch('forecast', args, function(err, data, xhr) {
			if (err) return handleError('OpenWeatherMap.forecast', callback, err, data, xhr)
			withCurrent(args, daysFromSteps(parseHourlyData(data, args.units)), xhr, callback)
		})
	}
	if (dailyRefused[args.appId] && Date.now() - dailyRefused[args.appId] < dailyRefusedFor) {
		return fromSteps()
	}
	fetch('forecast/daily', args, function(err, data, xhr) {
		if (err && xhr && xhr.status === 401) {
			// The app id is fine (else /forecast fails too): the days aren't in its plan.
			dailyRefused[args.appId] = Date.now()
			return fromSteps()
		}
		if (err) return handleError('OpenWeatherMap.forecast/daily', callback, err, data, xhr)
		withCurrent(args, parseDailyData(data, args.units), xhr, callback)
	})
}

function updateFreeHourly(config, callback) {
	var args = configArgs(config)
	fetch('forecast', args, function(err, data, xhr) {
		if (err) return handleError('OpenWeatherMap.forecast', callback, err, data, xhr)
		withCurrent(args, parseHourlyData(data, args.units), xhr, callback)
	})
}

//--- One Call (3.0)
// One Call needs coordinates, the settings have the city id: /weather has them, asked once per city.
var cityCoords = {} // cityId -> { lat, lon }

function fetchCoords(args, callback) {
	var known = cityCoords[args.cityId]
	if (known) {
		return callback(null, known)
	}
	fetch('weather', args, function(err, data, xhr) {
		if (err) return callback(err, data, xhr)
		if (!data || !data.coord) return callback('OpenWeatherMap: no coordinates for the city', data, xhr)
		cityCoords[args.cityId] = { lat: data.coord.lat, lon: data.coord.lon }
		callback(null, cityCoords[args.cityId])
	})
}

function fetchOneCall(config, callback) {
	var args = configArgs(config)
	var err = checkArgs(args)
	if (err) return callback(err)
	fetchCoords(args, function(coordErr, coord, xhr) {
		if (coordErr) return handleError('OpenWeatherMap.weather', callback, coordErr, coord, xhr)
		getJSON(oneCallUrl(coord, args), function(err, data, xhr) {
			if (err) return handleError('OpenWeatherMap.onecall', callback, err, data, xhr)
			callback(null, data, xhr)
		})
	})
}

function parseOneCallDaily(data, units) {
	return {
		list: (data.daily || []).map(function(item) { return parseDay(item, units) }),
		current: parseCurrentData(data.current, units),
	}
}

function parseOneCallHourly(data, units) {
	return {
		list: (data.hourly || []).map(function(item) { return parseHour(item, units, '1h') }),
		current: parseCurrentData(data.current, units),
	}
}

//--- Provider API (see WeatherApi.js for the item formats)
function updateDailyWeather(config, callback) {
	if (!usesOneCall(config)) {
		return updateFreeDaily(config, callback)
	}
	fetchOneCall(config, function(err, data, xhr) {
		if (err) return callback(err, data, xhr)
		callback(null, parseOneCallDaily(data, config.weatherUnits), xhr)
	})
}

function updateHourlyWeather(config, callback) {
	if (!usesOneCall(config)) {
		return updateFreeHourly(config, callback)
	}
	fetchOneCall(config, function(err, data, xhr) {
		if (err) return callback(err, data, xhr)
		callback(null, parseOneCallHourly(data, config.weatherUnits), xhr)
	})
}

// Hours between two hourly items (the meteogram's columns).
function dataPointDuration(config) {
	return usesOneCall(config) ? 1 : 3
}

//--- Settings > Weather > OpenWeatherMap > Check app id
// What the app id may use: callback({ current, daily, oneCall }), each true, false (refused, 401) or
// an error message (eg: no connection). Sent directly (not cached): the answer is wanted now.
function checkAppId(appId, cityId, callback, getJSONDirect) {
	getJSONDirect = getJSONDirect || Requests.getJSON
	var result = {}
	var args = { appId: appId, cityId: cityId || 2950159, units: 'metric' } // Berlin as the test city
	function ask(url, done) {
		getJSONDirect(url, function(err, data, xhr) {
			done(!err ? true : xhr && xhr.status === 401 ? false : String(err), data)
		})
	}
	ask(apiUrl('weather', args), function(current, data) {
		result.current = current
		var coord = current === true && data && data.coord ? data.coord : { lat: 52.52, lon: 13.41 }
		ask(apiUrl('forecast/daily', args) + '&cnt=1', function(daily) {
			result.daily = daily
			ask(oneCallUrl(coord, args).replace('exclude=minutely,alerts', 'exclude=minutely,hourly,daily,alerts'), function(oneCall) {
				result.oneCall = oneCall
				callback(result)
			})
		})
	})
}
