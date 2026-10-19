import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kirigamiaddons.formcard as FormCard

import ".."
import "../lib"
import "../TimeZone.js" as TimeZone

ConfigPage {
	id: page

	property int timezoneColumnWidth: Kirigami.Units.gridUnit * 12

	ListModel { id: timezoneListModel }

	function normalizedTimezones(list) {
		var zones = []
		if (Array.isArray(list)) {
			zones = list.slice(0)
		} else if (typeof list === "string") {
			zones = list.split(',')
		}
		var normalized = []
		for (var i = 0; i < zones.length; i++) {
			var zone = (zones[i] || "").trim()
			if (!zone) {
				continue
			}
			if (normalized.indexOf(zone) === -1) {
				normalized.push(zone)
			}
		}
		if (normalized.indexOf("Local") === -1) {
			normalized.unshift("Local")
		} else {
			normalized.splice(normalized.indexOf("Local"), 1)
			normalized.unshift("Local")
		}
		return normalized
	}

	function syncFromConfig() {
		var zones = normalizedTimezones(page.configBridge.read("selectedTimeZones", []))
		timezoneListModel.clear()
		for (var i = 0; i < zones.length; i++) {
			timezoneListModel.append({ zoneId: zones[i] })
		}
	}

	function updateConfig(zones) {
		page.configBridge.write("selectedTimeZones", normalizedTimezones(zones))
	}

	function addTimezone(zoneId) {
		var zone = (zoneId || "").trim()
		if (!zone) {
			return
		}
		var zones = normalizedTimezones(page.configBridge.read("selectedTimeZones", []))
		if (zones.indexOf(zone) === -1) {
			zones.push(zone)
			updateConfig(zones)
			syncFromConfig()
		}
		timezoneInput.text = ""
	}

	function removeTimezone(zoneId) {
		var zones = normalizedTimezones(page.configBridge.read("selectedTimeZones", []))
		var index = zones.indexOf(zoneId)
		if (index >= 0 && zoneId !== "Local") {
			zones.splice(index, 1)
			updateConfig(zones)
			syncFromConfig()
		}
	}

	function prettyZoneName(zoneId) {
		if (zoneId === "Local") {
			return i18n("Local")
		}
		return TimeZone.cityName(zoneId)
	}

	Component.onCompleted: syncFromConfig()
	Connections {
		target: page
		function onCfg_selectedTimeZonesChanged() {
			syncFromConfig()
		}
	}

	ColumnLayout {
		Layout.fillWidth: true
		spacing: 0

		FormCard.FormHeader {
			title: i18n("Extra Time Zones in the Tooltip")
		}
		FormCard.FormCard {
			// A plain list (not a ListView) so it sizes to its rows inside the scrolling page.
			Repeater {
				model: timezoneListModel
				ColumnLayout {
					Layout.fillWidth: true
					spacing: 0
					FormCard.FormDelegateSeparator {
						visible: index > 0
					}
					FormCard.AbstractFormDelegate {
						Layout.fillWidth: true
						background: null
						contentItem: RowLayout {
							spacing: Kirigami.Units.smallSpacing
							ColumnLayout {
								Layout.fillWidth: true
								spacing: 0
								Label {
									Layout.fillWidth: true
									text: prettyZoneName(model.zoneId)
									elide: Text.ElideRight
								}
								Label {
									Layout.fillWidth: true
									visible: model.zoneId !== "Local"
									text: model.zoneId
									elide: Text.ElideRight
									color: Kirigami.Theme.disabledTextColor
									font: Kirigami.Theme.smallFont
								}
							}
							ToolButton {
								icon.name: "edit-delete"
								display: AbstractButton.IconOnly
								text: i18n("Remove time zone")
								visible: model.zoneId !== "Local"
								onClicked: removeTimezone(model.zoneId)
								ToolTip.text: text
								ToolTip.visible: hovered
								ToolTip.delay: Kirigami.Units.toolTipDelay
							}
						}
					}
				}
			}
			FormCard.FormDelegateSeparator {}
			// Search the known zones; Enter, Add or a click adds the highlighted one.
			FormCard.AbstractFormDelegate {
				Layout.fillWidth: true
				background: null
				contentItem: ColumnLayout {
					spacing: Kirigami.Units.smallSpacing
					RowLayout {
						spacing: Kirigami.Units.smallSpacing
						TextField {
							id: timezoneInput
							Layout.fillWidth: true
							placeholderText: i18n("Add a time zone, eg: America/New_York")
							Keys.onUpPressed: zoneList.moveUp()
							Keys.onDownPressed: zoneList.moveDown()
							onAccepted: zoneList.pickCurrent()
						}
						Button {
							icon.name: "list-add"
							text: i18n("Add")
							enabled: timezoneInput.text.trim().length > 0 && zoneList.count > 0
							onClicked: zoneList.pickCurrent()
						}
					}
					TimeZoneList {
						id: zoneList
						visible: timezoneInput.text.trim() !== ""
						Layout.fillWidth: true
						Layout.preferredHeight: Kirigami.Units.gridUnit * 8
						query: timezoneInput.text
						onPicked: function(zone) { addTimezone(zone) }
					}
				}
			}
		}
		FormCard.FormSectionText {
			text: i18n("Zones with the same time as yours are not shown.")
		}

		FormCard.FormHeader {
			title: i18n("Display")
		}
		FormCard.FormCard {
			FormCard.FormComboBoxDelegate {
				text: i18n("Show time zones as")
				model: [i18n("City name"), i18n("Abbreviation (eg: CEST)")]
				currentIndex: page.configBridge.read("displayTimezoneAsCode", true) ? 1 : 0
				onActivated: function(index) { page.configBridge.write("displayTimezoneAsCode", index === 1) }
			}
		}
	}
}
