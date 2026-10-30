.pragma library

// Weather icons from the least to the most severe weather: a summary of several (eg: a day's from
// its hours, the meteogram's columns) shows the worst.
var weatherIconBySeverity = [
	// Least Severe
	'weather-clear-night',
	'weather-clear',
	'weather-few-clouds-night',
	'weather-few-clouds',
	'weather-clouds-night',
	'weather-clouds',
	'weather-fog',
	'weather-overcast',
	'weather-showers-scattered-night',
	'weather-showers-scattered',
	'weather-snow-scattered-night',
	'weather-snow-scattered-day',
	'weather-snow',
	'weather-snow-rain-night',
	'weather-snow-rain',
	'weather-showers-night',
	'weather-showers',
	'weather-storm-night',
	'weather-storm',
	'weather-severe-alert',
	// Most severe
]

function mostSevere(weatherIconList) {
	var mostSevereIndex = weatherIconBySeverity.indexOf(weatherIconList[0])
	for (var i = 1; i < weatherIconList.length; i++) {
		var index = weatherIconBySeverity.indexOf(weatherIconList[i])
		mostSevereIndex = Math.max(mostSevereIndex, index)
	}
	if (mostSevereIndex === -1) {
		return weatherIconList[0]
	}
	return weatherIconBySeverity[mostSevereIndex]
}
