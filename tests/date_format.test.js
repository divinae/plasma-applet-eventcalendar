// A date format without its year (package/contents/ui/Shared.js formatWithoutYear): the
// Agenda's title (#16), with the year's own word and the word before it.
const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const source = fs.readFileSync(path.join(__dirname, '../package/contents/ui/Shared.js'), 'utf8')
	.replace(/^\.pragma library\s*$/m, '')
	.replace(/^\.import .*$/mg, '')
const S = {}
vm.runInNewContext(source, S)

const cases = {
	'dddd, d MMMM yyyy': 'dddd, d MMMM', // pl, en_GB
	'dddd, MMMM d, yyyy': 'dddd, MMMM d', // en_US
	'dddd, d. MMMM yyyy': 'dddd, d. MMMM', // de
	'yyyy年M月d日dddd': 'M月d日dddd', // ja, zh
	"dddd, d MMMM yyyy 'г'.": 'dddd, d MMMM', // ru
	'yyyy년 MMMM d일 dddd': 'MMMM d일 dddd', // ko
	'dddd, d בMMMM yyyy': 'dddd, d בMMMM', // he
	"dddd, d 'de' MMMM 'de' yyyy": "dddd, d 'de' MMMM", // es, pt
	"dddd, d MMMM 'de' yyyy": 'dddd, d MMMM', // ca
}
for (const [format, expected] of Object.entries(cases)) {
	assert.strictEqual(S.formatWithoutYear(format), expected, format)
}
console.log('date_format: ok')
