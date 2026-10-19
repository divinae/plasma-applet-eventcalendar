// Popup keyboard shortcuts (package/contents/ui/KeyNav.js).
const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const read = name => fs.readFileSync(path.join(__dirname, '../package/contents/ui', name), 'utf8')
	.replace(/^\.pragma library\s*$/m, '').replace(/^\.import .*$/mg, '')
const K = {}
vm.runInNewContext(read('KeyNav.js'), K)
const { Key, Modifier } = K
const act = (key, mods, mode) => JSON.parse(JSON.stringify(K.actionFor(key, mods, mode)))

// Month: arrows move the selected day (a week up / down), PageUp / PageDown change the month.
assert.deepStrictEqual(act(Key.Left, 0, 'month'), { type: 'move', days: -1 })
assert.deepStrictEqual(act(Key.Right, 0, 'month'), { type: 'move', days: 1 })
assert.deepStrictEqual(act(Key.Up, 0, 'month'), { type: 'move', days: -7 })
assert.deepStrictEqual(act(Key.Down, 0, 'month'), { type: 'move', days: 7 })
assert.deepStrictEqual(act(Key.PageUp, 0, 'month'), { type: 'previous' })
assert.deepStrictEqual(act(Key.PageDown, 0, 'month'), { type: 'next' })
assert.deepStrictEqual(act(Key.Return, 0, 'month'), { type: 'open' })
assert.deepStrictEqual(act(Key.Enter, Modifier.Keypad, 'month'), { type: 'open' })

// Week, Day, Year: left / right go to the previous / next period; up / down are left alone.
for (const mode of ['week', 'today', 'year']) {
	assert.deepStrictEqual(act(Key.Left, 0, mode), { type: 'previous' }, mode)
	assert.deepStrictEqual(act(Key.Right, 0, mode), { type: 'next' }, mode)
	assert.strictEqual(K.actionFor(Key.Up, 0, mode), null, mode)
	assert.strictEqual(K.actionFor(Key.Down, 0, mode), null, mode)
	assert.strictEqual(K.actionFor(Key.Return, 0, mode), null, mode)
}

// Agenda: left / right pick the previous / next day; up / down scroll the list (not handled).
assert.deepStrictEqual(act(Key.Left, 0, 'classic'), { type: 'move', days: -1 })
assert.deepStrictEqual(act(Key.Right, 0, 'classic'), { type: 'move', days: 1 })
assert.strictEqual(K.actionFor(Key.Down, 0, 'classic'), null)
// Enter on an agenda tile opens the tile (the tile takes it), not a day.
assert.strictEqual(K.actionFor(Key.Return, 0, 'classic'), null)

// Everywhere: new, search, today, views.
for (const mode of ['month', 'week', 'today', 'classic', 'year']) {
	assert.deepStrictEqual(act(Key.N, 0, mode), { type: 'new' })
	assert.deepStrictEqual(act(Key.Slash, 0, mode), { type: 'search' })
	assert.deepStrictEqual(act(Key.Slash, Modifier.Shift, mode), { type: 'search' }) // Shift+7 on German layouts
	assert.deepStrictEqual(act(Key.F, Modifier.Control, mode), { type: 'search' })
	assert.deepStrictEqual(act(Key.T, 0, mode), { type: 'today' })
	assert.deepStrictEqual(act(Key.Home, 0, mode), { type: 'today' })
}
assert.deepStrictEqual(['1', '2', '3', '4', '5'].map(c => act(c.charCodeAt(0), 0, 'month').mode),
	['month', 'week', 'today', 'classic', 'year'])
assert.deepStrictEqual(act(0x35, Modifier.Keypad, 'week'), { type: 'view', mode: 'year' }) // Keypad 5
assert.strictEqual(K.actionFor(0x36, 0, 'month'), null) // 6: no view

// Modifiers: not ours (Ctrl+N, Alt+Left, Shift+T, Meta+1, Ctrl+Shift+F).
assert.strictEqual(K.actionFor(Key.N, Modifier.Control, 'month'), null)
assert.strictEqual(K.actionFor(Key.Left, Modifier.Alt, 'week'), null)
assert.strictEqual(K.actionFor(Key.T, Modifier.Shift, 'month'), null)
assert.strictEqual(K.actionFor(0x31, Modifier.Meta, 'month'), null)
assert.strictEqual(K.actionFor(Key.F, Modifier.Control | Modifier.Shift, 'month'), null)
// Esc and Tab are left to Plasma / the focus chain; other letters do nothing.
assert.strictEqual(K.actionFor(Key.Escape, 0, 'month'), null)
assert.strictEqual(K.actionFor(Key.Tab, 0, 'classic'), null)
assert.strictEqual(K.actionFor(0x41, 0, 'month'), null) // A

// Text fields keep their keys.
assert.strictEqual(K.isTextInput({ cursorPosition: 3, selectAll() {} }), true)
assert.strictEqual(K.isTextInput({ text: 'Label' }), false)
assert.strictEqual(K.isTextInput(null), false)

// Moving days: calendar days, across months and DST changes.
const ymd = d => [d.getFullYear(), d.getMonth() + 1, d.getDate(), d.getHours()]
assert.deepStrictEqual(ymd(K.addDays(new Date(2026, 9, 31, 15), 1)), [2026, 11, 1, 0])
assert.deepStrictEqual(ymd(K.addDays(new Date(2026, 2, 3), -7)), [2026, 2, 24, 0])
assert.deepStrictEqual(ymd(K.addDays(new Date(2026, 2, 28), 1)), [2026, 3, 29, 0])
assert.deepStrictEqual(ymd(K.addDays(new Date(2026, 11, 28), 7)), [2027, 1, 4, 0])

console.log('key_nav ok')
