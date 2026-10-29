// The Weather panel's hourly chart (package/contents/ui/ForecastChart.js).
const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const strip = s => s.replace(/^\.pragma library\s*$/m, '').replace(/^\.import .*$/mg, '')
const C = {}
vm.runInNewContext(strip(fs.readFileSync(path.join(__dirname, '../package/contents/ui/ForecastChart.js'), 'utf8')), C)
const plain = o => JSON.parse(JSON.stringify(o)) // Objects from the vm context

const hour = 3600
const at = (i, extra) => Object.assign({ dt: 1000 * hour + i * hour, temp: 10 }, extra)

//--- The current time
const points = [at(0), at(1), at(2), at(3)]
assert.strictEqual(C.nowIndex(points, (1000 * hour + 1.5 * hour) * 1000), 1.5)
assert.strictEqual(C.nowIndex(points, (1000 * hour) * 1000), 0)
assert.strictEqual(C.nowIndex(points, (999 * hour) * 1000), -1, 'before the chart')
assert.strictEqual(C.nowIndex(points, (1004 * hour) * 1000), -1, 'after the chart')
assert.strictEqual(C.nowIndex([at(0)], 0), -1)

//--- Nights
const icons = names => names.map((iconName, i) => at(i, { iconName }))
assert.deepStrictEqual(plain(C.nightFlags(icons(['weather-clear', 'weather-overcast', 'weather-clear-night', 'weather-fog', 'weather-fog']))),
	[false, false, true, true, true], 'overcast and fog: like the point before')
assert.deepStrictEqual(plain(C.nightFlags(icons(['weather-fog', 'weather-clouds-night']))), [true, true], 'or after')
assert.deepStrictEqual(plain(C.nightFlags(icons(['weather-fog', 'weather-snow']))), [false, false], 'unknown: day')
assert.deepStrictEqual(plain(C.nightRanges(icons(['weather-clear', 'weather-clear-night', 'weather-clear-night', 'weather-clear']))),
	[{ from: 0.5, to: 2.5 }])
assert.deepStrictEqual(plain(C.nightRanges(icons(['weather-clear-night', 'weather-clear', 'weather-clear-night']))),
	[{ from: 0, to: 0.5 }, { from: 1.5, to: 2 }], 'to the chart edges')

//--- The smooth line: through every point, never beyond a high or a low
const xs = [0, 10, 20, 30, 40]
const ys = [50, 20, 20, 60, 55]
const segments = C.smoothSegments(xs, ys)
assert.strictEqual(segments.length, 4)
segments.forEach((s, i) => {
	assert.deepStrictEqual([s.x, s.y], [xs[i + 1], ys[i + 1]])
	const low = Math.min(ys[i], ys[i + 1]), high = Math.max(ys[i], ys[i + 1])
	for (const y of [s.cp1y, s.cp2y]) {
		assert.ok(y >= low - 1e-9 && y <= high + 1e-9, `segment ${i}: control point ${y} within ${low}..${high}`)
	}
})
assert.deepStrictEqual(plain(C.smoothSegments([0], [1])), [])

//--- Temperature colors
assert.strictEqual(C.colorAt(0), '#3d8fe0')
assert.strictEqual(C.colorAt(-40), '#6a5acd')
assert.strictEqual(C.colorAt(50), '#e0403a')
assert.strictEqual(C.colorAt(5), C.mix('#3d8fe0', '#2bb3a3', 0.5))
assert.ok(Math.abs(C.toCelsius(50, 'imperial') - 10) < 1e-9)
assert.ok(Math.abs(C.fromCelsius(0, 'kelvin') - 273.15) < 1e-9)
const stops = plain(C.temperatureStops(4, 14, 'metric'))
assert.deepStrictEqual(stops.map(s => s.position), [0, 0.4, 1], 'the top first, 10 °C in between')
assert.strictEqual(stops[1].color, '#2bb3a3')
assert.strictEqual(stops[2].color, C.colorAt(4))
assert.strictEqual(plain(C.temperatureStops(50, 50.5, 'imperial')).length, 2, 'a flat line')

//--- Rain
const rain = values => values.map((precipitation, i) => at(i, { precipitation }))
assert.deepStrictEqual(plain(C.rainPeaks(rain([0, 0.2, 0.8, 0.3, 0, 0, 1.5, 1.5, 0]), 3)), [2, 6], 'a plateau: its first point')
assert.deepStrictEqual(plain(C.rainPeaks(rain([0.5, 0, 0.9, 0, 0.4]), 3)), [2], 'close peaks: the larger one')
assert.deepStrictEqual(plain(C.rainPeaks(rain([0, 0, 0]), 3)), [])
assert.ok(Math.abs(C.rainTotal(rain([0.2, 0, 1.3, undefined])) - 1.5) < 1e-9)

console.log('PASS forecast_chart')
