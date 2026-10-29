// Popup keyboard shortcuts (package/contents/ui/KeyNav.js).
const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const read = name => fs.readFileSync(path.join(__dirname, '../package/contents/ui', name), 'utf8')
	.replace(/^\.pragma library\s*$/m, '').replace(/^\.import .*$/mg, '')
const K = {}
vm.runInNewContext(read('KeyNav.js'), K)
const Shared = {}
vm.runInNewContext(read('Shared.js'), Shared)
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

// Week, Day: left / right go to the previous / next period; up / down are left alone.
for (const mode of ['week', 'today']) {
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
for (const mode of ['month', 'week', 'today', 'classic']) {
	assert.deepStrictEqual(act(Key.N, 0, mode), { type: 'new' })
	assert.deepStrictEqual(act(Key.Slash, 0, mode), { type: 'search' })
	assert.deepStrictEqual(act(Key.Slash, Modifier.Shift, mode), { type: 'search' }) // Shift+7 on German layouts
	assert.deepStrictEqual(act(Key.F, Modifier.Control, mode), { type: 'search' })
	assert.deepStrictEqual(act(Key.T, 0, mode), { type: 'today' })
	assert.deepStrictEqual(act(Key.Home, 0, mode), { type: 'today' })
}
assert.deepStrictEqual(['1', '2', '3', '4'].map(c => act(c.charCodeAt(0), 0, 'month').mode),
	['month', 'week', 'today', 'classic'])
assert.deepStrictEqual(act(0x34, Modifier.Keypad, 'week'), { type: 'view', mode: 'classic' }) // Keypad 4
assert.deepStrictEqual(act(0x35, 0, 'month'), { type: 'view', mode: 'tasks' }) // 5: Tasks
assert.strictEqual(K.actionFor(0x36, 0, 'month'), null) // 6: no view

// Tasks: no days; left / right, pages and "today" are left to the list. New, search and views stay.
for (const key of [Key.Left, Key.Right, Key.PageUp, Key.PageDown, Key.T, Key.Home]) {
	assert.strictEqual(K.actionFor(key, 0, 'tasks'), null, 'tasks ' + key)
}
assert.deepStrictEqual(act(Key.N, 0, 'tasks'), { type: 'new' })
// Tasks: Up / Down move the highlighted task; Enter, Space, E and Delete act on it.
assert.deepStrictEqual(act(Key.Up, 0, 'tasks'), { type: 'taskMove', delta: -1 })
assert.deepStrictEqual(act(Key.Down, 0, 'tasks'), { type: 'taskMove', delta: 1 })
assert.deepStrictEqual(act(Key.Return, 0, 'tasks'), { type: 'taskOpen' })
assert.deepStrictEqual(act(Key.Enter, Modifier.Keypad, 'tasks'), { type: 'taskOpen' })
assert.deepStrictEqual(act(Key.Space, 0, 'tasks'), { type: 'taskToggle' })
assert.deepStrictEqual(act(Key.E, 0, 'tasks'), { type: 'taskEdit' })
assert.deepStrictEqual(act(Key.Delete, 0, 'tasks'), { type: 'taskDelete' })
assert.strictEqual(K.actionFor(Key.E, Modifier.Shift, 'tasks'), null)
assert.strictEqual(K.actionFor(Key.Delete, Modifier.Control, 'tasks'), null)
// Elsewhere they aren't shortcuts.
for (const mode of ['month', 'week', 'today', 'classic']) {
	for (const key of [Key.Space, Key.E, Key.Delete]) {
		assert.strictEqual(K.actionFor(key, 0, mode), null, mode + ' ' + key)
	}
}
assert.deepStrictEqual(act(Key.Slash, 0, 'tasks'), { type: 'search' })
assert.deepStrictEqual(act(0x31, 0, 'tasks'), { type: 'view', mode: 'month' })

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

// Moving days (PopupView, with Shared.js): calendar days, across months and DST changes.
const ymd = d => [d.getFullYear(), d.getMonth() + 1, d.getDate(), d.getHours()]
const moveDays = (date, n) => Shared.startOfDay(Shared.addDays(date, n))
assert.deepStrictEqual(ymd(moveDays(new Date(2026, 9, 31, 15), 1)), [2026, 11, 1, 0])
assert.deepStrictEqual(ymd(moveDays(new Date(2026, 2, 3), -7)), [2026, 2, 24, 0])
assert.deepStrictEqual(ymd(moveDays(new Date(2026, 2, 28), 1)), [2026, 3, 29, 0])
assert.deepStrictEqual(ymd(moveDays(new Date(2026, 11, 28), 7)), [2027, 1, 4, 0])

// G: go to a date, in the views with days (not Tasks).
assert.deepStrictEqual(act(Key.G, 0, 'month'), { type: 'goToDate' })
assert.deepStrictEqual(act(Key.G, 0, 'week'), { type: 'goToDate' })
assert.strictEqual(K.actionFor(Key.G, 0, 'tasks'), null)

console.log('key_nav ok')
