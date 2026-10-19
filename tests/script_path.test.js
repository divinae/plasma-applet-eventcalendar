// Helper script paths (package/contents/ui/ScriptPath.js).
const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const ui = path.join(__dirname, '../package/contents/ui')
const source = fs.readFileSync(path.join(ui, 'ScriptPath.js'), 'utf8').replace(/^\.pragma library\s*$/m, '')
const base = 'file:///home/Jan%20Kowalski/.local/share/plasma/plasmoids/org.kde.plasma.eventcalendar/contents/ui/'
const S = {
	// Qt.resolvedUrl in a JS library resolves against the library's own URL.
	Qt: { resolvedUrl: relative => new URL(relative, base).href },
}
vm.runInNewContext(source, S)

assert.strictEqual(S.localPath('file:///tmp/a%20b/%C5%BC.ics'), '/tmp/a b/ż.ics', 'percent-decoded')
assert.strictEqual(S.localPath('file:///tmp/100%25.ics'), '/tmp/100%.ics')
assert.strictEqual(S.localPath('/already/a path'), '/already/a path', 'paths stay')
assert.strictEqual(S.scriptPath('icsjson.py'),
	'/home/Jan Kowalski/.local/share/plasma/plasmoids/org.kde.plasma.eventcalendar/contents/scripts/icsjson.py',
	'an install path with a space')

// Every helper script is located through scriptPath (no hand-built file:// stripping).
const qmlFiles = []
const walk = dir => {
	for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
		const full = path.join(dir, entry.name)
		if (entry.isDirectory()) {
			walk(full)
		} else if (entry.name.endsWith('.qml')) {
			qmlFiles.push(full)
		}
	}
}
walk(ui)
for (const file of qmlFiles) {
	const text = fs.readFileSync(file, 'utf8')
	assert.doesNotMatch(text, /resolvedUrl\(["'][./]*scripts\//, `${path.relative(ui, file)} must use ScriptPath.scriptPath`)
}

console.log('PASS script_path')
