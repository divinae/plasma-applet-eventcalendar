const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const source = fs.readFileSync(
	path.join(__dirname, '../package/contents/ui/code/GooglePalette.js'),
	'utf8'
).replace(/^\.pragma library\s*/, '')
const palette = {}
vm.runInNewContext(source, palette)

function testPaletteListsTheCurrentColors() {
	assert.strictEqual(palette.calendarPalette.length, 24)
	const colors = palette.calendarPalette.map((entry) => entry.color)
	assert.strictEqual(new Set(colors).size, 24)
	// Every classic color maps to one of them.
	Object.keys(palette.calendarColors).forEach((classic) => {
		assert.ok(colors.includes(palette.calendarColors[classic]), classic)
	})
}

function testClassicColorsAreMapped() {
	assert.strictEqual(palette.calendarColor('#9a9cff'), '#7986cb')
	assert.strictEqual(palette.calendarColor({ backgroundColor: '#92e1c0', colorId: '13' }), '#33b679')
}

function testCurrentColorsPassThrough() {
	// A color set from the widget's picker shows as is, whatever colorId Google still reports.
	assert.strictEqual(palette.calendarColor({ backgroundColor: '#8e24aa', colorId: '13' }), '#8e24aa')
	assert.strictEqual(palette.calendarColor('#039be5'), '#039be5')
}

function testUnknownColorsFallBackToColorId() {
	assert.strictEqual(palette.calendarColor({ backgroundColor: '#dadada', colorId: '1' }), '#795548')
	assert.strictEqual(palette.calendarColor({ backgroundColor: '#123456' }), '#123456')
}

function testEventPalette() {
	assert.strictEqual(palette.eventPalette.length, 11)
	palette.eventPalette.forEach((entry, i) => {
		assert.strictEqual(entry.id, String(i + 1))
		assert.strictEqual(entry.color, palette.eventColors[entry.id])
		assert.strictEqual(palette.eventColor(entry.id), entry.color)
	})
	assert.deepStrictEqual({ ...palette.eventPalette[0] }, { id: '1', name: 'Lavender', color: '#7986cb' })
	assert.deepStrictEqual({ ...palette.eventPalette[10] }, { id: '11', name: 'Tomato', color: '#d50000' })
	assert.strictEqual(new Set(palette.eventPalette.map((e) => e.name)).size, 11)
}

testPaletteListsTheCurrentColors()
testEventPalette()
testClassicColorsAreMapped()
testCurrentColorsPassThrough()
testUnknownColorsFallBackToColorId()
