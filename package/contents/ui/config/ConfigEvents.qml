import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kirigamiaddons.formcard as FormCard

import "../lib"
import "../calendars/PlasmaCalendarUtils.js" as PlasmaCalendarUtils

// Event sources, clicking events, notifications.
ConfigPage {
	id: page
	property var eventPluginsManager: null

	// Google Meet web apps that can open a meeting link: [{ name, command, authuser }]
	property var meetApps: []
	ExecUtil { id: meetAppFinder }
	function findMeetApps() {
		var script = String(Qt.resolvedUrl("../../scripts/find_meet_apps.py")).replace(/^file:\/\//, "")
		meetAppFinder.execArgv(["python3", "-I", script], function(cmd, exitCode, exitStatus, stdout, stderr) {
			try {
				var apps = JSON.parse(stdout)
				page.meetApps = Array.isArray(apps) ? apps : []
			} catch (e) {
				page.meetApps = []
			}
		})
	}

	// From digitalclock's configCalendar.qml
	signal configurationChanged()
	function saveConfig() {
		if (!eventPluginsManager) {
			return
		}
		var enabledPluginFilenames = PlasmaCalendarUtils.pluginPathToFilenameList(eventPluginsManager.enabledPlugins)
		page.configBridge.write("enabledCalendarPlugins", enabledPluginFilenames)
		page.configBridge.write("enabledCalendarPluginsAllowEmpty", enabledPluginFilenames.length === 0)
	}
	Component.onCompleted: {
		findMeetApps()
		try {
			eventPluginsManager = Qt.createQmlObject(
				"import org.kde.plasma.workspace.calendar as PlasmaCalendar; PlasmaCalendar.EventPluginsManager {}",
				page
			)
		} catch (e) {
			console.warn("[eventcalendar] PlasmaCalendar.EventPluginsManager unavailable:", e)
			return
		}
		PlasmaCalendarUtils.populateEnabledPluginsByFilename(
			eventPluginsManager,
			page.configBridge.read("enabledCalendarPlugins", []),
			page.configBridge.read("enabledCalendarPluginsAllowEmpty", false)
		)
	}

	// A label and a ConfigSound (checkbox, preview, file, browse) in one FormCard row.
	component SoundRow: FormCard.AbstractFormDelegate {
		id: soundRow
		property string label
		property string sfxEnabledKey
		property string sfxPathKey
		property string sfxPathDefaultValue: '/usr/share/sounds/Oxygen-Im-Nudge.ogg'
		background: null
		contentItem: RowLayout {
			spacing: Kirigami.Units.largeSpacing
			QQC2.Label {
				text: soundRow.label
				Layout.minimumWidth: Kirigami.Units.gridUnit * 5
			}
			ConfigSound {
				Layout.fillWidth: true
				label: ""
				sfxEnabledKey: soundRow.sfxEnabledKey
				sfxPathKey: soundRow.sfxPathKey
				sfxPathDefaultValue: soundRow.sfxPathDefaultValue
			}
		}
	}

	ColumnLayout {
		Layout.fillWidth: true
		spacing: 0

		//--- Sources
		FormCard.FormHeader {
			title: i18n("Calendars")
		}
		FormCard.FormCard {
			FormConfigSpin {
				label: i18n("Refresh every")
				configKey: 'eventsPollInterval'
				suffix: i18nc("Polling interval in minutes", " min")
				from: 5
				to: 90
			}
			FormCard.FormDelegateSeparator {}
			FormCard.FormTextDelegate {
				visible: !page.eventPluginsManager
				text: i18n("Plasma calendar plugins are unavailable.")
			}
			FormCard.AbstractFormDelegate {
				visible: !!page.eventPluginsManager
				background: null
				contentItem: ColumnLayout {
					spacing: 0
					QQC2.Label {
						text: i18n("Plasma calendars")
					}
					// A Repeater needs a layout parent (it breaks form layouts' child handling).
					Repeater {
						model: page.eventPluginsManager ? page.eventPluginsManager.model : null
						delegate: QQC2.CheckBox {
							text: model.display
							checked: model.checked
							onClicked: {
								model.checked = checked // needed for model's setData to be called
								page.saveConfig()
							}
						}
					}
				}
			}
			FormCard.FormDelegateSeparator {}
			FormConfigCombo {
				text: i18n("Clicking an event opens")
				configKey: 'eventClickAction'
				model: [
					{ value: 'details', text: i18n("Event details in the widget") },
					{ value: 'browser', text: i18n("Google Calendar in the browser") },
				]
			}
		}

		//--- Reminder
		FormCard.FormHeader {
			title: i18n("Reminder Before an Event")
		}
		FormCard.FormCard {
			FormConfigSwitch {
				id: reminderEnabled
				text: i18n("Show a reminder")
				configKey: 'eventReminderNotificationEnabled'
			}
			FormCard.FormDelegateSeparator {}
			FormConfigSpin {
				enabled: reminderEnabled.checked
				label: i18n("Time before")
				configKey: 'eventReminderMinutesBefore'
				suffix: i18nc("Time in minutes", " min")
				from: 1
				to: 100000
			}
			FormCard.FormDelegateSeparator {}
			FormConfigSwitch {
				enabled: reminderEnabled.checked
				text: i18n("Use the reminder times set in Google Calendar")
				configKey: 'eventReminderUseGoogle'
			}
			FormCard.FormDelegateSeparator {}
			// eventReminderTimeout: 0 = keep until dismissed, N > 0 = hide after N seconds,
			// -1 = Plasma's popup timeout (System Settings > Notifications).
			FormCard.FormSwitchDelegate {
				id: reminderKeep
				enabled: reminderEnabled.checked
				text: i18n("Keep until dismissed")
				checked: page.configBridge.read("eventReminderTimeout", -1) === 0
				onToggled: page.configBridge.write("eventReminderTimeout", checked ? 0 : (reminderHideAfter.value > 0 ? reminderHideAfter.value : -1))
			}
			FormCard.FormDelegateSeparator {}
			FormCard.FormSpinBoxDelegate {
				id: reminderHideAfter
				enabled: reminderEnabled.checked && !reminderKeep.checked
				label: i18n("Hide after")
				// 0 shows as the system's timeout.
				value: Math.max(0, page.configBridge.read("eventReminderTimeout", -1))
				from: 0
				to: 3600
				textFromValue: function(value, locale) {
					return value > 0 ? i18ncp("notification shown for", "%1 second", "%1 seconds", value) : i18nc("notification timeout", "System default")
				}
				valueFromText: function(text, locale) {
					var n = parseInt(text, 10)
					return isNaN(n) ? 0 : n
				}
				onValueModified: page.configBridge.write("eventReminderTimeout", value > 0 ? value : -1)
			}
			FormCard.FormSectionText {
				visible: reminderHideAfter.enabled
				text: i18n("System default: as set in System Settings > Notifications. A reminder hidden after a set time isn't kept in the notification history.")
			}
			FormCard.FormDelegateSeparator {}
			FormConfigSpin {
				enabled: reminderEnabled.checked
				label: i18n("Snooze")
				description: i18n("0 = no Snooze button")
				configKey: 'eventReminderSnoozeMinutes'
				suffix: i18nc("Time in minutes", " min")
				from: 0
				to: 120
			}
		}

		//--- Event starting
		FormCard.FormHeader {
			title: i18n("When an Event Starts")
		}
		FormCard.FormCard {
			FormConfigSwitch {
				id: startingEnabled
				text: i18n("Show a notification")
				configKey: 'eventStartingNotificationEnabled'
			}
			FormCard.FormDelegateSeparator {}
			FormConfigSwitch {
				enabled: startingEnabled.checked
				text: i18n("Keep until dismissed")
				configKey: 'eventStartingPersistent'
			}
			FormCard.FormDelegateSeparator {}
			FormConfigSwitch {
				enabled: startingEnabled.checked
				text: i18n("Critical")
				description: i18n("Shown even in Do Not Disturb")
				configKey: 'eventStartingCritical'
			}
		}

		//--- Sounds
		FormCard.FormHeader {
			title: i18n("Sounds")
		}
		FormCard.FormCard {
			SoundRow {
				enabled: reminderEnabled.checked
				label: i18n("Reminder")
				sfxEnabledKey: 'eventReminderSfxEnabled'
				sfxPathKey: 'eventReminderSfxPath'
			}
			FormCard.FormDelegateSeparator {}
			SoundRow {
				enabled: startingEnabled.checked
				label: i18n("Event starts")
				sfxEnabledKey: 'eventStartingSfxEnabled'
				sfxPathKey: 'eventStartingSfxPath'
			}
		}

		//--- Google Meet: which app opens Meet links (Join buttons)
		FormCard.FormHeader {
			title: i18n("Google Meet")
		}
		FormCard.FormCard {
			FormCard.FormComboBoxDelegate {
				id: meetAppCombo
				text: i18n("Open meeting links in")
				textRole: "text"
				// Default browser, the Meet web apps found (scripts/find_meet_apps.py), a command.
				model: [{ text: i18n("Default browser"), command: "" }]
					.concat(page.meetApps.map(function(app) { return { text: app.name, command: app.command, authuser: app.authuser } }))
					.concat([{ text: i18n("Other command…"), custom: true }])
				function syncIndex() {
					var command = String(page.configBridge.read("meetLinkCommand", "") || "")
					if (!command) {
						currentIndex = 0
						return
					}
					for (var i = 1; i < model.length - 1; i++) {
						if (model[i].command === command) {
							currentIndex = i
							return
						}
					}
					currentIndex = model.length - 1
				}
				onModelChanged: syncIndex()
				Component.onCompleted: syncIndex()
				onActivated: function(index) {
					var entry = model[index]
					if (entry.custom) {
						meetCommandField.forceActiveFocus()
						return
					}
					page.configBridge.write("meetLinkCommand", entry.command)
					meetCommandField.text = entry.command
					if (entry.authuser) {
						page.configBridge.write("meetLinkAuthUser", entry.authuser)
						meetAuthUserField.text = entry.authuser
					}
				}
			}
			FormCard.FormDelegateSeparator {}
			FormConfigText {
				id: meetCommandField
				visible: meetAppCombo.currentIndex === meetAppCombo.count - 1
				label: i18n("Command")
				configKey: 'meetLinkCommand'
				placeholderText: "vivaldi-stable --app=%u"
			}
			FormCard.FormDelegateSeparator { visible: meetCommandField.visible }
			FormConfigText {
				id: meetAuthUserField
				label: i18n("Google account")
				configKey: 'meetLinkAuthUser'
				placeholderText: i18n("Default")
			}
		}
		FormCard.FormSectionText {
			text: i18n("Join buttons open Google Meet links there; other meeting links open in the default browser. In a command, %u stands for the meeting link. Google account: its number (0, 1, …) or email, as in Google's account switcher; empty uses the app's default.")
		}

		//--- Both
		FormCard.FormHeader {
			title: i18n("All Event Notifications")
		}
		FormCard.FormCard {
			FormConfigSwitch {
				text: i18n("\"Join meeting\" and \"Open in Calendar\" buttons")
				configKey: 'eventNotificationActions'
			}
			FormCard.FormDelegateSeparator {}
			FormConfigSwitch {
				text: i18n("Skip all-day events")
				configKey: 'eventNotifySkipAllDay'
			}
			FormCard.FormDelegateSeparator {}
			FormConfigSwitch {
				text: i18n("Skip events I declined")
				configKey: 'eventNotifySkipDeclined'
			}
		}
		FormCard.FormSectionText {
			text: i18n("Popups and sounds for each kind of notification can also be set in System Settings > Notifications > Event Calendar.")
		}
	}
}
