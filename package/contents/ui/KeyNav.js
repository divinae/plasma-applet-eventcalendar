.pragma library

// Keyboard shortcuts in the popup: key press -> action. Plain JS (Qt key codes below) so it can
// be tested without Qt. PopupView runs the actions.

var Key = {
	Escape: 0x01000000,
	Tab: 0x01000001,
	Return: 0x01000004,
	Enter: 0x01000005,
	Delete: 0x01000007,
	Home: 0x01000010,
	Left: 0x01000012,
	Up: 0x01000013,
	Right: 0x01000014,
	Down: 0x01000015,
	PageUp: 0x01000016,
	PageDown: 0x01000017,
	Space: 0x20,
	Slash: 0x2f,
	Digit1: 0x31,
	E: 0x45,
	F: 0x46,
	N: 0x4e,
	T: 0x54,
}

var Modifier = {
	Shift: 0x02000000,
	Control: 0x04000000,
	Alt: 0x08000000,
	Meta: 0x10000000,
	Keypad: 0x20000000,
}

// The view tabs in header order: the number keys 1-5 pick them (Tasks: when shown).
var VIEW_MODES = ['month', 'week', 'today', 'classic', 'tasks']

// Actions:
//   { type: 'previous' } / { type: 'next' }: the previous / next month, week or day
//   { type: 'move', days: n }: move the selected day by n days
//   { type: 'open' }: open the selected day (Day view)
//   { type: 'new' }: new event on the selected day
//   { type: 'search' }, { type: 'today' }
//   { type: 'view', mode: 'month' }: switch the view
//   Tasks tab: { type: 'taskMove', delta: -1 | 1 } (Up / Down: the highlighted task), 'taskOpen'
//   (Enter), 'taskToggle' (Space), 'taskEdit' (E), 'taskDelete' (Delete); N ('new') is "Add a task…"
// null: not a shortcut, the key goes on to Plasma (eg: Esc closes the popup).
function actionFor(key, modifiers, mode) {
	var mods = (modifiers || 0) & ~Modifier.Keypad
	var ctrl = (mods & Modifier.Control) !== 0
	var alt = (mods & (Modifier.Alt | Modifier.Meta)) !== 0
	if (alt) {
		return null
	}
	if (ctrl) {
		// Ctrl+F: search. Other Ctrl shortcuts belong to Plasma / the system.
		return (key === Key.F && mods === Modifier.Control) ? { type: 'search' } : null
	}
	// "/" needs Shift on some layouts (eg: German Shift+7): ignore Shift for it.
	if (key === Key.Slash) {
		return { type: 'search' }
	}
	var shift = (mods & Modifier.Shift) !== 0
	if (shift) {
		return null
	}

	if (mode === 'tasks') {
		switch (key) {
			case Key.Up: return { type: 'taskMove', delta: -1 }
			case Key.Down: return { type: 'taskMove', delta: 1 }
			case Key.Return:
			case Key.Enter: return { type: 'taskOpen' }
			case Key.Space: return { type: 'taskToggle' }
			case Key.E: return { type: 'taskEdit' }
			case Key.Delete: return { type: 'taskDelete' }
		}
	}

	var grid = mode === 'month'
	var agenda = mode === 'classic'
	// Tasks: no days to move through; the arrows scroll the list.
	var dated = mode !== 'tasks'
	switch (key) {
		case Key.Left:
			return !dated ? null : grid || agenda ? { type: 'move', days: -1 } : { type: 'previous' }
		case Key.Right:
			return !dated ? null : grid || agenda ? { type: 'move', days: 1 } : { type: 'next' }
		case Key.Up:
			return grid ? { type: 'move', days: -7 } : null
		case Key.Down:
			return grid ? { type: 'move', days: 7 } : null
		case Key.PageUp:
			return dated ? { type: 'previous' } : null
		case Key.PageDown:
			return dated ? { type: 'next' } : null
		case Key.Return:
		case Key.Enter:
			return grid ? { type: 'open' } : null
		case Key.N:
			return { type: 'new' }
		case Key.T:
		case Key.Home:
			return dated ? { type: 'today' } : null
	}
	var digit = key - Key.Digit1
	if (digit >= 0 && digit < VIEW_MODES.length) {
		return { type: 'view', mode: VIEW_MODES[digit] }
	}
	return null
}

// A text field / area (or a spin box's text) has the focus: its keys are for typing.
function isTextInput(item) {
	return !!item && typeof item.cursorPosition === 'number' && typeof item.selectAll === 'function'
}
