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
					{ value: 'today', text: i18nc("calendar view showing one day", "Day") },
					{ value: 'classic', text: i18n("Agenda") },
					// Shown when task lists are selected (Tasks settings), else the month.
					{ value: 'tasks', text: i18n("Tasks") },
				]
			}
			FormCard.FormDelegateSeparator {}
			FormConfigSwitch {
				id: showViewTabsSwitch
				text: i18n("View switcher in the header")
				configKey: 'showViewTabs'
			}
			// The views the switcher offers (at least one calendar view stays: Tasks is only offered
			// with task lists selected).
			Repeater {
				model: [
					{ mode: 'month', text: i18n("Month") },
					{ mode: 'week', text: i18n("Week") },
					{ mode: 'today', text: i18nc("calendar view showing one day", "Day") },
					{ mode: 'classic', text: i18n("Agenda") },
					{ mode: 'tasks', text: i18n("Tasks") },
				]
				FormCard.FormCheckDelegate {
					readonly property var hidden: page.configBridge.read("hiddenViewTabs", []) || []
					readonly property int calendarViewsShown: ['month', 'week', 'today', 'classic'].filter(function(mode) {
						return hidden.indexOf(mode) < 0
					}).length
					enabled: showViewTabsSwitch.checked && (!checked || modelData.mode === 'tasks' || calendarViewsShown > 1)
					leftPadding: Kirigami.Units.gridUnit * 2
					text: modelData.text
					checked: hidden.indexOf(modelData.mode) < 0
					onToggled: {
						var list = Array.prototype.slice.call(page.configBridge.read("hiddenViewTabs", []) || []).filter(function(mode) {
							return mode !== modelData.mode
						})
						if (!checked) {
							list.push(modelData.mode)
						}
						page.configBridge.write("hiddenViewTabs", list)
					}
				}
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
			FormConfigSpin {
				label: i18n("Working hours start")
				configKey: 'weekViewStartHour'
				suffix: ":00"
				from: 0
				to: 23
			}
			FormCard.FormDelegateSeparator {}
			FormConfigSpin {
				label: i18n("Working hours end")
				configKey: 'weekViewEndHour'
				suffix: ":00"
				from: 1
				to: 24
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
			FormConfigCombo {
				text: i18n("Event look")
				configKey: 'eventLook'
				model: [
					{ value: 'bar', text: i18n("All-day filled, timed light with a color bar") },
					{ value: 'solid', text: i18n("Filled in the event color") },
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
				text: i18n("Declined events")
				configKey: 'showDeclinedEvents'
				model: [
					{ value: true, text: i18n("Show (struck through)") },
					{ value: false, text: i18nc("declined events", "Hide") },
				]
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
	}
}
