// Akonadi calendars of a PimCalendarsModel (package/contents/ui/calendars/PlasmaCalendarUtils.js).
const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const U = {}
vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../package/contents/ui/calendars/PlasmaCalendarUtils.js'), 'utf8')
	.replace(/^\.pragma library\s*$/m, ''), U)

const UserRole = 256, DisplayRole = 0
// A model of rows (optionally with children), each a map of role -> value.
function model(rows) {
	return {
		rowCount: parent => (parent ? parent.row.children || [] : rows).length,
		index: (row, column, parent) => ({ row: (parent ? parent.row.children : rows)[row] }),
		hasChildren: i => !!(i.row.children && i.row.children.length),
		data: (i, role) => i.row[role],
	}
}

// Current kdepim-addons: flat, with roles; accounts have enabled = false.
const flat = model([
	{ [UserRole + 1]: 1490, [UserRole + 2]: 'me@example.com', [UserRole + 3]: false, [UserRole + 4]: false },
	{ [UserRole + 1]: 1506, [UserRole + 2]: 'me@example.com', [UserRole + 3]: true, [UserRole + 4]: true },
	{ [UserRole + 1]: 1505, [UserRole + 2]: 'Support', [UserRole + 3]: true, [UserRole + 4]: false },
])
assert.deepStrictEqual(JSON.parse(JSON.stringify(U.pimCalendarRows(flat, UserRole, DisplayRole))), [
	{ id: '1506', name: 'me@example.com', checked: true },
	{ id: '1505', name: 'Support', checked: false },
])

// Older versions: a tree with a { id, enabled } object.
const tree = model([
	{ [DisplayRole]: 'Personal', [UserRole + 1]: { id: 7, enabled: true }, children: [
		{ [DisplayRole]: 'Birthdays', [UserRole + 1]: { id: 8, enabled: false } },
	] },
])
assert.deepStrictEqual(JSON.parse(JSON.stringify(U.pimCalendarRows(tree, UserRole, DisplayRole))), [
	{ id: '7', name: 'Personal', checked: true },
	{ id: '8', name: 'Birthdays', checked: false },
])
// Current versions are a tree under the accounts: calendars in folders of an account too.
const nested = model([
	{ [UserRole + 1]: 1, [UserRole + 2]: 'Work (DAV)', [UserRole + 3]: false, [UserRole + 4]: false, children: [
		{ [UserRole + 1]: 2, [UserRole + 2]: 'Team', [UserRole + 3]: false, [UserRole + 4]: false, children: [
			{ [UserRole + 1]: 3, [UserRole + 2]: 'Releases', [UserRole + 3]: true, [UserRole + 4]: true },
		] },
	] },
])
assert.deepStrictEqual(JSON.parse(JSON.stringify(U.pimCalendarRows(nested, UserRole, DisplayRole))), [
	{ id: '3', name: 'Releases', checked: true },
], 'a calendar two folders down')
assert.deepStrictEqual(Array.from(U.pimCalendarRows(null, UserRole, DisplayRole)), [])

console.log('PASS plasma_calendar_utils')
