import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kirigamiaddons.formcard as FormCard

import ".."
import "../lib"
import "../weather/OpenMeteo.js" as OpenMeteo

// Weather source, units and meteogram look.
ConfigPage {
	id: page

	// The icon theme's name for "System (Breeze)": its index.theme Name, else the directory name.
	property string iconThemeName: ""
	ExecUtil { id: iconThemeReader }
	Component.onCompleted: {
		var script = 't=$(kreadconfig6 --group Icons --key Theme); t=${t:-breeze}; '
			+ 'for d in "${XDG_DATA_HOME:-$HOME/.local/share}" $(echo "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}" | tr : " "); do '
			+ 'if [ -f "$d/icons/$t/index.theme" ]; then kreadconfig6 --file "$d/icons/$t/index.theme" --group "Icon Theme" --key Name; exit 0; fi; '
			+ 'done; echo "$t"'
		iconThemeReader.execArgv(['sh', '-c', script], function(cmd, exitCode, exitStatus, stdout) {
			page.iconThemeName = String(stdout || "").trim()
		})
	}

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
		onAccepted: page.configBridge.write('openWeatherMapCityId', selectedCityId)
	}
	WeatherCanadaCityDialog {
		id: weatherCanadaCityDialog
		onAccepted: page.configBridge.write('weatherCanadaCityId', selectedCityId)
	}

	readonly property string service: weatherService.currentValue || weatherService.configValue // The combo shows the first service when unset

	ColumnLayout {
		Layout.fillWidth: true
		spacing: 0

		//--- Source
		FormCard.FormHeader {
			title: i18n("Source")
		}
		FormCard.FormCard {
			FormConfigCombo {
				id: weatherService
				text: i18n("Service")
				configKey: 'weatherService'
				model: [
					{ value: 'OpenMeteo', text: i18n("Open-Meteo (free, no API key)") },
					{ value: 'OpenWeatherMap', text: 'OpenWeatherMap' },
					{ value: 'WeatherCanada', text: 'Weather Canada' },
				]
			}
		}

		//--- Open-Meteo: search a place by name and pick it.
		FormCard.FormHeader {
			visible: page.service === 'OpenMeteo'
			title: i18n("Location")
		}
		FormCard.FormCard {
			visible: page.service === 'OpenMeteo'
			FormCard.FormTextDelegate {
				text: i18n("Current location")
				description: page.configBridge.read("openMeteoLocationName", "") || i18n("Not set")
			}
			FormCard.FormDelegateSeparator {}
			FormCard.AbstractFormDelegate {
				background: null
				contentItem: RowLayout {
					spacing: Kirigami.Units.smallSpacing
					QQC2.TextField {
						id: locationSearchField
						Layout.fillWidth: true
						placeholderText: i18n("City name, eg: Warszawa")
						onAccepted: page.searchLocations()
					}
					QQC2.Button {
						icon.name: "search"
						text: i18n("Search")
						enabled: locationSearchField.text.trim().length > 1 && !page.searchingLocations
						onClicked: page.searchLocations()
					}
					QQC2.BusyIndicator {
						visible: page.searchingLocations
						running: visible
						Layout.preferredHeight: Kirigami.Units.iconSizes.small
						Layout.preferredWidth: Layout.preferredHeight
					}
				}
			}
			FormCard.FormTextDelegate {
				visible: page.locationSearchDone && page.locationResults.length === 0
				text: i18n("No places found.")
			}
			Repeater {
				model: page.locationResults
				FormCard.FormButtonDelegate {
					text: [modelData.name, modelData.region, modelData.country].filter(function(s) { return !!s }).join(", ")
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

		//--- OpenWeatherMap
		FormCard.FormHeader {
			visible: page.service === 'OpenWeatherMap'
			title: i18n("OpenWeatherMap")
		}
		FormCard.FormCard {
			visible: page.service === 'OpenWeatherMap'
			FormConfigText {
				id: weatherCityId
				label: i18n("City id")
				configKey: 'openWeatherMapCityId'
				placeholderText: i18n("eg: 5983720")
				// The dialog writes the key: show the new value.
				Connections {
					target: page
					function onCfg_openWeatherMapCityIdChanged() { weatherCityId.text = page.cfg_openWeatherMapCityId || "" }
				}
			}
			FormCard.FormDelegateSeparator {}
			FormCard.FormButtonDelegate {
				icon.name: "search"
				text: i18n("Find City…")
				onClicked: openWeatherMapCityDialog.open()
			}
			FormCard.FormDelegateSeparator {}
			FormConfigText {
				label: i18n("API app id")
				configKey: 'openWeatherMapAppId'
				echoMode: TextInput.Password
				placeholderText: i18n("Required for OpenWeatherMap")
			}
		}

		//--- Weather Canada
		FormCard.FormHeader {
			visible: page.service === 'WeatherCanada'
			title: i18n("Weather Canada")
		}
		FormCard.FormCard {
			visible: page.service === 'WeatherCanada'
			FormConfigText {
				id: weatherCanadaCityId
				label: i18n("City id")
				configKey: 'weatherCanadaCityId'
				placeholderText: i18n("eg: on-14")
				Connections {
					target: page
					function onCfg_weatherCanadaCityIdChanged() { weatherCanadaCityId.text = page.cfg_weatherCanadaCityId || "" }
				}
			}
			FormCard.FormDelegateSeparator {}
			FormCard.FormButtonDelegate {
				icon.name: "search"
				text: i18n("Find City…")
				onClicked: weatherCanadaCityDialog.open()
			}
		}

		//--- Display
		FormCard.FormHeader {
			title: i18n("Display")
		}
		FormCard.FormCard {
			FormConfigCombo {
				text: i18n("Units")
				configKey: 'weatherUnits'
				model: [
					{ value: 'metric', text: i18n("Celsius") },
					{ value: 'imperial', text: i18n("Fahrenheit") },
					{ value: 'kelvin', text: i18n("Kelvin") },
				]
			}
			FormCard.FormDelegateSeparator {}
			FormConfigCombo {
				text: i18n("Icons")
				configKey: 'weatherIconStyle'
				model: [
					{ value: 'system', text: page.iconThemeName ? i18nc("%1 = icon theme, eg: Breeze", "System (%1)", page.iconThemeName) : i18n("System") },
					{ value: 'yr', text: i18n("Yr (MET Norway)") },
				]
			}
			FormCard.FormDelegateSeparator {}
			FormConfigCombo {
				text: i18n("Current weather icon background")
				configKey: 'weatherIconBackground'
				model: [
					{ value: 'sky', text: i18n("Sky, after the weather") },
					{ value: 'subtle', text: i18n("Subtle") },
					{ value: 'none', text: i18nc("no icon background", "None") },
				]
			}
			FormCard.FormDelegateSeparator {}
			FormConfigSpin {
				label: i18n("Meteogram shows")
				configKey: 'meteogramHours'
				suffix: i18n(" hours")
				from: 9
				to: 48
				stepSize: 3
			}
		}
	}
}
