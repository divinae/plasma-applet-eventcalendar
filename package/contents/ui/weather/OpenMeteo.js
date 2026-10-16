.pragma library

.import "../lib/Requests.js" as Requests

// Open-Meteo: free, no API key. https://open-meteo.com/en/docs
// One forecast request has current, hourly and daily data; the daily and hourly
// updates share it (cached for a few minutes).

function weatherIsSetup(config) {
	return !!config.openMeteoLocationName && isFinite(config.openMeteoLatitude) && isFinite(config.openMeteoLongitude)
		&& !(config.openMeteoLatitude == 0 && config.openMeteoLongitude == 0)
}

//--- WMO weather codes
// [day icon, night icon, short text]
var codeMap = {
	0: ['weather-clear', 'weather-clear-night', 'Clear'],
	1: ['weather-few-clouds', 'weather-few-clouds-night', 'Mainly clear'],
	2: ['weather-clouds', 'weather-clouds-night', 'Partly cloudy'],
	3: ['weather-overcast', 'weather-overcast', 'Overcast'],
	45: ['weather-fog', 'weather-fog', 'Fog'],
	48: ['weather-fog', 'weather-fog', 'Rime fog'],
	51: ['weather-showers-scattered', 'weather-showers-scattered-night', 'Light drizzle'],
	53: ['weather-showers-scattered', 'weather-showers-scattered-night', 'Drizzle'],
	55: ['weather-showers-scattered', 'weather-showers-scattered-night', 'Heavy drizzle'],
	56: ['weather-freezing-rain', 'weather-freezing-rain', 'Freezing drizzle'],
	57: ['weather-freezing-rain', 'weather-freezing-rain', 'Freezing drizzle'],
	61: ['weather-showers-scattered', 'weather-showers-scattered-night', 'Light rain'],
	63: ['weather-showers', 'weather-showers-night', 'Rain'],
	65: ['weather-showers', 'weather-showers-night', 'Heavy rain'],
	66: ['weather-freezing-rain', 'weather-freezing-rain', 'Freezing rain'],
	67: ['weather-freezing-rain', 'weather-freezing-rain', 'Freezing rain'],
	71: ['weather-snow-scattered-day', 'weather-snow-scattered-night', 'Light snow'],
	73: ['weather-snow', 'weather-snow', 'Snow'],
	75: ['weather-snow', 'weather-snow', 'Heavy snow'],
	77: ['weather-snow', 'weather-snow', 'Snow grains'],
	80: ['weather-showers-scattered', 'weather-showers-scattered-night', 'Rain showers'],
	81: ['weather-showers', 'weather-showers-night', 'Rain showers'],
	82: ['weather-showers', 'weather-showers-night', 'Heavy rain showers'],
	85: ['weather-snow-scattered-day', 'weather-snow-scattered-night', 'Snow showers'],
	86: ['weather-snow', 'weather-snow', 'Heavy snow showers'],
	95: ['weather-storm', 'weather-storm-night', 'Thunderstorm'],
	96: ['weather-storm', 'weather-storm-night', 'Thunderstorm with hail'],
	99: ['weather-storm', 'weather-storm-night', 'Thunderstorm with hail'],
}

function codeInfo(code, isDay) {
	var info = codeMap[code] || ['weather-severe-alert', 'weather-severe-alert', 'Unknown']
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
var cache = { key: '', at: 0, data: null }
var pending = {} // key -> [callbacks]

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
	var url = forecastUrl(config)
	if (cache.key === url && cache.data && Date.now() - cache.at < 10 * 60 * 1000) {
		return callback(null, cache.data, null)
	}
	if (pending[url]) {
		pending[url].push(callback)
		return
	}
	pending[url] = [callback]
	Requests.getJSON({ url: url }, function(err, data, xhr) {
		if (!err && data && data.error) {
			err = data.reason || 'Open-Meteo error'
		}
		if (!err) {
			cache = { key: url, at: Date.now(), data: data }
		}
		var callbacks = pending[url]
		delete pending[url]
		for (var i = 0; i < callbacks.length; i++) {
			callbacks[i](err, data, xhr)
		}
	})
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
		temp: temperature(data.current.temperature_2m, units),
		iconName: info.iconName,
		text: info.text,
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
