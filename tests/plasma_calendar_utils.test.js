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
assert.deepStrictEqual(JSON.parse(JSON.stringify(U.pimCalendarRows(flat, UserRole, DisplayRole, true))), [
	{ id: '1490', name: 'me@example.com', checked: false, account: true },
	{ id: '1506', name: 'me@example.com', checked: true },
	{ id: '1505', name: 'Support', checked: false },
], 'with the accounts')

// The plugin's saved selection: ids Akonadi no longer has (an account set up anew).
assert.deepStrictEqual(Array.from(U.parsePimSelection('1386,1486,1501,1486\n')), ['1386', '1486', '1501'])
assert.deepStrictEqual(Array.from(U.parsePimSelection('')), [], 'no selection saved')
const allRows = U.pimCalendarRows(flat, UserRole, DisplayRole, true)
assert.deepStrictEqual(Array.from(U.stalePimSelection(['1490', '1506', '1501', '1386'], allRows)), ['1501', '1386'],
	'an account id saved is not missing')
assert.deepStrictEqual(Array.from(U.stalePimSelection(['1501'], [])), [], 'none before Akonadi is read')

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
], prefix)))
assert.deepStrictEqual(groups, [
	{ id: prefix + 'aaaaaa', color: '#aaaaaa', count: 1 },
	{ id: prefix + 'bbbbbb', color: '#bbbbbb', count: 5 },
], 'by color, other calendars left out')

// Named after the calendars of a color: the shown ones, else the others in it (a model made before
// a calendar was selected in the Digital Clock's settings has it unchecked).
const named = U.namesByColor([
	{ id: '1', name: 'Work', checked: true },
	{ id: '2', name: 'Team', checked: false },
	{ id: '3', name: 'Support', checked: false },
	{ id: '4', name: 'Holidays', checked: true },
	{ id: '5', name: 'No color', checked: true },
], { 1: '#ffaaaaaa', 2: '#aaaaaa', 3: '#ffbbbbbb', 4: '#cccccc' })
assert.deepStrictEqual(JSON.parse(JSON.stringify(named)), { aaaaaa: ['Work'], bbbbbb: ['Support'], cccccc: ['Holidays'] },
	'a shown calendar first; not shown ones only for a color without one')
assert.deepStrictEqual(JSON.parse(JSON.stringify(U.namesByColor([{ id: '1', name: 'Work', checked: true }], undefined))), {},
	'no colors read')

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

const rows = [
	{ id: '1486', name: 'me@gmail.com', checked: true },
	{ id: '1485', name: 'Holidays', checked: true },
	{ id: '20', name: 'Work', checked: true },
	{ id: '21', name: 'Off', checked: false },
]
const colors = { 1486: '#aaaaaa', 1485: '#bbbbbb', 20: '#bbbbbb', 21: '#cccccc' }
assert.deepStrictEqual(JSON.parse(JSON.stringify(U.mirroredColorKeys(rows, colors, { 1486: true, 1485: true, 21: true }))), { aaaaaa: true },
	'a color also of another shown calendar stays; not shown calendars left out')
assert.deepStrictEqual(JSON.parse(JSON.stringify(U.googleCalendarIdsByAccount([
	{ calendarList: [{ id: 'x@group.calendar.google.com' }, { id: 'y@group.calendar.google.com' }, { id: 'Me@Gmail.com', primary: true }],
		calendarIdList: ['x@group.calendar.google.com', 'primary'] },
	{ calendarList: [] },
	null,
]))), { 'me@gmail.com': ['x@group.calendar.google.com', 'Me@Gmail.com'] },
	'only the calendars shown in the widget ("primary" as its id): an Akonadi copy of another one stays')

//--- The Akonadi calendars under their accounts, Google's apart (the Google and Akonadi tabs)
const dbLines = [
	'account|akonadi_google_resource_14|Me@Gmail.com',
	'collection|1466|akonadi_google_resource_14|RootCollection',
	'collection|1486|akonadi_google_resource_14|me@gmail.com',
	'collection|1488|akonadi_google_resource_14|e_2_de#weeknum@group.v.calendar.google.com',
].join('\n')
const groupRows = [
	{ id: '1466', name: 'Google Groupware', checked: false, account: true },
	{ id: '1486', name: 'me@gmail.com', checked: true },
	{ id: '1488', name: 'Week numbers', checked: false },
	{ id: '10', name: 'Personal calendar', checked: false, account: true },
	{ id: '11', name: 'Personal', checked: true },
	{ id: '20', name: 'Birthdays & Anniversaries', checked: false, account: true },
]
const g = JSON.parse(JSON.stringify(U.pimCalendarGroups(groupRows, dbLines)))
assert.deepStrictEqual(g.filter(x => x.google).map(x => [x.name, x.calendars.map(c => c.id)]), [['me@gmail.com', ['1486', '1488']]],
	'a Google account by its email, with its calendars')
assert.deepStrictEqual(g.filter(x => !x.google).map(x => [x.name, x.calendars.map(c => c.id)]), [['Personal calendar', ['11']]],
	'the others under their accounts; an account without calendars left out')
const noDb = JSON.parse(JSON.stringify(U.pimCalendarGroups(groupRows, '')))
assert.deepStrictEqual([noDb.filter(x => x.google).length, noDb.filter(x => !x.google).map(x => x.name)], [0, ['Google Groupware', 'Personal calendar']],
	'without Akonadi\'s database all are others')
assert.deepStrictEqual(JSON.parse(JSON.stringify(U.pimCalendarGroups([{ id: '7', name: 'Old', checked: true }], ''))).filter(x => !x.google),
	[{ name: '', calendars: [{ id: '7', name: 'Old', checked: true }], google: false }], 'calendars without an account (older models)')

// From the model's tree: a calendar that is a resource of its own (a local calendar file) after a
// Google account isn't that account's: in its own group, the last.
const accountTree = model([
	{ [UserRole + 1]: 1490, [UserRole + 2]: 'Google Groupware', [UserRole + 3]: false, [UserRole + 4]: false, children: [
		{ [UserRole + 1]: 1617, [UserRole + 2]: 'work@example.com', [UserRole + 3]: true, [UserRole + 4]: true },
	] },
	{ [UserRole + 1]: 5, [UserRole + 2]: 'Personal calendar', [UserRole + 3]: true, [UserRole + 4]: false, [UserRole + 5]: 'office-calendar' },
	{ [UserRole + 1]: 20, [UserRole + 2]: 'Work (DAV)', [UserRole + 3]: false, [UserRole + 4]: false, children: [
		{ [UserRole + 1]: 21, [UserRole + 2]: 'Team', [UserRole + 3]: false, [UserRole + 4]: false, children: [
			{ [UserRole + 1]: 22, [UserRole + 2]: 'Releases', [UserRole + 3]: true, [UserRole + 4]: true },
		] },
	] },
])
const treeRows = U.pimCalendarRows(accountTree, UserRole, DisplayRole, true)
assert.deepStrictEqual(JSON.parse(JSON.stringify(treeRows)).filter(r => !r.account).map(r => [r.id, r.accountId || '']),
	[['1617', '1490'], ['5', ''], ['22', '20']], 'each calendar with its top account from the tree; in a folder too')
assert.strictEqual(treeRows.filter(r => r.id === '5')[0].icon, 'office-calendar', 'the model\'s icon (eg: a task list\'s)')
const treeGroups = JSON.parse(JSON.stringify(U.pimCalendarGroups(treeRows,
	'account|akonadi_google_resource_15|work@example.com\ncollection|1490|akonadi_google_resource_15|RootCollection\ncollection|1617|akonadi_google_resource_15|work@example.com')))
assert.deepStrictEqual(treeGroups.filter(x => x.google).map(x => [x.name, x.calendars.map(c => c.id)]), [['work@example.com', ['1617']]])
assert.deepStrictEqual(treeGroups.filter(x => !x.google).map(x => [x.name, x.calendars.map(c => c.id)]), [['Work (DAV)', ['22']], ['', ['5']]],
	'the local calendar in its own group, the last; not under the Google account')
assert.deepStrictEqual(JSON.parse(JSON.stringify(U.pimCalendarRows(accountTree, UserRole, DisplayRole))).map(r => Object.keys(r).join()),
	['id,name,checked', 'id,name,checked', 'id,name,checked'], 'without the accounts: rows as before')

console.log('PASS plasma_calendar_utils')
