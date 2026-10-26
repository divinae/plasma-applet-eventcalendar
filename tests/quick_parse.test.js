const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const source = fs.readFileSync(path.join(__dirname, '../package/contents/ui/QuickParse.js'), 'utf8')
	.replace(/^\.pragma library\s*$/m, '')
const Q = {}
vm.runInNewContext(source + '\nObject.assign(out, { parse, tokenKey })', { out: Q })

const plain = o => JSON.parse(JSON.stringify(o))
const today = '2026-10-26' // A Monday
const lists = [
	{ id: 'g::home', name: 'Home' },
	{ id: 'g::work', name: 'Work stuff' },
	{ id: 'tt::homework', name: 'Homework' },
	{ id: 'tt::inbox', name: 'Inbox' },
	{ id: 'tt::zakupy', name: 'Zakupy' },
]
const parse = (text, more) => Q.parse(text, Object.assign({ today, lists }, more))
// Only the fields given in want are compared.
const check = (text, want, more) => {
	const got = plain(parse(text, more))
	const picked = {}
	for (const k of Object.keys(want)) picked[k] = got[k]
	assert.deepStrictEqual(picked, want, JSON.stringify(text))
}

// The full example
{
	const r = plain(parse('Buy milk tomorrow 17:00 !high #Home every week'))
	assert.deepStrictEqual(Object.assign({}, r, { tokens: undefined }), {
		title: 'Buy milk', dueDay: '2026-10-27', dueTime: '17:00', priority: 5, listId: 'g::home',
		repeatRule: 'RRULE:FREQ=WEEKLY;INTERVAL=1', tokens: undefined,
	})
	assert.deepStrictEqual(r.tokens.map(t => [t.kind, t.text, t.start, t.end]), [
		['date', 'tomorrow', 9, 17], ['time', '17:00', 18, 23], ['priority', '!high', 24, 29],
		['list', '#Home', 30, 35], ['repeat', 'every week', 36, 46],
	])
}
check('Kupić mleko jutro o 17 !wysoki #zakupy co tydzień', {
	title: 'Kupić mleko', dueDay: '2026-10-27', dueTime: '17:00', priority: 5, listId: 'tt::zakupy', repeatRule: 'RRULE:FREQ=WEEKLY;INTERVAL=1',
})
check('Nothing special here', { title: 'Nothing special here', dueDay: '', dueTime: '', priority: 0, listId: '', repeatRule: '', tokens: [] })
check('', { title: '', tokens: [] })

// Relative days (English)
check('a today', { title: 'a', dueDay: today })
check('a tomorrow', { dueDay: '2026-10-27' })
check('a tmrw', { dueDay: '2026-10-27' })
check('a day after tomorrow', { title: 'a', dueDay: '2026-10-28' })
check('a the day after tomorrow', { title: 'a', dueDay: '2026-10-28' })
check('a in 3 days', { title: 'a', dueDay: '2026-10-29' })
check('a in 2 weeks', { dueDay: '2026-11-09' })
check('a in a week', { dueDay: '2026-11-02' })
check('a in 1 month', { dueDay: '2026-11-26' })
check('a next week', { title: 'a', dueDay: '2026-11-02' })
// Weekdays: the next one, never today (Monday 26 October)
check('a friday', { title: 'a', dueDay: '2026-10-30' })
check('a Fri', { dueDay: '2026-10-30' })
check('a monday', { dueDay: '2026-11-02' })
check('a next monday', { title: 'a', dueDay: '2026-11-02' })
check('a on Tuesday', { title: 'a', dueDay: '2026-10-27' })
check('a sunday', { dueDay: '2026-11-01' })
// Polish
check('a dziś', { title: 'a', dueDay: today })
check('a dzisiaj', { dueDay: today })
check('a jutro', { dueDay: '2026-10-27' })
check('a pojutrze', { title: 'a', dueDay: '2026-10-28' })
check('a za 3 dni', { title: 'a', dueDay: '2026-10-29' })
check('a za tydzień', { title: 'a', dueDay: '2026-11-02' })
check('a za 2 tygodnie', { dueDay: '2026-11-09' })
check('a w przyszły poniedziałek', { title: 'a', dueDay: '2026-11-02' })
check('a w przyszłym tygodniu', { title: 'a', dueDay: '2026-11-02' })
check('a w piątek', { title: 'a', dueDay: '2026-10-30' })
check('a pt', { dueDay: '2026-10-30' })
check('a śr', { dueDay: '2026-10-28' })
check('a środę', { dueDay: '2026-10-28' })
check('a czw', { dueDay: '2026-10-29' })
check('a wt', { dueDay: '2026-10-27' })
check('a sob', { dueDay: '2026-10-31' })
check('a niedz', { dueDay: '2026-11-01' })
check('a niedzielę', { dueDay: '2026-11-01' })
check('a Pon', { dueDay: '2026-11-02' })

// Dates
check('a 28.10', { title: 'a', dueDay: '2026-10-28' })
check('a 28.10.2026', { title: 'a', dueDay: '2026-10-28' })
check('a 28.10.27', { dueDay: '2027-10-28' })
check('a 20.10', { dueDay: '2027-10-20' }, ) // Past this year: next year
check('a 31.11', { title: 'a 31.11', dueDay: '' }) // No 31 November
check('a 2026-12-01', { title: 'a', dueDay: '2026-12-01' })
check('a 10/28', { dueDay: '2026-10-28' })
check('a 28/10', { dueDay: '2026-10-28' }) // Only one order works
check('a 10/11', { dueDay: '2026-11-10' }, { dayFirst: true })
check('a 10/11', { dueDay: '2027-10-11' }, { dayFirst: false }) // 11 October is past
check('a 11/10', { dueDay: '2026-11-10' }, { dayFirst: false })
check('a Oct 28', { title: 'a', dueDay: '2026-10-28' })
check('a October 28th', { dueDay: '2026-10-28' })
check('a 28 Oct', { title: 'a', dueDay: '2026-10-28' })
check('a on 28 Oct 2027', { title: 'a', dueDay: '2027-10-28' })
check('a Dec 1, 2026', { title: 'a', dueDay: '2026-12-01' })
check('a 28 października', { title: 'a', dueDay: '2026-10-28' })
check('a 3 listopada', { dueDay: '2026-11-03' })
check('a 29 Feb', { dueDay: '2028-02-29' })
// "May" is a name unless next to a day number
check('Call May tomorrow', { title: 'Call May', dueDay: '2026-10-27' })
check('Call May', { title: 'Call May', dueDay: '' })
check('a May 5', { title: 'a', dueDay: '2027-05-05' })
check('a 5 May', { title: 'a', dueDay: '2027-05-05' })
// The locale's names (here German) passed in
check('a Freitag', { title: 'a', dueDay: '2026-10-30' }, { dayNames: [[], [], [], [], [], ['Freitag'], []] })
check('a 3. Dezember', { title: 'a', dueDay: '2026-12-03' }, { monthNames: [[], [], [], [], [], [], [], [], [], [], [], ['Dezember', 'Dez.']] })

// Times
check('a 17:00', { title: 'a', dueTime: '17:00' })
check('a 9:05', { dueTime: '09:05' })
check('a 17.00', { title: 'a', dueTime: '17:00', dueDay: '' })
check('a 10.30', { dueTime: '10:30', dueDay: '' })
check('a 5pm', { title: 'a', dueTime: '17:00' })
check('a 5 pm', { title: 'a', dueTime: '17:00' })
check('a 5:30pm', { title: 'a', dueTime: '17:30' })
check('a 12am', { dueTime: '00:00' })
check('a 12pm', { dueTime: '12:00' })
check('a 17h', { title: 'a', dueTime: '17:00' })
check('a o 17', { title: 'a', dueTime: '17:00' })
check('a o 12.10', { title: 'a', dueTime: '12:10', dueDay: '' })
check('a at 9', { title: 'a', dueTime: '09:00' })
check('a at 5:30 pm', { title: 'a', dueTime: '17:30' })
check('a @8am', { title: 'a', dueTime: '08:00' })
check('a 24:00', { title: 'a 24:00', dueTime: '' })
check('a 13pm', { title: 'a 13pm', dueTime: '' })
check('a 12:60', { title: 'a 12:60', dueTime: '' })
check('a o 24', { dueTime: '' })

// Priority
check('a !high', { title: 'a', priority: 5 })
check('a !medium', { priority: 3 })
check('a !med', { priority: 3 })
check('a !low', { priority: 1 })
check('a !3', { priority: 5 })
check('a !2', { priority: 3 })
check('a !1', { priority: 1 })
check('a !!!', { title: 'a', priority: 5 })
check('a !!', { title: 'a', priority: 3 })
check('a !', { title: 'a', priority: 1 })
check('!high a', { title: 'a', priority: 5 })
check('Hello! world', { title: 'Hello! world', priority: 0 })
check('a !important', { title: 'a !important', priority: 0 })
check('a !30', { priority: 0 })
check('a !!!!', { priority: 0 })

// Lists
check('a #home', { title: 'a', listId: 'g::home' }) // Exact before Homework
check('a #Homew', { listId: 'tt::homework' })
check('a #hom', { listId: 'g::home' }) // The first by prefix
check('a #work', { title: 'a', listId: 'g::work' })
check('a #nope', { title: 'a #nope', listId: '' })
check('Learn C# today', { title: 'Learn C#', listId: '', dueDay: today })
check('a#home', { title: 'a#home', listId: '' })
check('a #home.', { title: 'a .', listId: 'g::home' })
check('a #Home', { listId: '' }, { lists: [] })

// Repeat
check('a every day', { title: 'a', repeatRule: 'RRULE:FREQ=DAILY;INTERVAL=1' })
check('a every week', { repeatRule: 'RRULE:FREQ=WEEKLY;INTERVAL=1' })
check('a every month', { repeatRule: 'RRULE:FREQ=MONTHLY;INTERVAL=1' })
check('a every year', { repeatRule: 'RRULE:FREQ=YEARLY;INTERVAL=1' })
check('a every 2 weeks', { title: 'a', repeatRule: 'RRULE:FREQ=WEEKLY;INTERVAL=2' })
check('a daily', { title: 'a', repeatRule: 'RRULE:FREQ=DAILY;INTERVAL=1' })
check('a weekly', { repeatRule: 'RRULE:FREQ=WEEKLY;INTERVAL=1' })
check('a monthly', { repeatRule: 'RRULE:FREQ=MONTHLY;INTERVAL=1' })
check('a yearly', { repeatRule: 'RRULE:FREQ=YEARLY;INTERVAL=1' })
check('a every weekday', { repeatRule: 'RRULE:FREQ=WEEKLY;INTERVAL=1;BYDAY=MO,TU,WE,TH,FR' })
// Every monday: from the first one, today included
check('a every monday', { title: 'a', repeatRule: 'RRULE:FREQ=WEEKLY;INTERVAL=1;BYDAY=MO', dueDay: today })
check('a every friday', { repeatRule: 'RRULE:FREQ=WEEKLY;INTERVAL=1;BYDAY=FR', dueDay: '2026-10-30' })
check('a every friday 3.11', { repeatRule: 'RRULE:FREQ=WEEKLY;INTERVAL=1;BYDAY=FR', dueDay: '2026-11-03' })
check('a codziennie', { title: 'a', repeatRule: 'RRULE:FREQ=DAILY;INTERVAL=1' })
check('a co tydzień', { title: 'a', repeatRule: 'RRULE:FREQ=WEEKLY;INTERVAL=1' })
check('a co miesiąc', { repeatRule: 'RRULE:FREQ=MONTHLY;INTERVAL=1' })
check('a co roku', { title: 'a', repeatRule: 'RRULE:FREQ=YEARLY;INTERVAL=1' })
check('a co 2 tygodnie', { repeatRule: 'RRULE:FREQ=WEEKLY;INTERVAL=2' })
check('a co poniedziałek', { title: 'a', repeatRule: 'RRULE:FREQ=WEEKLY;INTERVAL=1;BYDAY=MO' })
check('a w każdy piątek', { title: 'a', repeatRule: 'RRULE:FREQ=WEEKLY;INTERVAL=1;BYDAY=FR', dueDay: '2026-10-30' })

// Not inside words
check('Todayish plans', { title: 'Todayish plans', dueDay: '' })
check('Mondays are hard', { title: 'Mondays are hard', dueDay: '' })
check('Lemonade friday', { title: 'Lemonade', dueDay: '2026-10-30' })
check('version 1.17:00x', { dueTime: '' })
check('Jutrzenka', { dueDay: '' })
check('Sunbathing', { dueDay: '' })
check('Buy sun cream', { title: 'Buy sun cream', dueDay: '' })
check('newsletter', { repeatRule: '', dueDay: '' })

// Only the first of a kind; the rest stays in the title
check('a tomorrow friday', { title: 'a friday', dueDay: '2026-10-27' })
check('a 9:00 10:00', { title: 'a 10:00', dueTime: '09:00' })
// Spaces collapsed
check('  a   tomorrow   b  ', { title: 'a b' })
// Without today: no dates, the rest still works
assert.strictEqual(Q.parse('a tomorrow 17:00', {}).dueDay, '')
assert.strictEqual(Q.parse('a tomorrow 17:00', {}).dueTime, '17:00')

// Ignored tokens stay in the title, and nothing else takes their words
{
	const r = parse('Meet tomorrow 17:00 !high')
	const date = r.tokens.find(t => t.kind === 'date')
	assert.strictEqual(Q.tokenKey(date), 'date:tomorrow')
	check('Meet tomorrow 17:00 !high', { title: 'Meet tomorrow', dueDay: '', dueTime: '17:00', priority: 5 }, { ignore: ['date:tomorrow'] })
	check('Meet Tomorrow', { title: 'Meet Tomorrow', dueDay: '' }, { ignore: ['date:tomorrow'] })
	// "every monday" ignored: "monday" isn't a date either
	check('a every monday', { title: 'a every monday', dueDay: '', repeatRule: '' }, { ignore: ['repeat:every monday'] })
	// An ignored one doesn't stop a later one of its kind
	check('a 9:00 10:00', { title: 'a 9:00', dueTime: '10:00' }, { ignore: ['time:9:00'] })
}

// Only some kinds (events: day and time)
check('Party ! #home tomorrow 20:00 every week', { title: 'Party ! #home every week', dueDay: '2026-10-27', dueTime: '20:00', priority: 0, listId: '', repeatRule: '' },
	{ kinds: ['date', 'time'] })

// Month ends and years
assert.strictEqual(Q.parse('a in 1 month', { today: '2026-01-31' }).dueDay, '2026-02-28')
assert.strictEqual(Q.parse('a tomorrow', { today: '2026-12-31' }).dueDay, '2027-01-01')
assert.strictEqual(Q.parse('a 1.1', { today: '2026-12-31' }).dueDay, '2027-01-01')
assert.strictEqual(Q.parse('a 31.12', { today: '2026-12-31' }).dueDay, '2026-12-31')

console.log('quick_parse tests passed')
