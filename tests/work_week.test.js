// Week view "Work week" columns (package/contents/ui/Shared.js workDayOffsets).
const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const source = fs.readFileSync(path.join(__dirname, '../package/contents/ui/Shared.js'), 'utf8')
	.replace(/^\.pragma library\s*$/m, '')
	.replace(/^\.import .*$/mg, '')
const S = {}
vm.runInNewContext(source, S)

const monToFri = [1, 2, 3, 4, 5]
const same = (actual, expected, message) => assert.deepStrictEqual(Array.from(actual), expected, message)

// Week from Monday (getDay 1): the first five days.
same(S.workDayOffsets(1, monToFri), [0, 1, 2, 3, 4], 'Monday start')
// Week from Sunday: Monday to Friday are days 1..5.
same(S.workDayOffsets(0, monToFri), [1, 2, 3, 4, 5], 'Sunday start')
// Week from Saturday: Monday to Friday are days 2..6.
same(S.workDayOffsets(6, monToFri), [2, 3, 4, 5, 6], 'Saturday start')
// Week from Wednesday (custom setting): week order, the weekend in the middle is left out.
same(S.workDayOffsets(3, monToFri), [0, 1, 2, 5, 6], 'Wednesday start')
// Locale with a Friday / Saturday weekend (Sunday..Thursday, Sunday = 7), week from Saturday.
same(S.workDayOffsets(6, [7, 1, 2, 3, 4]), [1, 2, 3, 4, 5], 'Sunday to Thursday')
// No locale data: Monday to Friday.
same(S.workDayOffsets(1, []), [0, 1, 2, 3, 4], 'no working days given')
same(S.workDayOffsets(1, undefined), [0, 1, 2, 3, 4], 'undefined working days')

console.log('work_week: ok')
