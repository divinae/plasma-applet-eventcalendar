.pragma library
.import "Shared.js" as Shared

// The weather icon for a forecast item's iconName (weather-clear, weather-showers-night, ...) in the
// style of Settings > Weather > Icons:
// - 'monochrome': the theme's symbolic icon (use with `fallback: name` for themes without one)
// - 'colorful': the Yr weather symbols (MIT, https://github.com/metno/weathericons) in
//   ../icons/weather; the names without one (alerts, tornado, dust, ...) stay monochrome.
var yrSymbols = {
	'weather-clear': 'clearsky_day',
	'weather-clear-night': 'clearsky_night',
	'weather-few-clouds': 'fair_day',
	'weather-few-clouds-night': 'fair_night',
	'weather-clouds': 'partlycloudy_day',
	'weather-clouds-night': 'partlycloudy_night',
	'weather-overcast': 'cloudy',
	'weather-fog': 'fog',
	'weather-freezing-rain': 'sleet',
	'weather-hail': 'heavysleet',
	'weather-showers': 'rain',
	'weather-showers-night': 'rain',
	'weather-showers-scattered': 'rainshowers_day',
	'weather-showers-scattered-night': 'rainshowers_night',
	'weather-snow': 'snow',
	'weather-snow-rain': 'sleetshowers_day',
	'weather-snow-rain-night': 'sleetshowers_night',
	'weather-snow-scattered-day': 'snowshowers_day',
	'weather-snow-scattered-night': 'snowshowers_night',
	'weather-storm': 'rainandthunder',
	'weather-storm-night': 'rainshowersandthunder_night',
}

function colorful(name, style) {
	return style === 'colorful' && !!yrSymbols[name]
}

function source(name, style) {
	if (colorful(name, style)) {
		return Qt.resolvedUrl('../icons/weather/' + yrSymbols[name] + '.svg')
	}
	return Shared.symbolicIcon(name)
}

// A large icon (the Weather panel's "Now"): the theme's full color icon when monochrome.
function largeSource(name, style) {
	if (colorful(name, style)) {
		return source(name, style)
	}
	return name || ''
}
