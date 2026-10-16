import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import ".."
import "../lib"

// Popup views: month / week / agenda, calendar look and, for the agenda layout, its widgets.
ConfigPage {
	id: page

	readonly property bool agendaMode: page.configBridge.read("popupMode", "classic") === 'classic'

	Kirigami.FormLayout {
		Layout.fillWidth: true

		//--- Popup
		Kirigami.Separator {
			Kirigami.FormData.isSection: true
			Kirigami.FormData.label: i18n("Popup")
		}
		ConfigComboBox {
			Kirigami.FormData.label: i18n("Default view:")
			configKey: 'popupMode'
			model: [
				{ value: 'month', text: i18n("Month") },
				{ value: 'week', text: i18n("Week") },
				{ value: 'today', text: i18n("Today") },
				{ value: 'classic', text: i18n("Agenda") },
			]
		}
		ConfigCheckBox {
			configKey: 'showViewTabs'
			text: i18n("Show view switcher in the header")
		}
		RowLayout {
			Kirigami.FormData.label: i18n("Popup size:")
			ConfigSpinBox {
				configKey: 'monthModeWidth'
				suffix: i18n(" px")
				minimumValue: 300
				maximumValue: 3000
			}
			Label { text: "×" }
			ConfigSpinBox {
				configKey: 'monthModeHeight'
				suffix: i18n(" px")
				minimumValue: 250
				maximumValue: 3000
			}
		}
		RowLayout {
			Kirigami.FormData.label: i18n("Hours shown (today and week):")
			ConfigSpinBox {
				configKey: 'weekViewStartHour'
				suffix: ":00"
				minimumValue: 0
				maximumValue: 23
			}
			Label { text: "–" }
			ConfigSpinBox {
				configKey: 'weekViewEndHour'
				suffix: ":00"
				minimumValue: 1
				maximumValue: 24
			}
		}
		ComboBox {
			id: firstDayOfWeekComboBox
			Kirigami.FormData.label: i18n("First day of week:")
			// -1 = locale default, 0..6 = Sunday..Saturday
			model: {
				var list = [{ text: i18n("Default"), value: -1 }]
				for (var i = 0; i < 7; i++) {
					list.push({ text: Qt.locale().dayName(i), value: i })
				}
				return list
			}
			textRole: "text"
			currentIndex: page.configBridge.read("firstDayOfWeek", -1) + 1
			onActivated: page.configBridge.write("firstDayOfWeek", currentIndex - 1)
		}

		//--- Calendar look
		Kirigami.Separator {
			Kirigami.FormData.isSection: true
			Kirigami.FormData.label: i18n("Calendar")
		}
		ConfigCheckBox {
			Kirigami.FormData.label: i18n("Show:")
			configKey: 'monthShowWeekNumbers'
			text: i18n("Week numbers")
		}
		ConfigCheckBox {
			configKey: 'weatherShowInViews'
			text: i18n("Weather in the week and today views")
		}
		ConfigCheckBox {
			Kirigami.FormData.label: i18n("Clicking a day:")
			configKey: 'monthClickOpensDay'
			text: i18n("Show the day's events (month view)")
		}
		ConfigComboBox {
			Kirigami.FormData.label: i18n("Double-clicking a day:")
			configKey: 'monthDayDoubleClick'
			model: [
				{ value: 'GoogleCalWeb', text: i18n("New event in Google Calendar (browser)") },
				{ value: 'DoNothing', text: i18n("Do nothing") },
			]
		}

		//--- Agenda layout (classic mode only)
		Kirigami.Separator {
			visible: page.agendaMode
			Kirigami.FormData.isSection: true
			Kirigami.FormData.label: i18n("Agenda View")
		}
		ConfigCheckBox {
			visible: page.agendaMode
			Kirigami.FormData.label: i18n("Above the agenda:")
			configKey: 'widgetShowMeteogram'
			text: i18n("Meteogram")
		}
		ConfigCheckBox {
			id: widgetShowTimer
			visible: page.agendaMode
			configKey: 'widgetShowTimer'
			text: i18n("Timer")
		}
		ConfigSound {
			visible: page.agendaMode
			enabled: widgetShowTimer.checked
			Kirigami.FormData.label: i18n("Timer sound:")
			label: ""
			Layout.fillWidth: true
			sfxEnabledKey: 'timerSfxEnabled'
			sfxPathKey: 'timerSfxFilepath'
			sfxPathDefaultValue: '/usr/share/sounds/freedesktop/stereo/complete.oga'
		}
		ConfigSpinBox {
			visible: page.agendaMode
			Kirigami.FormData.label: i18n("Meteogram / timer height:")
			configKey: 'topRowHeight'
			suffix: i18n(" px")
			minimumValue: 50
			maximumValue: 3000
		}

		//--- Agenda list
		Kirigami.Separator {
			visible: page.agendaMode
			Kirigami.FormData.isSection: true
			Kirigami.FormData.label: i18n("Agenda List")
		}
		ConfigCheckBox {
			visible: page.agendaMode
			Kirigami.FormData.label: i18n("Events:")
			configKey: 'agendaShowEventDescription'
			text: i18n("Show descriptions")
		}
		ConfigCheckBox {
			visible: page.agendaMode
			configKey: 'agendaShowEventHangoutLink'
			text: i18n("Show meeting link button")
		}
		ConfigCheckBox {
			visible: page.agendaMode
			configKey: 'agendaBreakupMultiDayEvents'
			text: i18n("Show multi-day events on every day")
		}
	}
}
