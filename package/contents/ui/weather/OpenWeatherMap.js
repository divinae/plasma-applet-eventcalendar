.pragma library

.import "../lib/Requests.js" as Requests

function weatherIsSetup(config) {
	return !!config.openWeatherMapCityId
}

function fetchHourlyWeatherForecast(args, callback) {
	if (!args.appId) return callback('OpenWeatherMap AppId not set')
	if (!args.cityId) return callback('OpenWeatherMap CityId not set')

	var url = 'https://api.openweathermap.org/data/2.5/'
	url += 'forecast?id=' + args.cityId
	url += '&units=' + (args.units || 'metric')
	url += '&appid=' + args.appId
	Requests.getJSON(url, callback)
}

function fetchDailyWeatherForecast(args, callback) {
	if (!args.appId) return callback('OpenWeatherMap AppId not set')
	if (!args.cityId) return callback('OpenWeatherMap CityId not set')

	var url = 'https://api.openweathermap.org/data/2.5/'
	url += 'forecast/daily?id=' + args.cityId
	url += '&units=' + (args.units || 'metric')
	url += '&appid=' + args.appId
	Requests.getJSON(url, callback)
}

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

function parseDailyData(weatherData) {
	for (var j = 0; j < weatherData.list.length; j++) {
		var forecastItem = weatherData.list[j]

		forecastItem.iconName = weatherIconMap[forecastItem.weather[0].icon]
		forecastItem.text = forecastItem.weather[0].main
		forecastItem.description = forecastItem.weather[0].description
		
		var lines = []
		lines.push('<b>Morning:</b> ' + Math.round(forecastItem.temp.morn) + '°')
		lines.push('<b>Day:</b> ' + Math.round(forecastItem.temp.day) + '°')
		lines.push('<b>Evening:</b> ' + Math.round(forecastItem.temp.eve) + '°')
		lines.push('<b>Night:</b> ' + Math.round(forecastItem.temp.night) + '°')
		forecastItem.notes = lines.join('<br>')
	}

	return weatherData
}

function parseHourlyData(weatherData) {
	for (var j = 0; j < weatherData.list.length; j++) {
		var forecastItem = weatherData.list[j]
		
		forecastItem.temp = forecastItem.main.temp
		forecastItem.iconName = weatherIconMap[forecastItem.weather[0].icon]
		forecastItem.description = forecastItem.weather[0].description

		var rain = forecastItem.rain && forecastItem.rain['3h'] || 0
		var snow = forecastItem.snow && forecastItem.snow['3h'] || 0
		var mm = rain + snow
		forecastItem.precipitation = mm
	}

	return weatherData
}

function handleError(funcName, callback, err, data, xhr) {
	console.error('[eventcalendar]', funcName + '.err', err, xhr && xhr.status, data)
	return callback(err, data, xhr)
}

function updateDailyWeather(config, callback) {
	fetchDailyWeatherForecast({
		appId: config.openWeatherMapAppId,
		cityId: config.openWeatherMapCityId,
		units: config.weatherUnits,
	}, function(err, data, xhr) {
		if (err) return handleError('OpenWeatherMap.fetchDailyWeatherForecast', callback, err, data, xhr)

		data = parseDailyData(data)

		callback(err, data, xhr)
	})
}

function updateHourlyWeather(config, callback) {
	fetchHourlyWeatherForecast({
		appId: config.openWeatherMapAppId,
		cityId: config.openWeatherMapCityId,
		units: config.weatherUnits,
	}, function(err, data, xhr) {
		if (err) return handleError('updateHourlyWeather', callback, err, data, xhr)

		data = parseHourlyData(data)

		callback(err, data, xhr)
	})
}

