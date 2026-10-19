// Event "when" texts (package/contents/ui/LocaleFuncs.js formatWhen, formatRange).
const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const strip = s => s.replace(/^\.pragma library\s*$/m, '').replace(/^\.import .*$/mg, '')
const ui = path.join(__dirname, '../package/contents/ui')

// Enough of Qt's date formatting for these formats.
const DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
const pad = n => (n < 10 ? '0' : '') + n
function format(d, f) {
	return f.replace(/yyyy|MMM|ddd|HH|mm|d/g, t => ({
		yyyy: d.getFullYear(), MMM: MONTHS[d.getMonth()], ddd: DAYS[d.getDay()],
		HH: pad(d.getHours()), mm: pad(d.getMinutes()), d: d.getDate(),
	})[t])
}
const Qt = { formatDate: format, formatTime: format, formatDateTime: format }
const i18nc = (context, text, ...args) => text.replace(/%(\d)/g, (m, n) => args[n - 1])
const i18n = (text, ...args) => i18nc('', text, ...args)

const Shared = { Qt }
vm.runInNewContext(strip(fs.readFileSync(path.join(ui, 'Shared.js'), 'utf8')), Shared)
const L = { Qt, i18n, i18nc, Shared }
vm.runInNewContext(strip(fs.readFileSync(path.join(ui, 'LocaleFuncs.js'), 'utf8')), L)

const now = new Date(2026, 9, 19, 10, 30)
const timed = (d, h1, h2) => ({
	start: { dateTime: 'x' }, startDateTime: new Date(2026, 9, d, h1), endDateTime: new Date(2026, 9, d, h2),
})
assert.strictEqual(L.formatRange('9:00', '10:00'), '9:00 – 10:00')
assert.strictEqual(L.formatWhen(timed(23, 12, 13), 'HH:mm', now), 'Fri 23 Oct · 12:00 – 13:00', 'timed')
const allDay = { start: { date: '2026-10-23' }, startDateTime: new Date(2026, 9, 23), endDateTime: new Date(2026, 9, 24) }
assert.strictEqual(L.formatWhen(allDay, 'HH:mm', now), 'Fri 23 Oct · All day', 'all day')
const days = { start: { date: '2026-10-14' }, startDateTime: new Date(2026, 9, 14), endDateTime: new Date(2026, 9, 17) }
assert.strictEqual(L.formatWhen(days, 'HH:mm', now), '14 Oct – 16 Oct', 'several days')
const nextYear = { start: { dateTime: 'x' }, startDateTime: new Date(2027, 0, 5, 9), endDateTime: new Date(2027, 0, 5, 10) }
assert.strictEqual(L.formatWhen(nextYear, 'HH:mm', now), 'Tue 5 Jan 2027 · 09:00 – 10:00', 'another year')
const overnight = { start: { dateTime: 'x' }, startDateTime: new Date(2026, 9, 23, 22), endDateTime: new Date(2026, 9, 24, 2) }
assert.strictEqual(L.formatWhen(overnight, 'HH:mm', now), '23 Oct 22:00 – 24 Oct 02:00', 'timed over two days')
console.log('locale_funcs ok')
