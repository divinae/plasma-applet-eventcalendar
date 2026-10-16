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
			// eventReminderTimeout: 0 = keep until dismissed; anything else = Plasma's popup timeout
			// (System Settings > Notifications). KDE notifications have no per-notification timeout.
			FormCard.FormSwitchDelegate {
				enabled: reminderEnabled.checked
				text: i18n("Keep until dismissed")
				checked: page.configBridge.read("eventReminderTimeout", 12) === 0
				onToggled: page.configBridge.write("eventReminderTimeout", checked ? 0 : 12)
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
