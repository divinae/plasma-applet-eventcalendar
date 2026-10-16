import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kirigamiaddons.formcard as FormCard

import ".."
import "../lib"

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
					{ value: 'today', text: i18n("Today") },
					{ value: 'classic', text: i18n("Agenda") },
				]
			}
			FormCard.FormDelegateSeparator {}
			FormConfigSwitch {
				text: i18n("View switcher in the header")
				configKey: 'showViewTabs'
			}
			FormCard.FormDelegateSeparator {}
			FormConfigSpin {
				label: i18n("Popup width")
				configKey: 'monthModeWidth'
				suffix: i18n(" px")
				from: 300
				to: 3000
			}
			FormCard.FormDelegateSeparator {}
			FormConfigSpin {
				label: i18n("Popup height")
				configKey: 'monthModeHeight'
				suffix: i18n(" px")
				from: 250
				to: 3000
			}
		}

		//--- Week and Today
		FormCard.FormHeader {
			title: i18n("Week and Today")
		}
		FormCard.FormCard {
			FormConfigSpin {
				label: i18n("First hour shown")
				configKey: 'weekViewStartHour'
				suffix: ":00"
				from: 0
				to: 23
			}
			FormCard.FormDelegateSeparator {}
			FormConfigSpin {
				label: i18n("Last hour shown")
				configKey: 'weekViewEndHour'
				suffix: ":00"
				from: 1
				to: 24
			}
			FormCard.FormDelegateSeparator {}
			FormConfigSwitch {
				text: i18n("Weather")
				description: i18n("Forecast in the day headers and, in the Today view, a weather panel.")
				configKey: 'weatherShowInViews'
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
			FormConfigCombo {
				text: i18n("Google event colors")
				description: i18n("Google's API still returns an older palette; the current colors match Google Calendar.")
				configKey: 'googleColorPalette'
				model: [
					{ value: 'current', text: i18n("As in Google Calendar") },
					{ value: 'classic', text: i18n("Classic (as returned by Google)") },
				]
			}
			FormCard.FormDelegateSeparator {}
			FormConfigSwitch {
				text: i18n("Week numbers")
				configKey: 'monthShowWeekNumbers'
			}
			FormCard.FormDelegateSeparator {}
			FormConfigSwitch {
				text: i18n("Clicking a day shows its events")
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
						sfxPathDefaultValue: '/usr/share/sounds/freedesktop/stereo/complete.oga'
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
	}
}
