// The new-event calendar picker's choices (package/contents/ui/lib/CalendarSelection.js).
const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const S = {}
vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../package/contents/ui/lib/CalendarSelection.js'), 'utf8')
	.replace(/^\.pragma library\s*$/m, ''), S)

const account = 'me@example.com'
const calendars = [
	{ id: 'acc::school', summary: account + ' - School', calendarName: 'School', accountLabel: account, accessRole: 'reader' },
	{ id: 'acc::family', summary: account + ' - Family', calendarName: 'Family', accountLabel: account, accessRole: 'owner' },
	{ id: 'acc::me', summary: account + ' - ' + account, calendarName: account, accountLabel: account, accessRole: 'owner', primary: true },
	{ id: 'acc::tasks', summary: 'My Tasks (tasks)', accessRole: 'owner', isTasklist: true },
]
const ids = choices => JSON.parse(JSON.stringify(choices.calendars.map(c => c.id)))
const selected = choices => choices.calendars[choices.selectedIndex].id

// Nothing remembered: the primary calendar, not the first writable one (a shared family calendar).
let choices = S.buildChoices(calendars, '')
assert.deepStrictEqual(ids(choices), ['acc::family', 'acc::me', 'acc::tasks'], 'only those one can add to')
assert.strictEqual(selected(choices), 'acc::me')

// The remembered one wins; a remembered read-only one is still listed and selected.
assert.strictEqual(selected(S.buildChoices(calendars, 'acc::tasks')), 'acc::tasks')
assert.strictEqual(selected(S.buildChoices(calendars, 'acc::school')), 'acc::school')

// No primary calendar (CalDAV, .ics): the first one.
assert.strictEqual(S.buildChoices(calendars.filter(c => !c.primary), 'missing').selectedIndex, 0)
assert.strictEqual(S.buildChoices([], '').calendars.length, 0)

// Labels: the calendar first, then its account; a primary one named after its account once.
assert.strictEqual(S.choiceLabel(calendars[1]), 'Family (me@example.com)')
assert.strictEqual(S.choiceLabel(calendars[2]), account)
assert.strictEqual(S.choiceLabel({ calendarName: account, accountLabel: account, primary: false }), account + ' (' + account + ')')
assert.strictEqual(S.choiceLabel({ calendarName: 'Personal', accountLabel: account, primary: true }), 'Personal (' + account + ')')
assert.strictEqual(S.choiceLabel(calendars[3]), 'My Tasks (tasks)', 'no name and account: its summary')

console.log('PASS calendar_selection')
