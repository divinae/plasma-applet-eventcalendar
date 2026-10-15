import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import "../lib"
import "../calendars/PlasmaCalendarUtils.js" as PlasmaCalendarUtils

ConfigPage {
	id: page
	property var eventPluginsManager: null

	HeaderText {
		text: i18n("Event Calendar Plugins")
	}

	ConfigSection {
		CheckBox {
			text: i18n("ICalendar (.ics)")
			checked: true
			enabled: false
			visible: page.configBridge.read("debugging", false)
		}
		CheckBox {
			text: i18n("Google Calendar")
			checked: true
			enabled: false
		}
	}


	HeaderText {
		text: i18n("Plasma Calendar Plugins")
	}

	// From digitalclock's configCalendar.qml
	signal configurationChanged()
	MessageWidget {
		visible: !eventPluginsManager
		messageType: MessageWidget.MessageType.Warning
		closeButtonVisible: false
		text: i18n("Plasma calendar plugins are unavailable. Install the Plasma calendar module to manage these plugins.")
	}
	ConfigSection {
		Repeater {
			id: calendarPluginsRepeater
			model: eventPluginsManager ? eventPluginsManager.model : null
			delegate: CheckBox {
				text: model.display
				checked: model.checked
				onClicked: {
					model.checked = checked // needed for model's setData to be called
					// page.configurationChanged()
					page.saveConfig()
				}
			}
		}
	}
	function saveConfig() {
		if (!eventPluginsManager) {
			return
		}
		page.configBridge.write("enabledCalendarPlugins", PlasmaCalendarUtils.pluginPathToFilenameList(eventPluginsManager.enabledPlugins))
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
		PlasmaCalendarUtils.populateEnabledPluginsByFilename(eventPluginsManager, page.configBridge.read("enabledCalendarPlugins", []))
	}

	HeaderText {
		text: i18n("Misc")
	}
	ColumnLayout {

		ConfigSpinBox {
			configKey: 'eventsPollInterval'
			before: i18n("Refresh events every: ")
			suffix: i18nc("Polling interval in minutes", "min")
			minimumValue: 5
			maximumValue: 90
		}
	}

	HeaderText {
		text: i18n("Notifications")
	}

	ConfigSection {
		ConfigNotification {
			id: eventReminderNotification
			label: i18n("Event Reminder")
			notificationEnabledKey: 'eventReminderNotificationEnabled'
			sfxEnabledKey: 'eventReminderSfxEnabled'
			sfxPathKey: 'eventReminderSfxPath'
			sfxPathDefaultValue: '/usr/share/sounds/Oxygen-Im-Nudge.ogg'

			RowLayout {
				spacing: 0
				Item { implicitWidth: parent.parent.indentWidth } // indent
				ConfigSpinBox {
					configKey: 'eventReminderMinutesBefore'
					suffix: i18nc("Polling interval in minutes", "min")
					minimumValue: 1
				}
			}
			RowLayout {
				spacing: 0
				enabled: eventReminderNotification.notificationEnabled
				Item { implicitWidth: eventReminderNotification.indentWidth } // indent
				ConfigSpinBox {
					configKey: 'eventReminderTimeout'
					before: i18n("Hide after:")
					suffix: i18nc("Time in seconds", "s")
					after: i18n("(0 = keep until dismissed)")
					minimumValue: 0
					maximumValue: 600
				}
			}
			RowLayout {
				spacing: 0
				enabled: eventReminderNotification.notificationEnabled
				Item { implicitWidth: eventReminderNotification.indentWidth } // indent
				ConfigSpinBox {
					configKey: 'eventReminderSnoozeMinutes'
					before: i18n("Snooze:")
					suffix: i18nc("Time in minutes", "min")
					after: i18n("(0 = no Snooze button)")
					minimumValue: 0
					maximumValue: 120
				}
			}
		}
	}

	ConfigSection {
		ConfigNotification {
			id: eventStartingNotification
			label: i18n("Event Starting")
			notificationEnabledKey: 'eventStartingNotificationEnabled'
			sfxEnabledKey: 'eventStartingSfxEnabled'
			sfxPathKey: 'eventStartingSfxPath'
			sfxPathDefaultValue: '/usr/share/sounds/Oxygen-Im-Nudge.ogg'

			RowLayout {
				spacing: 0
				enabled: eventStartingNotification.notificationEnabled
				Item { implicitWidth: eventStartingNotification.indentWidth } // indent
				ConfigCheckBox {
					configKey: 'eventStartingPersistent'
					text: i18n("Keep until dismissed")
				}
			}
			RowLayout {
				spacing: 0
				enabled: eventStartingNotification.notificationEnabled
				Item { implicitWidth: eventStartingNotification.indentWidth } // indent
				ConfigCheckBox {
					configKey: 'eventStartingCritical'
					text: i18n("Critical (shown even in Do Not Disturb)")
				}
			}
		}
	}

	ConfigSection {
		ConfigCheckBox {
			configKey: 'eventNotificationActions'
			text: i18n("Show \"Join meeting\" and \"Open in Calendar\" buttons")
		}
		ConfigCheckBox {
			configKey: 'eventNotifySkipAllDay'
			text: i18n("Don't notify for all-day events")
		}
		ConfigCheckBox {
			configKey: 'eventNotifySkipDeclined'
			text: i18n("Don't notify for events I declined")
		}
	}

}
