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

// enabledCalendarPlugins left one character per entry by another port: joined back.
const repair = list => Array.from(U.repairPluginList(list))
assert.deepStrictEqual(repair('holidaysevents.so,pimevents.so'.split('')), ['holidaysevents.so', 'pimevents.so'], 'one character each')
assert.deepStrictEqual(repair(['holidaysevents.so,pimevents.so']), ['holidaysevents.so', 'pimevents.so'], 'several in one entry')
assert.deepStrictEqual(repair(['holidaysevents.so', 'pimevents.so']), ['holidaysevents.so', 'pimevents.so'], 'a sound list as it is')
assert.deepStrictEqual(repair(['h', 'pimevents.so']), ['pimevents.so'], 'a stray letter left out')
assert.deepStrictEqual(repair(['x']), [], 'nothing usable')
assert.deepStrictEqual(repair([]), [])

//--- Akonadi events by color
assert.strictEqual(U.colorKey('#9A9CFF'), '9a9cff')
assert.strictEqual(U.colorKey('#ff9a9cff'), '9a9cff', 'with alpha')
assert.strictEqual(U.colorKey(''), '')
assert.strictEqual(U.colorKey('red'), '')
const prefix = 'plasma_EventsColor_'
const ev = (color, summary) => ({ calendarId: prefix + color, summary })
const groups = JSON.parse(JSON.stringify(U.colorCalendars([
	ev('aaaaaa', 'Standup'), ev('bbbbbb', 'Vacation'), ev('bbbbbb', 'Physio'), ev('bbbbbb', 'Vacation'),
	ev('bbbbbb', 'Dentist'), ev('bbbbbb', 'Review'), { calendarId: 'plasma_Holidays', summary: 'Easter' },
], prefix, 3)))
assert.deepStrictEqual(groups, [
	{ id: prefix + 'aaaaaa', color: '#aaaaaa', count: 1, titles: ['Standup'] },
	{ id: prefix + 'bbbbbb', color: '#bbbbbb', count: 5, titles: ['Vacation', 'Physio', 'Dentist'] },
], 'by color, different titles, other calendars left out')

//--- Akonadi's Google calendars of an account also signed in to in the widget
const mirrored = U.akonadiMirroredCollections([
	'account|akonadi_google_resource_14|Me@Gmail.com',
	'account|akonadi_google_resource_15|work@example.com',
	'collection|1466|akonadi_google_resource_14|RootCollection',
	'collection|1485|akonadi_google_resource_14|de.german#holiday@group.v.calendar.google.com',
	'collection|1486|akonadi_google_resource_14|me@gmail.com',
	'collection|1489|akonadi_google_resource_14|other@group.calendar.google.com',
	'collection|1495|akonadi_google_resource_15|de.german#holiday@group.v.calendar.google.com',
	'collection|1499|akonadi_google_resource_99|me@gmail.com',
	'',
].join('\n'), { 'me@gmail.com': ['me@gmail.com', 'de.german#holiday@group.v.calendar.google.com'] })
assert.deepStrictEqual(JSON.parse(JSON.stringify(mirrored)), { 1485: true, 1486: true },
	"that account's calendars in the widget: not those it lacks, not another account's, not a resource without settings")
assert.deepStrictEqual(JSON.parse(JSON.stringify(U.akonadiMirroredCollections('', { 'me@gmail.com': ['me@gmail.com'] }))), {}, 'no database: none')

console.log('PASS plasma_calendar_utils')
