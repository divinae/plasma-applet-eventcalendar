.pragma library

.import "../lib/Requests.js" as Requests
.import "RequestCache.js" as RequestCache

// Open-Meteo: free, no API key (10000 requests a day). https://open-meteo.com/en/docs
// One forecast request has current, hourly and daily data; the daily and hourly
// updates share it (RequestCache).
var DAILY_LIMIT = 2000

function weatherIsSetup(config) {
	return !!config.openMeteoLocationName && isFinite(config.openMeteoLatitude) && isFinite(config.openMeteoLongitude)
		&& !(config.openMeteoLatitude == 0 && config.openMeteoLongitude == 0)
}

//--- WMO weather codes
// The texts are marked for translation only: there's no i18n() in a library, Logic.qml translates
// them (localizedWeather) as the data comes.
function I18N_NOOP(text) {
	return text
}

// [day icon, night icon, short text]
var codeMap = {
	0: ['weather-clear', 'weather-clear-night', I18N_NOOP("Clear")],
	1: ['weather-few-clouds', 'weather-few-clouds-night', I18N_NOOP("Mainly clear")],
	2: ['weather-clouds', 'weather-clouds-night', I18N_NOOP("Partly cloudy")],
	3: ['weather-overcast', 'weather-overcast', I18N_NOOP("Overcast")],
	45: ['weather-fog', 'weather-fog', I18N_NOOP("Fog")],
	48: ['weather-fog', 'weather-fog', I18N_NOOP("Rime fog")],
	51: ['weather-showers-scattered', 'weather-showers-scattered-night', I18N_NOOP("Light drizzle")],
	53: ['weather-showers-scattered', 'weather-showers-scattered-night', I18N_NOOP("Drizzle")],
	55: ['weather-showers-scattered', 'weather-showers-scattered-night', I18N_NOOP("Heavy drizzle")],
	56: ['weather-freezing-rain', 'weather-freezing-rain', I18N_NOOP("Freezing drizzle")],
	57: ['weather-freezing-rain', 'weather-freezing-rain', I18N_NOOP("Freezing drizzle")],
	61: ['weather-showers-scattered', 'weather-showers-scattered-night', I18N_NOOP("Light rain")],
	63: ['weather-showers', 'weather-showers-night', I18N_NOOP("Rain")],
	65: ['weather-showers', 'weather-showers-night', I18N_NOOP("Heavy rain")],
	66: ['weather-freezing-rain', 'weather-freezing-rain', I18N_NOOP("Freezing rain")],
	67: ['weather-freezing-rain', 'weather-freezing-rain', I18N_NOOP("Freezing rain")],
	71: ['weather-snow-scattered-day', 'weather-snow-scattered-night', I18N_NOOP("Light snow")],
	73: ['weather-snow', 'weather-snow', I18N_NOOP("Snow")],
	75: ['weather-snow', 'weather-snow', I18N_NOOP("Heavy snow")],
	77: ['weather-snow', 'weather-snow', I18N_NOOP("Snow grains")],
	80: ['weather-showers-scattered', 'weather-showers-scattered-night', I18N_NOOP("Rain showers")],
	81: ['weather-showers', 'weather-showers-night', I18N_NOOP("Rain showers")],
	82: ['weather-showers', 'weather-showers-night', I18N_NOOP("Heavy rain showers")],
	85: ['weather-snow-scattered-day', 'weather-snow-scattered-night', I18N_NOOP("Snow showers")],
	86: ['weather-snow', 'weather-snow', I18N_NOOP("Heavy snow showers")],
	95: ['weather-storm', 'weather-storm-night', I18N_NOOP("Thunderstorm")],
	96: ['weather-storm', 'weather-storm-night', I18N_NOOP("Thunderstorm with hail")],
	99: ['weather-storm', 'weather-storm-night', I18N_NOOP("Thunderstorm with hail")],
}

function codeInfo(code, isDay) {
	var info = codeMap[code] || ['weather-severe-alert', 'weather-severe-alert', I18N_NOOP("Unknown")]
	return { iconName: isDay === 0 ? info[1] : info[0], text: info[2] }
}

//--- Units
function temperature(celsius, units) {
	return units === 'kelvin' ? celsius + 273.15 : celsius
}

// Local date / datetime strings from Open-Meteo (timezone=auto) to seconds since epoch.
function parseLocalTime(s) {
	// "2026-10-16" or "2026-10-16T08:45"
	var parts = s.split('T')
	var d = parts[0].split('-')
	var t = parts[1] ? parts[1].split(':') : [0, 0]
	return new Date(+d[0], +d[1] - 1, +d[2], +t[0], +t[1]).getTime() / 1000
}

//--- Request (shared by daily and hourly updates)
function forecastUrl(config) {
	var url = 'https://api.open-meteo.com/v1/forecast'
	url += '?latitude=' + encodeURIComponent(config.openMeteoLatitude)
	url += '&longitude=' + encodeURIComponent(config.openMeteoLongitude)
	url += '&current=temperature_2m,weather_code,is_day'
	url += '&hourly=temperature_2m,weather_code,precipitation,is_day'
	url += '&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum'
	url += '&timezone=auto&forecast_days=14'
	if (config.weatherUnits === 'imperial') {
		url += '&temperature_unit=fahrenheit&precipitation_unit=inch'
	}
	return url
}

function fetchForecast(config, callback) {
	RequestCache.getJSON({
		service: 'OpenMeteo',
		url: forecastUrl(config),
		dailyLimit: DAILY_LIMIT,
		errorOf: function(data) {
			return data && data.error ? data.reason || 'Open-Meteo error' : ''
		},
	}, callback)
}

//--- Provider API (see WeatherApi.js for the item formats)
function updateDailyWeather(config, callback) {
	fetchForecast(config, function(err, data, xhr) {
		if (err) {
			return callback(err, data, xhr)
		}
		var daily = data.daily
		var units = config.weatherUnits
		var precipitationUnit = config.weatherUnits === 'imperial' ? 'in' : 'mm'
		var list = []
		for (var i = 0; i < daily.time.length; i++) {
			var info = codeInfo(daily.weather_code[i], 1)
			var precipitation = daily.precipitation_sum[i] || 0
			list.push({
				dt: parseLocalTime(daily.time[i]),
				temp: {
					min: temperature(daily.temperature_2m_min[i], units),
					max: temperature(daily.temperature_2m_max[i], units),
				},
				iconName: info.iconName,
				text: info.text,
				description: info.text,
				precipitation: precipitation,
				notes: precipitation > 0 ? 'Precipitation: ' + precipitation + ' ' + precipitationUnit : '',
			})
		}
		callback(null, { list: list, current: currentData(data, units) }, xhr)
	})
}

function updateHourlyWeather(config, callback) {
	fetchForecast(config, function(err, data, xhr) {
		if (err) {
			return callback(err, data, xhr)
		}
		var hourly = data.hourly
		var units = config.weatherUnits
		var nowSeconds = Date.now() / 1000
		var list = []
		for (var i = 0; i < hourly.time.length; i++) {
			var dt = parseLocalTime(hourly.time[i])
			if (dt < nowSeconds - 3600) {
				continue // From the current hour on
			}
			if (list.length >= 7 * 24) {
				break // A week: the meteogram and the Today panel (also for the next days)
			}
			var info = codeInfo(hourly.weather_code[i], hourly.is_day ? hourly.is_day[i] : 1)
			list.push({
				dt: dt,
				temp: temperature(hourly.temperature_2m[i], units),
				iconName: info.iconName,
				description: info.text,
				precipitation: hourly.precipitation[i] || 0,
			})
		}
		callback(null, { list: list, current: currentData(data, units) }, xhr)
	})
}

function currentData(data, units) {
	if (!data.current) {
		return null
	}
	var info = codeInfo(data.current.weather_code, data.current.is_day)
	return {
		dt: parseLocalTime(data.current.time),
		temp: temperature(data.current.temperature_2m, units),
		iconName: info.iconName,
		text: info.text,
		description: info.text,
	}
}

//--- Location search (settings)
// callback(err, [{ name, region, country, latitude, longitude }])
function searchLocations(query, language, callback) {
	var url = 'https://geocoding-api.open-meteo.com/v1/search'
	url += '?name=' + encodeURIComponent(query)
	url += '&count=8&format=json'
	if (language) {
		url += '&language=' + encodeURIComponent(language)
	}
	Requests.getJSON({ url: url }, function(err, data, xhr) {
		if (err) {
			return callback(err, [])
		}
		var results = (data && data.results) || []
		callback(null, results.map(function(r) {
			return {
				name: r.name,
				region: r.admin1 || '',
				country: r.country || '',
				latitude: r.latitude,
				longitude: r.longitude,
			}
		}))
	})
}
