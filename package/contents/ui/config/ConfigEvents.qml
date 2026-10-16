import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

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

	Kirigami.FormLayout {
		Layout.fillWidth: true

		//--- Sources
		Kirigami.Separator {
			Kirigami.FormData.isSection: true
			Kirigami.FormData.label: i18n("Calendars")
		}
		ConfigSpinBox {
			Kirigami.FormData.label: i18n("Refresh every:")
			configKey: 'eventsPollInterval'
			suffix: i18nc("Polling interval in minutes", " min")
			minimumValue: 5
			maximumValue: 90
		}
		Label {
			visible: !page.eventPluginsManager
			text: i18n("Plasma calendar plugins are unavailable.")
			opacity: 0.7
		}
		// A Repeater directly in a FormLayout breaks the layout's child handling.
		ColumnLayout {
			visible: !!page.eventPluginsManager
			Kirigami.FormData.label: i18n("Plasma calendars:")
			spacing: 0
			Repeater {
				model: page.eventPluginsManager ? page.eventPluginsManager.model : null
				delegate: CheckBox {
					text: model.display
					checked: model.checked
					onClicked: {
						model.checked = checked // needed for model's setData to be called
						page.saveConfig()
					}
				}
			}
		}

		//--- Clicking
		Kirigami.Separator {
			Kirigami.FormData.isSection: true
			Kirigami.FormData.label: i18n("Clicking an Event")
		}
		ConfigComboBox {
			Kirigami.FormData.label: i18n("Opens:")
			configKey: 'eventClickAction'
			model: [
				{ value: 'details', text: i18n("Event details in the widget") },
				{ value: 'browser', text: i18n("Google Calendar in the browser") },
			]
		}

		//--- Reminder
		Kirigami.Separator {
			Kirigami.FormData.isSection: true
			Kirigami.FormData.label: i18n("Reminder Before an Event")
		}
		ConfigCheckBox {
			id: reminderEnabled
			configKey: 'eventReminderNotificationEnabled'
			text: i18n("Show a reminder")
		}
		ConfigSpinBox {
			enabled: reminderEnabled.checked
			Kirigami.FormData.label: i18n("Time before:")
			configKey: 'eventReminderMinutesBefore'
			suffix: i18nc("Time in minutes", " min")
			minimumValue: 1
		}
		ConfigCheckBox {
			enabled: reminderEnabled.checked
			configKey: 'eventReminderUseGoogle'
			text: i18n("Use the reminder times set in Google Calendar")
		}
		ConfigSound {
			enabled: reminderEnabled.checked
			Kirigami.FormData.label: i18n("Sound:")
			label: ""
			Layout.fillWidth: true
			sfxEnabledKey: 'eventReminderSfxEnabled'
			sfxPathKey: 'eventReminderSfxPath'
			sfxPathDefaultValue: '/usr/share/sounds/Oxygen-Im-Nudge.ogg'
		}
		// eventReminderTimeout: 0 = keep until dismissed; anything else = Plasma's popup timeout
		// (System Settings > Notifications). KDE notifications have no per-notification timeout.
		CheckBox {
			enabled: reminderEnabled.checked
			Kirigami.FormData.label: i18n("Popup:")
			text: i18n("Keep until dismissed")
			checked: page.configBridge.read("eventReminderTimeout", 12) === 0
			onToggled: page.configBridge.write("eventReminderTimeout", checked ? 0 : 12)
		}
		ConfigSpinBox {
			enabled: reminderEnabled.checked
			Kirigami.FormData.label: i18n("Snooze:")
			configKey: 'eventReminderSnoozeMinutes'
			suffix: i18nc("Time in minutes", " min")
			after: i18n("(0 = no Snooze button)")
			minimumValue: 0
			maximumValue: 120
		}

		//--- Event starting
		Kirigami.Separator {
			Kirigami.FormData.isSection: true
			Kirigami.FormData.label: i18n("When an Event Starts")
		}
		ConfigCheckBox {
			id: startingEnabled
			configKey: 'eventStartingNotificationEnabled'
			text: i18n("Show a notification")
		}
		ConfigSound {
			enabled: startingEnabled.checked
			Kirigami.FormData.label: i18n("Sound:")
			label: ""
			Layout.fillWidth: true
			sfxEnabledKey: 'eventStartingSfxEnabled'
			sfxPathKey: 'eventStartingSfxPath'
			sfxPathDefaultValue: '/usr/share/sounds/Oxygen-Im-Nudge.ogg'
		}
		ConfigCheckBox {
			enabled: startingEnabled.checked
			configKey: 'eventStartingPersistent'
			text: i18n("Keep until dismissed")
		}
		ConfigCheckBox {
			enabled: startingEnabled.checked
			configKey: 'eventStartingCritical'
			text: i18n("Critical (shown even in Do Not Disturb)")
		}

		//--- Both
		Kirigami.Separator {
			Kirigami.FormData.isSection: true
			Kirigami.FormData.label: i18n("All Event Notifications")
		}
		ConfigCheckBox {
			configKey: 'eventNotificationActions'
			text: i18n("\"Join meeting\" and \"Open in Calendar\" buttons")
		}
		ConfigCheckBox {
			Kirigami.FormData.label: i18n("Skip:")
			configKey: 'eventNotifySkipAllDay'
			text: i18n("All-day events")
		}
		ConfigCheckBox {
			configKey: 'eventNotifySkipDeclined'
			text: i18n("Events I declined")
		}
	}
}
