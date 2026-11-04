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

// Popup views: month / week / agenda, calendar look and, for the agenda layout, its widgets.
ConfigPage {
	id: page

	readonly property bool agendaMode: page.configBridge.read("popupMode", "classic") === 'classic'

	ColumnLayout {
		Layout.fillWidth: true
		spacing: 0

		//--- Popup
		FormCard.FormHeader {
			title: i18n("Popup")
		}
		FormCard.FormCard {
			FormConfigCombo {
				text: i18n("Default view")
				configKey: 'popupMode'
				model: [
					{ value: 'month', text: i18n("Month") },
					{ value: 'week', text: i18n("Week") },
					{ value: 'today', text: i18nc("calendar view showing one day", "Day") },
					{ value: 'classic', text: i18n("Agenda") },
					// Shown when task lists are selected (Tasks settings), else the month.
					{ value: 'tasks', text: i18n("Tasks") },
				]
			}
			FormCard.FormDelegateSeparator {}
			// On: the Default view is only for the first time it opens.
			FormConfigSwitch {
				text: i18n("Open in the last used view")
				configKey: 'popupOpenLastView'
			}
			FormCard.FormDelegateSeparator {}
			FormConfigCombo {
				text: i18n("View switcher")
				configKey: 'viewSwitcher'
				model: [
					{ value: 'tabs', text: i18n("Tabs") },
					// One button with the view shown and a menu: little room taken.
					{ value: 'menu', text: i18n("Drop-down menu") },
				]
			}
			// The views the switcher offers, as one row of checkboxes (at least one calendar view
			// stays; Tasks is only offered with task lists selected).
			FormCard.AbstractFormDelegate {
				id: tabsRow
				readonly property var hidden: page.configBridge.read("hiddenViewTabs", []) || []
				readonly property int calendarViewsShown: ['month', 'week', 'today', 'classic'].filter(function(mode) {
					return hidden.indexOf(mode) < 0
				}).length
				background: null
				contentItem: ColumnLayout {
					spacing: Kirigami.Units.smallSpacing
					QQC2.Label {
						text: i18n("Views offered")
						textFormat: Text.PlainText
					}
					Flow {
						Layout.fillWidth: true
						spacing: Kirigami.Units.largeSpacing
						Repeater {
							model: [
								{ mode: 'month', text: i18n("Month") },
								{ mode: 'week', text: i18n("Week") },
								{ mode: 'today', text: i18nc("calendar view showing one day", "Day") },
								{ mode: 'classic', text: i18n("Agenda") },
								{ mode: 'tasks', text: i18n("Tasks") },
							]
							QQC2.CheckBox {
								text: modelData.text
								checked: tabsRow.hidden.indexOf(modelData.mode) < 0
								enabled: !checked || modelData.mode === 'tasks' || tabsRow.calendarViewsShown > 1
								onToggled: {
									var list = Array.prototype.slice.call(tabsRow.hidden).filter(function(mode) {
										return mode !== modelData.mode
									})
									if (!checked) {
										list.push(modelData.mode)
									}
									page.configBridge.write("hiddenViewTabs", list)
								}
							}
						}
					}
				}
			}
			FormCard.FormDelegateSeparator {}
			FormConfigRange {
				label: i18n("Popup size")
				firstKey: 'monthModeWidth'
				firstFrom: 300
				firstTo: 3000
				secondKey: 'monthModeHeight'
				secondFrom: 250
				secondTo: 3000
				stepSize: 10
				separator: "×"
				suffix: i18n(" px")
			}
		}

		//--- Appearance
		FormCard.FormHeader {
			title: i18n("Appearance")
		}
		FormCard.FormCard {
			FormConfigCombo {
				text: i18n("Style")
				description: i18n("Islands: the calendar grids, the Day view's panels, the agenda days and the task sections each sit in a rounded card.")
				configKey: 'uiStyle'
				model: [
					{ value: 'islands', text: i18n("Islands (cards)") },
					{ value: 'flat', text: i18n("Flat") },
				]
			}
			FormCard.FormDelegateSeparator {}
			FormConfigSwitch {
				text: i18n("Animations")
				description: i18n("Views slide and fade in, cards open, the small month's days ease.")
				configKey: 'animationsEnabled'
			}
			FormCard.FormDelegateSeparator {}
			FormConfigCombo {
				text: i18n("Event look")
				configKey: 'eventLook'
				model: [
					{ value: 'bar', text: i18n("All-day filled, timed light with a color bar") },
					{ value: 'solid', text: i18n("Filled in the event color") },
				]
			}
			FormCard.FormDelegateSeparator {}
			FormConfigCombo {
				text: i18n("Event colors")
				description: i18n("Google's API still returns an older palette; \"As in Google Calendar\" shows the current one. \"Follow the system color scheme\" uses the nearest colors of your Plasma color scheme.")
				configKey: 'googleColorPalette'
				model: [
					{ value: 'current', text: i18n("As in Google Calendar") },
					{ value: 'classic', text: i18n("Classic (as returned by Google)") },
					{ value: 'system', text: i18n("Follow the system color scheme") },
				]
			}
			FormCard.FormDelegateSeparator {}
			FormConfigSpin {
				label: i18n("Event text size")
				configKey: 'eventFontScale'
				suffix: "%"
				from: 70
				to: 160
				stepSize: 10
			}
		}

		//--- Calendar
		FormCard.FormHeader {
			title: i18n("Calendar")
		}
		FormCard.FormCard {
			FormConfigCombo {
				text: i18n("First day of week")
				configKey: 'firstDayOfWeek'
				// -1 = locale default, 0..6 = Sunday..Saturday
				model: {
					var list = [{ text: i18n("Default"), value: -1 }]
					for (var i = 0; i < 7; i++) {
						list.push({ text: Qt.locale().dayName(i), value: i })
					}
					return list
				}
			}
			FormCard.FormDelegateSeparator {}
			FormConfigSwitch {
				text: i18n("Week numbers")
				configKey: 'monthShowWeekNumbers'
			}
			FormCard.FormDelegateSeparator {}
			FormConfigSwitch {
				text: i18n("Clicking a day opens it in the Day view")
				description: i18n("Month view")
				configKey: 'monthClickOpensDay'
			}
			FormCard.FormDelegateSeparator {}
			FormConfigCombo {
				text: i18n("Double-clicking a day")
				configKey: 'monthDayDoubleClick'
				model: [
					{ value: 'GoogleCalWeb', text: i18n("New event in Google Calendar (browser)") },
					{ value: 'DoNothing', text: i18n("Do nothing") },
				]
			}
			FormCard.FormDelegateSeparator {}
			FormConfigCombo {
				text: i18n("Declined events")
				configKey: 'showDeclinedEvents'
				model: [
					{ value: true, text: i18n("Show (struck through)") },
					{ value: false, text: i18nc("declined events", "Hide") },
				]
			}
			FormCard.FormDelegateSeparator {}
			FormConfigSwitch {
				text: i18n("Show an event in several calendars once")
				description: i18n("A meeting in your calendar and in a shared one, for example.")
				configKey: 'hideDuplicateEvents'
			}
		}

		//--- Week and Day
		FormCard.FormHeader {
			title: i18n("Week and Day")
		}
		FormCard.FormCard {
			FormConfigCombo {
				text: i18nc("week view setting", "Days shown")
				configKey: 'weekViewWorkWeek'
				model: [
					{ value: false, text: i18n("7 days") },
					{ value: true, text: i18n("Work week (without the weekend)") },
				]
			}
			FormCard.FormDelegateSeparator {}
			FormConfigRange {
				label: i18n("Working hours")
				firstKey: 'weekViewStartHour'
				firstFrom: 0
				firstTo: 23
				secondKey: 'weekViewEndHour'
				secondFrom: 1
				secondTo: 24
				suffix: ":00"
			}
			FormCard.FormDelegateSeparator {}
			// An extra column of hour labels in another time zone.
			FormCard.AbstractFormDelegate {
				id: secondZoneDelegate
				property string zone: page.configBridge.read("weekViewSecondTimeZone", "") || ""
				function setZone(value) {
					zone = value
					page.configBridge.write("weekViewSecondTimeZone", value)
					zoneSearch.text = ""
				}
				background: null
				contentItem: ColumnLayout {
					spacing: Kirigami.Units.smallSpacing
					RowLayout {
						Layout.fillWidth: true
						QQC2.Label {
							Layout.fillWidth: true
							text: i18n("Second time zone")
						}
						QQC2.Label {
							text: secondZoneDelegate.zone ? secondZoneDelegate.zone.replace(/_/g, ' ') : i18nc("no second time zone", "None")
							opacity: 0.7
						}
						QQC2.ToolButton {
							visible: secondZoneDelegate.zone !== ""
							icon.name: "edit-clear"
							onClicked: secondZoneDelegate.setZone("")
							Accessible.name: QQC2.ToolTip.text
							QQC2.ToolTip.text: i18n("No second time zone")
							QQC2.ToolTip.visible: hovered
						}
					}
					QQC2.Label {
						Layout.fillWidth: true
						wrapMode: Text.Wrap
						font: Kirigami.Theme.smallFont
						opacity: 0.7
						text: i18n("Its hours are shown next to the local ones in the Week and Day views.")
					}
					Kirigami.SearchField {
						id: zoneSearch
						Layout.fillWidth: true
						placeholderText: i18n("Search time zones")
						autoAccept: false // Enter picks the highlighted zone
						Keys.onUpPressed: zoneList.moveUp()
						Keys.onDownPressed: zoneList.moveDown()
						onAccepted: zoneList.pickCurrent()
					}
					TimeZoneList {
						id: zoneList
						visible: zoneSearch.text !== ""
						Layout.fillWidth: true
						Layout.preferredHeight: Kirigami.Units.gridUnit * 8
						query: zoneSearch.text
						currentZone: secondZoneDelegate.zone
						onPicked: function(zone) { secondZoneDelegate.setZone(zone) }
					}
				}
			}
			FormCard.FormDelegateSeparator {}
			FormConfigSwitch {
				text: i18n("Weather")
				description: i18n("Forecast in the day headers and, in the Day view, a weather panel.")
				configKey: 'weatherShowInViews'
			}
			FormCard.FormDelegateSeparator {}
			// The Day view's panels beside the hours, one row of checkboxes.
			FormCard.AbstractFormDelegate {
				background: null
				contentItem: ColumnLayout {
					spacing: Kirigami.Units.smallSpacing
					QQC2.Label {
						Layout.fillWidth: true
						text: i18n("Day view shows")
						textFormat: Text.PlainText
					}
					Flow {
						Layout.fillWidth: true
						spacing: Kirigami.Units.largeSpacing
						Repeater {
							model: [
								{ key: 'dayShowMiniMonth', text: i18n("Small calendar") },
								{ key: 'dayShowUpNext', text: i18n("Up next") },
								{ key: 'dayShowMoon', text: i18n("Moon"), off: true }, // Off by default
								{ key: 'dayShowWeather', text: i18n("Weather") },
								{ key: 'dayShowTasks', text: i18n("Tasks") },
							]
							QQC2.CheckBox {
								text: modelData.text
								checked: page.configBridge.read(modelData.key, !modelData.off) === true
								onToggled: page.configBridge.write(modelData.key, checked)
							}
						}
					}
				}
			}
			FormCard.FormDelegateSeparator {}
			FormConfigSpin {
				label: i18n("Up next shows")
				hint: i18n("The days after the shown one; later ones under \"Show more\"")
				configKey: 'dayUpNextDays'
				// The unit as the number asks for it (1 day, 2 days; in Polish 1 dzień, 2 dni, 5 dni).
				unitFor: function(n) { return i18ncp("number of days, after the number", "day", "days", n) }
				from: 1
				to: 30
			}
			FormCard.FormDelegateSeparator {}
			FormConfigSwitch {
				text: i18n("All-day events side by side")
				description: i18n("In the Day view, three or more all-day events take a third of the width each, three in a row. Hovering one shows it in full.")
				configKey: 'dayAllDayTiles'
			}
		}

		//--- Agenda (classic mode only)
		FormCard.FormHeader {
			visible: page.agendaMode
			title: i18n("Agenda")
		}
		FormCard.FormCard {
			visible: page.agendaMode
			FormConfigSwitch {
				text: i18n("Event descriptions")
				configKey: 'agendaShowEventDescription'
			}
			FormCard.FormDelegateSeparator {}
			FormConfigSwitch {
				text: i18n("Meeting link button")
				configKey: 'agendaShowEventHangoutLink'
			}
			FormCard.FormDelegateSeparator {}
			FormConfigSwitch {
				text: i18n("Multi-day events on every day")
				configKey: 'agendaBreakupMultiDayEvents'
			}
			FormCard.FormDelegateSeparator {}
			FormConfigSwitch {
				text: i18n("Meteogram above the agenda")
				configKey: 'widgetShowMeteogram'
			}
			FormCard.FormDelegateSeparator {}
			FormConfigSwitch {
				id: widgetShowTimer
				text: i18n("Timer above the agenda")
				configKey: 'widgetShowTimer'
			}
			FormCard.FormDelegateSeparator {
				visible: widgetShowTimer.checked
			}
			FormCard.AbstractFormDelegate {
				visible: widgetShowTimer.checked
				background: null
				contentItem: RowLayout {
					spacing: Kirigami.Units.largeSpacing
					QQC2.Label {
						text: i18n("Timer sound")
					}
					ConfigSound {
						Layout.fillWidth: true
						label: ""
						sfxEnabledKey: 'timerSfxEnabled'
						sfxPathKey: 'timerSfxFilepath'
						sfxPathDefaultValue: '/usr/share/sounds/ocean/stereo/alarm-clock-elapsed.oga'
					}
				}
			}
			FormCard.FormDelegateSeparator {}
			FormConfigSpin {
				label: i18n("Meteogram / timer height")
				configKey: 'topRowHeight'
				suffix: i18n(" px")
				from: 50
				to: 3000
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
