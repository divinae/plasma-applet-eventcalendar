// Every setting in main.xml has its cfg_ property on the settings pages (lib/ConfigPage.qml), so it's
// applied with OK / Apply. The exceptions are state the widget keeps itself: given to a page, OK
// would write back the value the dialog opened with and undo what the widget changed meanwhile.
const assert = require('assert')
const fs = require('fs')
const path = require('path')

const root = path.join(__dirname, '../package/contents')
const keys = [...fs.readFileSync(path.join(root, 'config/main.xml'), 'utf8').matchAll(/<entry name="([^"]+)"/g)].map(m => m[1])
const page = fs.readFileSync(path.join(root, 'ui/lib/ConfigPage.qml'), 'utf8')

const widgetState = [
	'popupLastView', // The last view (main.qml)
	'hiddenHeaderButtons', // The header's own menu
	'dayTasksScope', // The Day view's task panel menu
	'importRequest', // Settings > Calendars > Import: written straight to the widget
	'cameraDevice', 'cameraMirrored', // The camera check's choices
	'mutedEventKeys', // Mute Notifications, per event
	'clockHiddenCalendarIds', // The popup's calendar menu
]

const missing = keys.filter(k => !page.includes(`property var cfg_${k}\n`))
assert.deepStrictEqual(missing.filter(k => !widgetState.includes(k)), [], 'settings without a cfg_ property in ConfigPage.qml')
assert.deepStrictEqual(widgetState.filter(k => !missing.includes(k)), [], 'widget state that got a cfg_ property (OK would undo its changes)')
assert.deepStrictEqual(widgetState.filter(k => !keys.includes(k)), [], 'allowlisted keys gone from main.xml')
console.log('config_page_keys: ok')
