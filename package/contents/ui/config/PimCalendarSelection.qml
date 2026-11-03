import QtQuick

import "../lib"
import "../lib/SafeConfig.js" as SafeConfig
import "../calendars/PlasmaCalendarUtils.js" as PlasmaCalendarUtils

// Which KDE PIM (Akonadi) calendars the widget shows: the pimevents plugin's own selection
// ([PIMEventsPlugin] calendars= in plasmashellrc), chosen in the Akonadi tab; the Google tab reads
// pimEventsEnabled. One model, saved with the page (ConfigCalendars.saveConfig): a model saves its
// whole selection, so a second one would undo the first's changes.
Item {
	id: selection

	property QtObject configBridge: null
	signal changed() // A calendar ticked or one forgotten: the page has something to apply

	readonly property bool pimEventsEnabled: PlasmaCalendarUtils.hasPlugin(configBridge.read("enabledCalendarPlugins", []), "pimevents")

	// Made (with the reads below) only once the plugin is on: nothing for Akonadi otherwise.
	property var model: null
	function start() {
		if (model || !pimEventsEnabled) {
			return
		}
		model = PlasmaCalendarUtils.createPimCalendarsModel(selection)
		updateRows() // The model may be filled already: no reset or insert comes then
		readDatabase()
		savedReader.execArgv(PlasmaCalendarUtils.pimSelectionCommand(), function(cmd, exitCode, exitStatus, stdout) {
			selection.saved = PlasmaCalendarUtils.parsePimSelection(stdout)
		})
	}
	onPimEventsEnabledChanged: start()
	Component.onCompleted: start()

	readonly property bool canChange: PlasmaCalendarUtils.pimModelCanChoose(model)
	property var rows: [] // pimCalendarRows, with the accounts
	property bool ticking: false // A tick from here: no need to read the database again
	function updateRows() {
		rows = PlasmaCalendarUtils.pimCalendarRows(model, Qt.UserRole, Qt.DisplayRole, true)
		if (!ticking) {
			databaseTimer.restart() // A calendar added or changed (eg: given a color): read them again
		}
	}
	Connections { // Akonadi fills the model asynchronously
		target: selection.model
		function onModelReset() { selection.updateRows() }
		function onRowsInserted() { selection.updateRows() }
		function onRowsRemoved() { selection.updateRows() }
		function onDataChanged() { selection.updateRows() }
	}

	// From Akonadi's database, in one run (PlasmaCalendarUtils.akonadiCalendarsCommand, as the
	// widget reads it): the calendars' colors and Akonadi's Google accounts and calendars (listed
	// first, by email; none when it can't be read).
	ExecUtil { id: databaseReader }
	property var colors: ({})
	property string googleCollections: ""
	readonly property var groups: PlasmaCalendarUtils.pimCalendarGroups(rows, googleCollections)
	function readDatabase() {
		databaseReader.execArgv(PlasmaCalendarUtils.akonadiCalendarsCommand(), function(cmd, exitCode, exitStatus, stdout) {
			selection.colors = PlasmaCalendarUtils.parseAkonadiColors(stdout)
			selection.googleCollections = String(stdout || "")
		})
	}
	Timer {
		id: databaseTimer
		interval: 1000 // Akonadi sends a change in parts: read once they're in
		onTriggered: selection.readDatabase()
	}

	// Akonadi's copies of calendars shown through a Google account signed in to in the widget (the
	// setting, so it follows the Google tab): the widget shows their events once, the account's.
	readonly property var mirrored: {
		var accounts = SafeConfig.parseBase64Json(configBridge.read("googleAccounts", ""), [])
		return PlasmaCalendarUtils.akonadiMirroredCollections(googleCollections,
			PlasmaCalendarUtils.googleCalendarIdsByAccount(PlasmaCalendarUtils.toArray(accounts)))
	}

	// The selection as saved: ids Akonadi no longer has (eg: an account set up anew, its calendars
	// got new ids) are kept by the plugin, but show nothing. Forgotten ones go with the page.
	ExecUtil { id: savedReader }
	property var saved: []
	readonly property var missing: PlasmaCalendarUtils.stalePimSelection(saved, rows)

	function tick(id, checked) {
		ticking = true
		model.setChecked(Number(id), checked)
		ticking = false
	}
	function setChecked(id, checked) {
		if (canChange) {
			tick(id, checked)
			changed()
		}
	}
	function forgetMissing() {
		if (!canChange) {
			return
		}
		var forget = missing
		forget.forEach(function(id) { tick(id, false) })
		saved = saved.filter(function(id) { return forget.indexOf(id) < 0 })
		changed()
	}
	// Through the plugin's model: plasmashell's copy of the config and the plugins follow.
	function save() {
		if (model) {
			model.saveConfig()
		}
	}
}
