const assert = require('assert')
const fs = require('fs')
const path = require('path')

function read(relativePath) {
	return fs.readFileSync(path.join(__dirname, '..', relativePath), 'utf8')
}

const install = read('install')
const update = read('update')
const helper = read('package/contents/scripts/icsjson.py')
const readme = read('ReadMe.md')

assert.ok(install.includes('"python3-pip"') && install.includes('"python-pip"'),
	'install must provide pip on supported distro families')
assert.ok(install.includes("'recurring-ical-events>=3.8,<4'"),
	'install must install the recurrence dependency with a compatible version range')
assert.ok(install.includes('install_requirements\ninstall_python_calendar_dependencies'),
	'install must invoke the user-local recurrence dependency installer')
assert.ok(install.includes('.local/share/plasma_org.kde.plasma.eventcalendar/python'),
	'install must keep Python dependencies out of the system environment')

// update is a thin wrapper: it refuses a dirty tree, then hands over to install
// (which pulls and installs the dependencies above).
assert.ok(install.includes('-r|--restart) restartPlasmashell=true'), 'install must accept --restart')
assert.ok(update.includes('if ! git diff --quiet || ! git diff --cached --quiet; then'),
	'update must refuse a dirty working tree')
assert.ok(update.trimEnd().endsWith('exec bash ./install --restart'),
	'update must hand over to install')

assert.ok(
	helper.includes('sys.path.insert(0, LOCAL_PYTHON_DIR)'),
	'the iCalendar helper must load dependencies from the applet data directory'
)
assert.ok(
	readme.includes('recurring-ical-events>=3.8,<4'),
	'the recurrence dependency must be documented for non-script installs'
)

console.log('PASS install_ical_dependencies')
