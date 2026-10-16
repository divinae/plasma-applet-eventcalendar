import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import ".."
import "../lib"
import "../weather/OpenMeteo.js" as OpenMeteo

// Weather source, units and meteogram look.
ConfigPage {
	id: page

	property var locationResults: []
	property bool searchingLocations: false
	property bool locationSearchDone: false
	function searchLocations() {
		var query = locationSearchField.text.trim()
		if (query.length < 2) {
			return
		}
		searchingLocations = true
		OpenMeteo.searchLocations(query, Qt.locale().name.split('_')[0], function(err, results) {
			searchingLocations = false
			locationSearchDone = true
			locationResults = results || []
		})
	}

	OpenWeatherMapCityDialog {
		id: openWeatherMapCityDialog
		onAccepted: weatherCityId.value = selectedCityId
	}
	WeatherCanadaCityDialog {
		id: weatherCanadaCityDialog
		onAccepted: weatherCanadaCityId.value = selectedCityId
	}

	Kirigami.FormLayout {
		Layout.fillWidth: true

		//--- Source
		Kirigami.Separator {
			Kirigami.FormData.isSection: true
			Kirigami.FormData.label: i18n("Source")
		}
		ConfigComboBox {
			id: weatherService
			Kirigami.FormData.label: i18n("Service:")
			configKey: 'weatherService'
			model: [
				{ value: 'OpenMeteo', text: i18n("Open-Meteo (free, no API key)") },
				{ value: 'OpenWeatherMap', text: 'OpenWeatherMap' },
				{ value: 'WeatherCanada', text: 'Weather Canada' },
			]
		}

		// Open-Meteo: search a place by name and pick it.
		Label {
			visible: weatherService.value === 'OpenMeteo'
			Kirigami.FormData.label: i18n("Location:")
			text: page.configBridge.read("openMeteoLocationName", "") || i18n("Not set")
			font.bold: !!page.configBridge.read("openMeteoLocationName", "")
		}
		RowLayout {
			visible: weatherService.value === 'OpenMeteo'
			Kirigami.FormData.label: i18n("Find a place:")
			TextField {
				id: locationSearchField
				Layout.preferredWidth: Kirigami.Units.gridUnit * 12
				placeholderText: i18n("City name, eg: Warszawa")
				onAccepted: page.searchLocations()
			}
			Button {
				icon.name: "search"
				text: i18n("Search")
				enabled: locationSearchField.text.trim().length > 1 && !page.searchingLocations
				onClicked: page.searchLocations()
			}
			BusyIndicator {
				visible: page.searchingLocations
				running: visible
				Layout.preferredHeight: Kirigami.Units.iconSizes.small
				Layout.preferredWidth: Layout.preferredHeight
			}
		}
		Label {
			visible: weatherService.value === 'OpenMeteo' && page.locationSearchDone && page.locationResults.length === 0
			text: i18n("No places found.")
			opacity: 0.7
		}
		ColumnLayout {
			visible: weatherService.value === 'OpenMeteo' && page.locationResults.length > 0
			spacing: 0
			Repeater {
				model: page.locationResults
				ToolButton {
					readonly property string label: [modelData.name, modelData.region, modelData.country].filter(function(s) { return !!s }).join(", ")
					text: label
					icon.name: "mark-location"
					onClicked: {
						page.configBridge.write("openMeteoLatitude", modelData.latitude)
						page.configBridge.write("openMeteoLongitude", modelData.longitude)
						page.configBridge.write("openMeteoLocationName", modelData.name + (modelData.country ? ", " + modelData.country : ""))
						page.configBridge.write("weatherService", "OpenMeteo")
						page.locationResults = []
						page.locationSearchDone = false
						locationSearchField.text = ""
					}
				}
			}
		}
		RowLayout {
			visible: weatherService.value === 'OpenWeatherMap'
			Kirigami.FormData.label: i18n("City:")
			ConfigString {
				id: weatherCityId
				configKey: 'openWeatherMapCityId'
				placeholderText: i18n("City id, eg: 5983720")
			}
			Button {
				icon.name: "search"
				text: i18n("Find City…")
				onClicked: openWeatherMapCityDialog.open()
			}
		}
		RowLayout {
			visible: weatherService.value === 'WeatherCanada'
			Kirigami.FormData.label: i18n("City:")
			ConfigString {
				id: weatherCanadaCityId
				configKey: 'weatherCanadaCityId'
				placeholderText: i18n("City id, eg: on-14")
			}
			Button {
				icon.name: "search"
				text: i18n("Find City…")
				onClicked: weatherCanadaCityDialog.open()
			}
		}
		ConfigString {
			visible: weatherService.value === 'OpenWeatherMap'
			Kirigami.FormData.label: i18n("API app id:")
			configKey: 'openWeatherMapAppId'
			echoMode: TextInput.Password
			placeholderText: i18n("Required for OpenWeatherMap")
		}

		//--- Display
		Kirigami.Separator {
			Kirigami.FormData.isSection: true
			Kirigami.FormData.label: i18n("Display")
		}
		ConfigComboBox {
			Kirigami.FormData.label: i18n("Units:")
			configKey: 'weatherUnits'
			model: [
				{ value: 'metric', text: i18n("Celsius") },
				{ value: 'imperial', text: i18n("Fahrenheit") },
				{ value: 'kelvin', text: i18n("Kelvin") },
			]
		}
		ConfigSpinBox {
			Kirigami.FormData.label: i18n("Meteogram shows:")
			configKey: 'meteogramHours'
			suffix: i18n(" hours")
			minimumValue: 9
			maximumValue: 48
			stepSize: 3
		}

	}
}
