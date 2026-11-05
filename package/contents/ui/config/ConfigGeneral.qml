import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import QtCore
import org.kde.kirigami as Kirigami
import org.kde.kirigamiaddons.formcard as FormCard

import ".."
import "../lib"
import "../ScriptPath.js" as ScriptPath
import "../lib/SettingsTransfer.js" as SettingsTransfer
import "../lib/Base64Compat.js" as Base64Compat

// General: what's about the widget as a whole, not one of its views or sources: its background on
// the desktop, sharing with Glance, the offline start, the settings backup and troubleshooting.
ConfigPage {
	id: page

	ColumnLayout {
		Layout.fillWidth: true
		spacing: 0

		//--- On the desktop
		FormCard.FormHeader {
			title: i18n("Desktop widget")
		}
		FormCard.FormCard {
			FormConfigSwitch {
				text: i18n("Show background")
				configKey: 'showBackground'
			}
		}

		//--- Glance (GlancePublisher)
		FormCard.FormHeader {
			title: i18n("Glance")
		}
		FormCard.FormCard {
			FormConfigSwitch {
				text: i18n("Share events with Glance")
				description: i18n("Today's and tomorrow's events, with meeting links, for the Glance panel widget. Only on this computer; no descriptions or guest addresses.")
				configKey: 'glanceShareEvents'
			}
		}

		//--- Offline start (EventCache.qml)
		FormCard.FormHeader {
			title: i18n("Offline")
		}
		FormCard.FormCard {
			FormConfigSwitch {
				text: i18n("Keep events and tasks for offline start")
				description: i18n("The last loaded events and tasks (no descriptions or notes) are stored in ~/.cache/plasma-eventcalendar and shown until the first refresh. Off: nothing is stored, and the stored copy is deleted.")
				configKey: 'eventCacheEnabled'
			}
		}

		//--- Settings backup (issue #21)
		FormCard.FormHeader {
			title: i18n("Settings Backup")
		}
		FormCard.FormCard {
			FormCard.FormButtonDelegate {
				icon.name: "document-export"
				text: i18n("Export Settings…")
				description: i18n("All settings of this widget to a file, without passwords and sign-ins")
				enabled: !settingsBackup.busy
				onClicked: exportDialog.open()
			}
			FormCard.FormDelegateSeparator {}
			FormCard.FormButtonDelegate {
				icon.name: "document-import"
				text: i18n("Import Settings…")
				description: i18n("From an exported file; press Apply or OK to keep them")
				enabled: !settingsBackup.busy
				onClicked: importDialog.open()
			}
			FormCard.AbstractFormDelegate {
				visible: !!settingsBackup.message
				background: null
				contentItem: Kirigami.InlineMessage {
					visible: true
					type: settingsBackup.isError ? Kirigami.MessageType.Error : Kirigami.MessageType.Positive
					text: settingsBackup.message
				}
			}
		}
		FormCard.FormSectionText {
			text: i18n("Accounts come back with their calendars. On this computer they stay signed in; on another one, sign in again (passwords and sign-ins stay in the system keyring).")
		}

		//--- Troubleshooting
		FormCard.FormHeader {
			title: i18n("Troubleshooting")
		}
		FormCard.FormCard {
			FormConfigSwitch {
				text: i18n("Debug logging and extra settings pages")
				configKey: 'debugging'
			}
		}
	}

	QtObject {
		id: settingsBackup
		property bool busy: false
		property string message: ""
		property bool isError: false
		readonly property string helperPath: ScriptPath.scriptPath("settings_file.py")

		function say(text, error) {
			message = text
			isError = !!error
		}

		// Every setting of the widget: the configuration's keys (also those without a cfg_ property on
		// this page, read and written through the configuration then), and the page's. The *Default
		// ones are left out by SettingsTransfer.
		function keys() {
			var out = (typeof plasmoid !== "undefined" && plasmoid && plasmoid.configuration) ? Array.prototype.slice.call(plasmoid.configuration.keys()) : []
			var plasmaOwn = out.indexOf("minimumWidth") // Plasma's own keys from there (see ConfigAdvanced)
			if (plasmaOwn >= 0) {
				out = out.slice(0, plasmaOwn)
			}
			for (var prop in page) {
				if (prop.indexOf("cfg_") === 0 && out.indexOf(prop.slice(4)) < 0) {
					out.push(prop.slice(4))
				}
			}
			return out
		}

		function exportTo(url) {
			var path = ScriptPath.localPath(url)
			if (!/\.json$/i.test(path)) {
				path += ".json"
			}
			var version = (typeof plasmoid !== "undefined" && plasmoid && plasmoid.metaData) ? plasmoid.metaData.version : ""
			var data = SettingsTransfer.build(keys(), function(key) { return page.configBridge.read(key, undefined) }, version)
			var parts = SettingsTransfer.chunks(Base64Compat.base64EncodeString(JSON.stringify(data, null, "\t")), 48000)
			busy = true
			say("", false)
			function writePart(n) {
				var argv = ["python3", helperPath, "write", "--path", path, "--part", String(n), "--data", parts[n]]
				if (n === parts.length - 1) {
					argv.push("--last")
				}
				backupExec.execArgv(argv, function(cmd, exitCode, exitStatus, stdout, stderr) {
					if (exitCode) {
						settingsBackup.busy = false
						settingsBackup.say(i18n("The file couldn't be written: %1", String(stderr || "").trim()), true)
					} else if (n < parts.length - 1) {
						writePart(n + 1)
					} else {
						settingsBackup.busy = false
						settingsBackup.say(i18n("Exported to %1", path), false)
					}
				})
			}
			writePart(0)
		}

		function importFrom(url) {
			var path = ScriptPath.localPath(url)
			busy = true
			say("", false)
			backupExec.execArgv(["python3", helperPath, "read", "--path", path], function(cmd, exitCode, exitStatus, stdout, stderr) {
				settingsBackup.busy = false
				if (exitCode) {
					settingsBackup.say(i18n("The file couldn't be read: %1", String(stderr || "").trim()), true)
					return
				}
				var result = SettingsTransfer.parse(stdout, function(key) { return page.configBridge.read(key, undefined) })
				if (result.error) {
					settingsBackup.say(i18n("This isn't a settings file of Event Calendar."), true)
					return
				}
				var keys = Object.keys(result.settings)
				keys.forEach(function(key) {
					page.configBridge.write(key, result.settings[key])
				})
				var text = i18np("Imported %1 setting. Press Apply or OK to keep it.", "Imported %1 settings. Press Apply or OK to keep them.", keys.length)
				if (result.skipped.length) {
					text += " " + i18np("Not imported (not in this version, a password or sign-in, or a value of another kind): %2", "%1 not imported (not in this version, passwords or sign-ins, or values of another kind): %2", result.skipped.length, result.skipped.join(", "))
				}
				settingsBackup.say(text, false)
			})
		}
	}
	ExecUtil { id: backupExec }

	FileDialog {
		id: exportDialog
		title: i18n("Export Settings")
		fileMode: FileDialog.SaveFile
		nameFilters: [i18n("Settings (*.json)")]
		defaultSuffix: "json" // Added by the dialog, so it asks before replacing that file
		currentFolder: StandardPaths.writableLocation(StandardPaths.DocumentsLocation)
		selectedFile: currentFolder + "/" + SettingsTransfer.fileName(new Date())
		onAccepted: settingsBackup.exportTo(selectedFile)
	}
	FileDialog {
		id: importDialog
		title: i18n("Import Settings")
		fileMode: FileDialog.OpenFile
		nameFilters: [i18n("Settings (*.json)")]
		currentFolder: StandardPaths.writableLocation(StandardPaths.DocumentsLocation)
		onAccepted: settingsBackup.importFrom(selectedFile)
	}
}
