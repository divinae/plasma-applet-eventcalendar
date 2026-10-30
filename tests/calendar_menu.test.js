// The popup's calendar menu in sections (package/contents/ui/Shared.js calendarMenuSections).
const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const source = fs.readFileSync(path.join(__dirname, '../package/contents/ui/Shared.js'), 'utf8')
	.replace(/^\.pragma library\s*$/m, '')
	.replace(/^\.import .*$/mg, '')
const S = {}
vm.runInNewContext(source, S)

const menu = entries => JSON.parse(JSON.stringify(S.calendarMenuSections(entries))).map(e => e.id + ':' + e.section)

// The Plasma calendars come first (their manager is bound first), the accounts later.
assert.deepStrictEqual(menu([
	{ id: 'plasma_Holidays', group: '' },
	{ id: 'plasma_EventsColor_92e1c0', group: '' },
	{ id: 'plasma_EventsColor_b99aff', group: '' },
	{ id: 'calendar.ics', group: '' },
	{ id: 'me@gmail.com', group: 'me@gmail.com' },
	{ id: 'team@group.calendar.google.com', group: 'me@gmail.com' },
	{ id: 'inbox', group: 'TickTick' },
]), [
	'me@gmail.com:0', 'team@group.calendar.google.com:0', 'inbox:0',
	'plasma_EventsColor_92e1c0:1', 'plasma_EventsColor_b99aff:1',
	'plasma_Holidays:2', 'calendar.ics:2',
], 'accounts, then Akonadi, then holidays and files; in order within each')

assert.deepStrictEqual(menu([{ id: 'plasma_Events', group: '' }, { id: 'plasma_Holidays', group: '' }]),
	['plasma_Events:1', 'plasma_Holidays:2'], 'Akonadi as one calendar (no colors)')
assert.deepStrictEqual(menu(undefined), [])

console.log('calendar_menu: ok')
