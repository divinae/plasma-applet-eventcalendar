.pragma library

.import "OpenWeatherMap.js" as OpenWeatherMap
.import "WeatherCanada.js" as WeatherCanada
.import "OpenMeteo.js" as OpenMeteo
.import "IconSeverity.js" as IconSeverity

/* How many hours each data point represents */
function getDataPointDuration(config) {
	var weatherService = config.weatherService
	if (weatherService == 'OpenWeatherMap') {
		return OpenWeatherMap.dataPointDuration(config)
	} else if (weatherService == 'OpenMeteo') {
		return 1
	} else if (weatherService == 'WeatherCanada') {
		return 1
	} else {
		return 1
	}
}

/* Precipitation units ('mm' or '%') */
function getRainUnits(config) {
	var weatherService = config.weatherService
	if (weatherService == 'OpenWeatherMap' || weatherService == 'OpenMeteo') {
		return 'mm'
	} else if (weatherService == 'WeatherCanada') {
		return '%'
	} else {
		return 'mm'
	}
}

/* Update the weather shown in the agenda. */
/* @returns: callback(err, {
	list: [
		{
			dt: 1474831800, // seconds
			temp: {
				min: 14.5,
				max: 14.5,
				morn: 14.5, // (Optional)
				day: 14.5, // (Optional)
				eve: 14.5, // (Optional)
				night: 14.5, // (Optional)
			},
			iconName: 'weather-clear',
			text: 'Clear', // Word/Short description (the "Weather Text" shown in the agenda)
			description: 'clear sky',  // Sentence (shown in the tooltip)
			notes: 'Morning: 13°\nEvening: 5°', // Tooltip subtext (Optional)
		},
		...
	]
}, xhr)
*/
function updateDailyWeather(config, callback) {
	if (!weatherIsSetup(config)) {
		return callback('Weather configuration not setup')
	}
	var weatherService = config.weatherService
	if (weatherService == 'OpenMeteo') {
		OpenMeteo.updateDailyWeather(config, callback)
	} else if (weatherService == 'OpenWeatherMap') {
		OpenWeatherMap.updateDailyWeather(config, callback)
	} else if (weatherService == 'WeatherCanada') {
		WeatherCanada.updateDailyWeather(config, callback)
	}
}

/* Update the meteogram dataset. Will not be called if the meteogram isn't enabled. */
/* @returns: callback(err, {
	list: [
		{
			dt: 1474831800, // seconds
			temp: 14.5,
			iconName: 'weather-clear',
			description: 'clear sky', // Sentence (Tooltip)
			precipitation: 20, // Can represent 20mm or 20%
		},
		...
	]
}, xhr)
*/
function updateHourlyWeather(config, callback) {
	if (!weatherIsSetup(config)) {
		return callback('Weather configuration not setup')
	}
	var weatherService = config.weatherService
	if (weatherService == 'OpenMeteo') {
		OpenMeteo.updateHourlyWeather(config, callback)
	} else if (weatherService == 'OpenWeatherMap') {
		OpenWeatherMap.updateHourlyWeather(config, callback)
	} else if (weatherService == 'WeatherCanada') {
		WeatherCanada.updateHourlyWeather(config, callback)
	}
}

/* Return true if all configuration has been setup. */
function weatherIsSetup(config) {
	var weatherService = config.weatherService
	if (weatherService == 'OpenMeteo') {
		return OpenMeteo.weatherIsSetup(config)
	} else if (weatherService == 'OpenWeatherMap') {
		return OpenWeatherMap.weatherIsSetup(config)
	} else if (weatherService == 'WeatherCanada') {
		return WeatherCanada.weatherIsSetup(config)
	} else {
		return false
	}
}

// The most severe of the icons (eg: a day's from its hours): see IconSeverity.js.
function getMostSevereIcon(weatherIconList) {
	return IconSeverity.mostSevere(weatherIconList)
}
