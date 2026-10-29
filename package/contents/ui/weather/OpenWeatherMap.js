.pragma library

.import "RequestCache.js" as RequestCache

// OpenWeatherMap 2.5: the current weather, 3 hour steps (forecast) and days (forecast/daily).
// The requests go through RequestCache: the daily and hourly updates share the current weather,
// and an app id is shared by every widget using it (the built-in one by everyone who didn't enter
// their own), so its budget is kept low.
var DAILY_LIMIT = 500

function weatherIsSetup(config) {
	return !!config.openWeatherMapCityId
}

function apiUrl(endpoint, args) {
	var url = 'https://api.openweathermap.org/data/2.5/'
	url += endpoint + '?id=' + args.cityId
	url += '&units=' + (args.units === 'imperial' ? 'imperial' : 'metric')
	url += '&appid=' + args.appId
	return url
}

function fetch(endpoint, args, callback) {
	if (!args.appId) return callback('OpenWeatherMap AppId not set')
	if (!args.cityId) return callback('OpenWeatherMap CityId not set')
	RequestCache.getJSON({
		service: 'OpenWeatherMap',
		url: apiUrl(endpoint, args),
		dailyLimit: DAILY_LIMIT,
	}, callback)
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

//--- Parsing (new objects: the responses stay in RequestCache)
function parseDailyData(weatherData, units) {
	var list = []
	for (var j = 0; j < weatherData.list.length; j++) {
		var item = weatherData.list[j]
		var weather = item.weather && item.weather[0]
		var temp = {}
		for (var key in item.temp) {
			temp[key] = temperature(item.temp[key], units)
		}
		var lines = []
		lines.push('<b>Morning:</b> ' + Math.round(temp.morn) + '°')
		lines.push('<b>Day:</b> ' + Math.round(temp.day) + '°')
		lines.push('<b>Evening:</b> ' + Math.round(temp.eve) + '°')
		lines.push('<b>Night:</b> ' + Math.round(temp.night) + '°')
		list.push({
			dt: item.dt,
			temp: temp,
			iconName: iconName(weather),
			text: weather ? weather.main : '',
			description: weather ? weather.description : '',
			precipitation: (item.rain || 0) + (item.snow || 0),
			notes: lines.join('<br>'),
		})
	}
	return list
}

function parseHourlyData(weatherData, units) {
	var list = []
	for (var j = 0; j < weatherData.list.length; j++) {
		var item = weatherData.list[j]
		var weather = item.weather && item.weather[0]
		var rain = item.rain && item.rain['3h'] || 0
		var snow = item.snow && item.snow['3h'] || 0
		list.push({
			dt: item.dt,
			temp: temperature(item.main.temp, units),
			iconName: iconName(weather),
			text: sentence(weather ? weather.description : ''),
			description: weather ? weather.description : '',
			precipitation: rain + snow,
		})
	}
	return list
}

// The current weather (/weather): what the Weather panel shows as "Now".
function parseCurrentData(data, units) {
	if (!data || !data.main) {
		return null
	}
	var weather = data.weather && data.weather[0]
	return {
		dt: data.dt, // When it was measured
		temp: temperature(data.main.temp, units),
		iconName: iconName(weather),
		text: sentence(weather ? weather.description : ''),
		description: weather ? weather.description : '',
		precipitation: (data.rain && data.rain['1h'] || 0) + (data.snow && data.snow['1h'] || 0),
	}
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

// The forecast, then the current weather; without the current weather (it failed): the forecast
// alone, the panel shows its first step then.
function fetchWithCurrent(endpoint, config, parse, callback) {
	var args = configArgs(config)
	fetch(endpoint, args, function(err, data, xhr) {
		if (err) return handleError('OpenWeatherMap.' + endpoint, callback, err, data, xhr)
		var result = { list: parse(data, args.units), current: null }
		fetch('weather', args, function(currentErr, currentData) {
			if (!currentErr) {
				result.current = parseCurrentData(currentData, args.units)
			}
			callback(null, result, xhr)
		})
	})
}

function updateDailyWeather(config, callback) {
	fetchWithCurrent('forecast/daily', config, parseDailyData, callback)
}

function updateHourlyWeather(config, callback) {
	fetchWithCurrent('forecast', config, parseHourlyData, callback)
}
