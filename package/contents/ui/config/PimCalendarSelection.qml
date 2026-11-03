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

	property var model: {
		try { // kdepim-addons is optional
			return Qt.createQmlObject("import org.kde.plasma.PimCalendars; PimCalendarsModel {}", selection)
		} catch (e) {
			return null
		}
	}
	readonly property bool canChange: !!model && typeof model.setChecked === "function"
	property var rows: [] // pimCalendarRows, with the accounts
	function updateRows() {
		rows = PlasmaCalendarUtils.pimCalendarRows(model, Qt.UserRole, Qt.DisplayRole, true)
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

	// Akonadi's copies of calendars shown through a Google account signed in to in the widget (the
	// setting, so it follows the Google tab): the widget shows their events once, the account's.
	readonly property var mirrored: {
		var accounts = SafeConfig.parseBase64Json(configBridge.read("googleAccounts", ""), [])
		return PlasmaCalendarUtils.akonadiMirroredCollections(googleCollections,
			PlasmaCalendarUtils.googleCalendarIdsByAccount(Array.isArray(accounts) ? accounts : []))
	}

	// The selection as saved: ids Akonadi no longer has (eg: an account set up anew, its calendars
	// got new ids) are kept by the plugin, but show nothing. Forgotten ones go with the page.
	ExecUtil { id: savedReader }
	property var saved: []
	property var forgotten: ({})
	readonly property var missing: PlasmaCalendarUtils.stalePimSelection(saved, rows).filter(function(id) {
		return !forgotten[id]
	})

	function setChecked(id, checked) {
		if (canChange) {
			model.setChecked(Number(id), checked)
			changed()
		}
	}
	function forgetMissing() {
		if (!canChange) {
			return
		}
		var next = Object.assign({}, forgotten)
		missing.forEach(function(id) {
			model.setChecked(Number(id), false)
			next[id] = true
		})
		forgotten = next
		changed()
	}
	// Through the plugin's model: plasmashell's copy of the config and the plugins follow.
	function save() {
		if (model) {
			model.saveConfig()
		}
	}

	onModelChanged: updateRows()
	Component.onCompleted: {
		updateRows() // The model may be filled already: no reset or insert comes then
		databaseReader.execArgv(PlasmaCalendarUtils.akonadiCalendarsCommand(), function(cmd, exitCode, exitStatus, stdout) {
			selection.colors = PlasmaCalendarUtils.parseAkonadiColors(stdout)
			selection.googleCollections = String(stdout || "")
		})
		savedReader.execArgv(PlasmaCalendarUtils.pimSelectionCommand(), function(cmd, exitCode, exitStatus, stdout) {
			selection.saved = PlasmaCalendarUtils.parsePimSelection(stdout)
		})
	}
}
