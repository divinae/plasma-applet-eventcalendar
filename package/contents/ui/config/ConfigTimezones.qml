import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import ".."
import "../lib"

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
		var parts = zoneId.split('/')
		return parts[parts.length - 1].replace(/_/g, ' ')
	}

	Component.onCompleted: syncFromConfig()
	Connections {
		target: page
		function onCfg_selectedTimeZonesChanged() {
			syncFromConfig()
		}
	}

	Kirigami.FormLayout {
		Layout.fillWidth: true

		Kirigami.Separator {
			Kirigami.FormData.isSection: true
			Kirigami.FormData.label: i18n("Extra Time Zones in the Tooltip")
		}
		RowLayout {
			Kirigami.FormData.label: i18n("Add:")
			TextField {
				id: timezoneInput
				Layout.preferredWidth: Kirigami.Units.gridUnit * 14
				placeholderText: i18n("eg: America/New_York")
				onAccepted: addTimezone(text)
			}
			Button {
				icon.name: "list-add"
				text: i18n("Add")
				enabled: timezoneInput.text.trim().length > 0
				onClicked: addTimezone(timezoneInput.text)
			}
		}
		// A plain list (not a ListView) so it sizes to its rows inside the scrolling page.
		ColumnLayout {
			Kirigami.FormData.label: i18n("Shown:")
			spacing: 0
			Repeater {
				model: timezoneListModel
				RowLayout {
					spacing: Kirigami.Units.smallSpacing
					Label {
						text: prettyZoneName(model.zoneId)
						Layout.preferredWidth: page.timezoneColumnWidth
						elide: Text.ElideRight
					}
					Label {
						text: model.zoneId
						Layout.preferredWidth: page.timezoneColumnWidth
						elide: Text.ElideRight
						opacity: 0.6
					}
					ToolButton {
						icon.name: "edit-delete"
						enabled: model.zoneId !== "Local"
						onClicked: removeTimezone(model.zoneId)
						Accessible.name: i18n("Remove time zone")
					}
				}
			}
		}
		Label {
			Layout.maximumWidth: Kirigami.Units.gridUnit * 20
			wrapMode: Text.Wrap
			opacity: 0.7
			text: i18n("Zones with the same time as yours are not shown.")
		}
		ComboBox {
			Kirigami.FormData.label: i18n("Show as:")
			model: [i18n("City name"), i18n("Abbreviation (eg: CEST)")]
			currentIndex: page.configBridge.read("displayTimezoneAsCode", true) ? 1 : 0
			onActivated: function(index) { page.configBridge.write("displayTimezoneAsCode", index === 1) }
		}
	}
}
