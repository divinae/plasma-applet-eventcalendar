.pragma library

// The Weather panel's hourly chart: the parts that don't draw. points: hourly items
// ({ dt (seconds), temp, iconName, precipitation }), evenly spaced in time.

// Where the time `nowMs` is, as a fractional point index (1.5: halfway between the 2nd and the 3rd
// point), or -1 outside the chart.
function nowIndex(points, nowMs) {
	if (!points || points.length < 2) {
		return -1
	}
	var first = points[0].dt * 1000
	var step = points[1].dt * 1000 - first
	var index = (nowMs - first) / step
	return step > 0 && index >= 0 && index <= points.length - 1 ? index : -1
}

// Night or day for each point, from its icon: a night icon (weather-clear-night, ...) is night,
// one that has a night variant (weather-clear, ...) is day. The others (overcast, fog, snow, ...)
// look the same at night: they take the nearest point that tells, earlier ones first.
var DAY_ICONS = [
	'weather-clear', 'weather-few-clouds', 'weather-clouds', 'weather-showers', 'weather-showers-scattered',
	'weather-snow-rain', 'weather-snow-scattered-day', 'weather-storm',
]
function nightFlags(points) {
	var known = points.map(function(point) {
		var name = String(point.iconName || '')
		if (name.indexOf('night') >= 0) {
			return true
		}
		return DAY_ICONS.indexOf(name) >= 0 ? false : null
	})
	return known.map(function(night, i) {
		for (var d = 1; night === null && d < known.length; d++) {
			if (i - d >= 0 && known[i - d] !== null) {
				night = known[i - d]
			} else if (i + d < known.length && known[i + d] !== null) {
				night = known[i + d]
			}
		}
		return night === true
	})
}

// Night stretches as point index ranges [{ from, to }]; a stretch reaches halfway to its day
// neighbours (the step between two points is the change).
function nightRanges(points) {
	var flags = nightFlags(points)
	var ranges = []
	for (var i = 0; i < flags.length; i++) {
		if (!flags[i]) {
			continue
		}
		var from = i === 0 ? 0 : i - 0.5
		while (i + 1 < flags.length && flags[i + 1]) {
			i++
		}
		ranges.push({ from: from, to: i === flags.length - 1 ? i : i + 0.5 })
	}
	return ranges
}

// A smooth curve through the points that doesn't overshoot them (monotone cubic, Fritsch-Carlson):
// a high or a low stays the highest or lowest point of the line. One bezier segment per pair:
// [{ cp1x, cp1y, cp2x, cp2y, x, y }], drawn from (xs[0], ys[0]).
function smoothSegments(xs, ys) {
	var n = xs.length
	var segments = []
	if (n < 2) {
		return segments
	}
	var slopes = []
	for (var i = 0; i < n - 1; i++) {
		slopes.push((ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i]))
	}
	var tangents = [slopes[0]]
	for (var j = 1; j < n - 1; j++) {
		tangents.push(slopes[j - 1] * slopes[j] <= 0 ? 0 : (slopes[j - 1] + slopes[j]) / 2)
	}
	tangents.push(slopes[n - 2])
	for (var k = 0; k < n - 1; k++) {
		if (slopes[k] === 0) {
			tangents[k] = tangents[k + 1] = 0
			continue
		}
		var a = tangents[k] / slopes[k]
		var b = tangents[k + 1] / slopes[k]
		var h = a * a + b * b
		if (h > 9) {
			var t = 3 / Math.sqrt(h)
			tangents[k] = t * a * slopes[k]
			tangents[k + 1] = t * b * slopes[k]
		}
	}
	for (var m = 0; m < n - 1; m++) {
		var dx = (xs[m + 1] - xs[m]) / 3
		segments.push({
			cp1x: xs[m] + dx, cp1y: ys[m] + tangents[m] * dx,
			cp2x: xs[m + 1] - dx, cp2y: ys[m + 1] - tangents[m + 1] * dx,
			x: xs[m + 1], y: ys[m + 1],
		})
	}
	return segments
}

//--- Temperature colors (Settings > Weather > Units)
function toCelsius(temp, units) {
	return units === 'imperial' ? (temp - 32) * 5 / 9 : units === 'kelvin' ? temp - 273.15 : temp
}
function fromCelsius(celsius, units) {
	return units === 'imperial' ? celsius * 9 / 5 + 32 : units === 'kelvin' ? celsius + 273.15 : celsius
}

// From frost blue to heat red, by degrees Celsius.
var TEMP_COLORS = [
	[-10, '#6a5acd'],
	[0, '#3d8fe0'],
	[10, '#2bb3a3'],
	[18, '#8cc63f'],
	[24, '#f2b134'],
	[30, '#f07c2a'],
	[36, '#e0403a'],
]

// Gradient stops for temperatures from minTemp (at 1, the bottom) to maxTemp (at 0, the top):
// [{ position, color }]; the colors of the temperatures in between, the range's ends interpolated.
function temperatureStops(minTemp, maxTemp, units) {
	var low = toCelsius(minTemp, units)
	var high = toCelsius(maxTemp, units)
	if (high - low < 1) {
		high = low + 1
	}
	function position(celsius) {
		return 1 - (celsius - low) / (high - low)
	}
	var stops = [{ position: 1, color: colorAt(low) }]
	for (var i = 0; i < TEMP_COLORS.length; i++) {
		if (TEMP_COLORS[i][0] > low && TEMP_COLORS[i][0] < high) {
			stops.push({ position: position(TEMP_COLORS[i][0]), color: TEMP_COLORS[i][1] })
		}
	}
	stops.push({ position: 0, color: colorAt(high) })
	return stops.reverse()
}

function colorAt(celsius) {
	if (celsius <= TEMP_COLORS[0][0]) {
		return TEMP_COLORS[0][1]
	}
	for (var i = 1; i < TEMP_COLORS.length; i++) {
		if (celsius <= TEMP_COLORS[i][0]) {
			var lower = TEMP_COLORS[i - 1]
			var upper = TEMP_COLORS[i]
			return mix(lower[1], upper[1], (celsius - lower[0]) / (upper[0] - lower[0]))
		}
	}
	return TEMP_COLORS[TEMP_COLORS.length - 1][1]
}

function mix(colorA, colorB, t) {
	function channel(color, i) {
		return parseInt(color.substr(1 + i * 2, 2), 16)
	}
	var out = '#'
	for (var i = 0; i < 3; i++) {
		var value = Math.round(channel(colorA, i) + (channel(colorB, i) - channel(colorA, i)) * t)
		out += (value < 16 ? '0' : '') + value.toString(16)
	}
	return out
}

//--- Rain
// The rain peaks worth a label: the points with more rain than both neighbours (a plateau: its
// first point), at least `gap` points apart (the larger peak wins).
function rainPeaks(points, gap) {
	var rain = points.map(function(point) {
		return point.precipitation || 0
	})
	var peaks = []
	for (var i = 0; i < rain.length; i++) {
		var before = i > 0 ? rain[i - 1] : 0
		var after = i + 1 < rain.length ? rain[i + 1] : 0
		if (rain[i] > 0 && rain[i] > before && rain[i] >= after) {
			peaks.push(i)
		}
	}
	peaks.sort(function(a, b) {
		return rain[b] - rain[a] || a - b
	})
	var kept = []
	peaks.forEach(function(peak) {
		var near = kept.some(function(other) {
			return Math.abs(other - peak) < gap
		})
		if (!near) {
			kept.push(peak)
		}
	})
	return kept.sort(function(a, b) {
		return a - b
	})
}

function rainTotal(points) {
	return points.reduce(function(sum, point) {
		return sum + (point.precipitation || 0)
	}, 0)
}
