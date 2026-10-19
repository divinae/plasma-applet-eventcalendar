// Daily forecast by day (package/contents/ui/DayWeather.js).
const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const strip = s => s.replace(/^\.pragma library\s*$/m, '').replace(/^\.import .*$/mg, '')
const ui = path.join(__dirname, '../package/contents/ui')
const Shared = {}
vm.runInNewContext(strip(fs.readFileSync(path.join(ui, 'Shared.js'), 'utf8')), Shared)
const W = { Shared }
vm.runInNewContext(strip(fs.readFileSync(path.join(ui, 'DayWeather.js'), 'utf8')), W)

const sec = d => d.getTime() / 1000
const monday = { dt: sec(new Date(2026, 9, 19, 12)), temp: { min: 4, max: 11 }, iconName: 'weather-clouds' }
const tuesday = { dt: sec(new Date(2026, 9, 20, 0, 30)), temp: { min: 2, max: 9 } }
const map = W.byDay({ list: [monday, tuesday] })
assert.strictEqual(Object.keys(map).length, 2)
assert.strictEqual(map[Shared.dayKey(new Date(2026, 9, 19))], monday, 'by local day')
assert.strictEqual(map[Shared.dayKey(new Date(2026, 9, 20, 23))], tuesday, 'any time of the day')
assert.strictEqual(map[Shared.dayKey(new Date(2026, 9, 21))], undefined)
assert.deepStrictEqual(Object.keys(W.byDay(null)), [], 'no data')
assert.deepStrictEqual(Object.keys(W.byDay({ list: [] })), [], 'empty list')
assert.deepStrictEqual(Object.keys(W.byDay({})), [], 'no list')
console.log('day_weather ok')
