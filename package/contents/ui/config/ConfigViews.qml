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

	AppletConfig { id: config }

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
				{ value: 'today', text: i18n("Today") },
				{ value: 'week', text: i18n("Week") },
				{ value: 'month', text: i18n("Month") },
				{ value: 'classic', text: i18n("Agenda") },
			]
		}
		ConfigCheckBox {
			configKey: 'showViewTabs'
			text: i18n("Show view switcher in the header")
		}
		RowLayout {
			Kirigami.FormData.label: i18n("Today, week and month size:")
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
			configKey: 'monthShowBorder'
			text: i18n("Grid lines")
		}
		ConfigCheckBox {
			configKey: 'monthShowWeekNumbers'
			text: i18n("Week numbers")
		}
		ConfigCheckBox {
			configKey: 'monthHighlightCurrentDayWeek'
			text: i18n("Highlight the current day of the week")
		}
		ConfigCheckBox {
			configKey: 'showOutlines'
			text: i18n("Outlines around icons and dots")
		}
		ConfigComboBox {
			Kirigami.FormData.label: i18n("Today:")
			configKey: 'monthTodayStyle'
			model: [
				{ value: 'theme', text: i18n("Framed") },
				{ value: 'bigNumber', text: i18n("Big number") },
			]
		}
		ConfigSlider {
			Kirigami.FormData.label: i18n("Day corner radius:")
			configKey: 'monthCellRadius'
			minimumValue: 0
			maximumValue: 1
			Layout.preferredWidth: Kirigami.Units.gridUnit * 10
		}
		ConfigString {
			Kirigami.FormData.label: i18n("Current month title:")
			configKey: 'monthCurrentCustomTitleFormat'
			placeholderText: i18nc("calendar title format for current month", "MMMM d, yyyy")
			Layout.preferredWidth: Kirigami.Units.gridUnit * 10
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
			Kirigami.FormData.label: i18n("Show:")
			configKey: 'widgetShowCalendar'
			text: i18n("Calendar")
		}
		ConfigCheckBox {
			visible: page.agendaMode
			configKey: 'widgetShowAgenda'
			text: i18n("Agenda")
		}
		ConfigCheckBox {
			visible: page.agendaMode
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
		ConfigCheckBox {
			visible: page.agendaMode
			Kirigami.FormData.label: i18n("Layout:")
			configKey: 'twoColumns'
			text: i18n("Calendar next to the agenda (two columns)")
		}
		RowLayout {
			visible: page.agendaMode
			Kirigami.FormData.label: i18n("Column widths (left | right):")
			ConfigSpinBox {
				configKey: 'leftColumnWidth'
				suffix: i18n(" px")
				minimumValue: 100
				maximumValue: 3000
			}
			Label { text: "|" ; opacity: 0.5 }
			ConfigSpinBox {
				configKey: 'rightColumnWidth'
				suffix: i18n(" px")
				minimumValue: 100
				maximumValue: 3000
			}
		}
		RowLayout {
			visible: page.agendaMode
			Kirigami.FormData.label: i18n("Row heights (top / bottom):")
			ConfigSpinBox {
				configKey: 'topRowHeight'
				suffix: i18n(" px")
				minimumValue: 50
				maximumValue: 3000
			}
			Label { text: "/" ; opacity: 0.5 }
			ConfigSpinBox {
				configKey: 'bottomRowHeight'
				suffix: i18n(" px")
				minimumValue: 100
				maximumValue: 3000
			}
		}
		ConfigSpinBox {
			visible: page.agendaMode
			Kirigami.FormData.label: i18n("Calendar height (one column):")
			configKey: 'monthHeightSingleColumn'
			suffix: i18n(" px")
			minimumValue: 100
			maximumValue: 3000
		}
		ConfigComboBox {
			visible: page.agendaMode
			Kirigami.FormData.label: i18n("Event markers:")
			configKey: 'monthEventBadgeType'
			model: [
				{ value: 'theme', text: i18n("Theme") },
				{ value: 'dots', text: i18n("Dots") },
				{ value: 'bottomBar', text: i18n("Bar in event colors") },
				{ value: 'bottomBarHighlight', text: i18n("Bar in highlight color") },
				{ value: 'count', text: i18n("Count") },
				{ value: 'eventTitles', text: i18n("Event titles") },
			]
		}

		//--- Agenda list
		Kirigami.Separator {
			visible: page.agendaMode
			Kirigami.FormData.isSection: true
			Kirigami.FormData.label: i18n("Agenda List")
		}
		ConfigSpinBox {
			visible: page.agendaMode
			Kirigami.FormData.label: i18n("Font size:")
			configKey: 'agendaFontSize'
			suffix: i18n(" px")
			after: i18n("(0 = system font)")
		}
		RowLayout {
			visible: page.agendaMode
			Kirigami.FormData.label: i18n("Spacing:")
			ConfigSpinBox {
				configKey: 'agendaDaySpacing'
				suffix: i18n(" px")
				after: i18n("between days,")
			}
			ConfigSpinBox {
				configKey: 'agendaEventSpacing'
				suffix: i18n(" px")
				after: i18n("between events")
			}
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
			configKey: 'agendaCondensedAllDayEvent'
			text: i18n("Hide \"All day\" text")
		}
		ConfigCheckBox {
			visible: page.agendaMode
			configKey: 'agendaBreakupMultiDayEvents'
			text: i18n("Show multi-day events on every day")
		}
		ConfigCheckBox {
			visible: page.agendaMode
			configKey: 'agendaNewEventRememberCalendar'
			text: i18n("Remember the calendar of the last new event")
		}
		ConfigColor {
			visible: page.agendaMode
			Kirigami.FormData.label: i18n("In-progress color:")
			label: ""
			configKey: 'agendaInProgressColor'
			defaultColor: config.agendaInProgressColorDefault
		}
		RowLayout {
			visible: page.agendaMode
			Kirigami.FormData.label: i18n("Weather:")
			ConfigCheckBox {
				id: agendaWeatherShowIcon
				configKey: 'agendaWeatherShowIcon'
				text: i18n("Icon")
			}
			ConfigSlider {
				enabled: agendaWeatherShowIcon.checked
				configKey: 'agendaWeatherIconHeight'
				minimumValue: 12
				maximumValue: 48
				stepSize: 1
				after: '' + value + i18n(" px")
				Layout.preferredWidth: Kirigami.Units.gridUnit * 8
			}
		}
		ConfigCheckBox {
			visible: page.agendaMode
			configKey: 'agendaWeatherShowText'
			text: i18n("Text")
		}
		ConfigCheckBox {
			visible: page.agendaMode
			configKey: 'agendaWeatherOnRight'
			text: i18n("On the right side")
		}
	}
}
