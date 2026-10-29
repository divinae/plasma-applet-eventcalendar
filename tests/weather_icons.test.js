// Weather icon styles (package/contents/ui/WeatherIcons.js).
const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const strip = s => s.replace(/^\.pragma library\s*$/m, '').replace(/^\.import .*$/mg, '')
const ui = path.join(__dirname, '../package/contents/ui')
const iconDir = path.join(__dirname, '../package/contents/icons/weather')
const Shared = {}
vm.runInNewContext(strip(fs.readFileSync(path.join(ui, 'Shared.js'), 'utf8')), Shared)
const Qt = { resolvedUrl: url => 'file:///ui/' + url }
const W = { Shared, Qt }
vm.runInNewContext(strip(fs.readFileSync(path.join(ui, 'WeatherIcons.js'), 'utf8')), W)

// Monochrome: the symbolic icon (the default), the full color theme icon for the large one.
assert.strictEqual(W.source('weather-clear', 'monochrome'), 'weather-clear-symbolic')
assert.strictEqual(W.source('weather-clear', undefined), 'weather-clear-symbolic')
assert.strictEqual(W.largeSource('weather-clear', 'monochrome'), 'weather-clear')
assert.strictEqual(W.source('', 'colorful'), '')

// Colorful: a bundled Yr symbol; names without one stay monochrome.
assert.strictEqual(W.source('weather-clouds', 'colorful'), 'file:///ui/../icons/weather/partlycloudy_day.svg')
assert.strictEqual(W.largeSource('weather-overcast', 'colorful'), 'file:///ui/../icons/weather/cloudy.svg')
assert.strictEqual(W.source('wi-tornado', 'colorful'), 'wi-tornado-symbolic')
assert.strictEqual(W.colorful('weather-severe-alert', 'colorful'), false)

// Every symbol is bundled, and every bundled file is used.
const used = new Set(Object.values(W.yrSymbols).map(f => f + '.svg'))
for (const file of used) {
	assert.ok(fs.existsSync(path.join(iconDir, file)), 'bundled: ' + file)
}
for (const file of fs.readdirSync(iconDir).filter(f => f.endsWith('.svg'))) {
	assert.ok(used.has(file), 'used: ' + file)
}
assert.ok(fs.existsSync(path.join(iconDir, 'LICENSE')), 'license')

// Every weather-* icon a weather service gives has a colorful symbol.
const weatherDir = path.join(ui, 'weather')
for (const file of fs.readdirSync(weatherDir)) {
	const names = fs.readFileSync(path.join(weatherDir, file), 'utf8').match(/'weather-[a-z-]+'/g) || []
	for (const quoted of names) {
		const name = quoted.slice(1, -1)
		if (name !== 'weather-severe-alert') {
			assert.ok(W.yrSymbols[name], file + ': ' + name)
		}
	}
}

console.log('PASS weather_icons')
