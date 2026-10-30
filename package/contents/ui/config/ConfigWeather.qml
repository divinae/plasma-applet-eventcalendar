import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kirigamiaddons.formcard as FormCard

import ".."
import "../lib"
import "../weather/OpenMeteo.js" as OpenMeteo
import "../weather/OpenWeatherMap.js" as OpenWeatherMap

// Weather source, units and meteogram look.
ConfigPage {
	id: page

	// Check App Id: what the entered app id may use (OpenWeatherMap.checkAppId).
	property var owmCheck: null // { current, daily, oneCall }: true, false (refused) or an error
	property bool owmChecking: false
	readonly property string owmCheckText: {
		if (!owmCheck) {
			return ""
		}
		function state(value) {
			return value === true ? i18nc("an API the app id may use", "yes") : value === false ? i18nc("an API the app id may not use", "no") : i18nc("%1 = error", "failed (%1)", value)
		}
		var lines = [
			i18n("Current weather, 3 hour steps: %1", state(owmCheck.current)),
			i18n("16 days (paid plan): %1", state(owmCheck.daily)),
			i18n("One Call 3.0: %1", state(owmCheck.oneCall)),
		]
		if (owmCheck.current === false) {
			lines.push(i18n("OpenWeatherMap doesn't know this app id (a new one takes up to 2 hours)."))
		} else if (owmCheck.oneCall === true && page.cfg_openWeatherMapApi !== "onecall") {
			lines.push(i18n("Choose One Call 3.0 above: by the hour and 8 days."))
		} else if (owmCheck.oneCall === false && page.cfg_openWeatherMapApi === "onecall") {
			lines.push(i18n("Not subscribed to One Call 3.0: choose Free (2.5) above."))
		}
		return lines.join("\n")
	}
	function checkOpenWeatherMapAppId() {
		owmChecking = true
		owmCheck = null
		OpenWeatherMap.checkAppId(page.cfg_openWeatherMapAppId, page.cfg_openWeatherMapCityId, function(result) {
			page.owmCheck = result
			page.owmChecking = false
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
			FormConfigPassword {
				label: i18n("API app id")
				configKey: 'openWeatherMapAppId'
				placeholderText: i18n("Required for OpenWeatherMap")
				onTextEdited: page.owmCheck = null // For another app id
			}
			FormCard.FormDelegateSeparator {}
			FormConfigCombo {
				text: i18n("API")
				configKey: 'openWeatherMapApi'
				model: [
					{ value: 'free', text: i18n("Free (2.5)") },
					{ value: 'onecall', text: i18n("One Call 3.0") },
				]
			}
			FormCard.FormDelegateSeparator {}
			FormCard.FormButtonDelegate {
				icon.name: "dialog-ok-apply"
				text: page.owmChecking ? i18n("Checking…") : i18n("Check App Id")
				description: page.owmCheckText
				// Not the built-in app id: its requests count against everyone's shared limit.
				enabled: !page.owmChecking && !!page.cfg_openWeatherMapAppId
					&& page.cfg_openWeatherMapAppId !== page.configBridge.readDefault('openWeatherMapAppId', '')
				onClicked: page.checkOpenWeatherMapAppId()
			}
		}
		// The APIs and what an app id needs for them.
		FormCard.FormSectionText {
			visible: page.service === 'OpenWeatherMap'
			text: i18n("Free (2.5) works with any app id: the current weather and a forecast in 3 hour steps for 5 days. Its forecast for 16 days needs a paid plan; without one, the days are made from the 3 hour steps.") + "<br><br>"
				+ i18n("One Call 3.0 needs the \"One Call by Call\" subscription on <a href=\"https://openweathermap.org/api/one-call-3\">openweathermap.org</a> (1000 calls a day are free, a payment card is required): the current weather, 48 hours by the hour and 8 days, in one call. The widget asks at most every 10 minutes, about 150 calls a day.") + "<br><br>"
				+ i18n("One app id works for both: Check App Id tells what yours may use.")
			textFormat: Text.StyledText
			onLinkActivated: function(link) { Qt.openUrlExternally(link) }
		}
		// The built-in app id: its request limit is shared by everyone using the widget.
		FormCard.FormSectionText {
			readonly property string appId: page.cfg_openWeatherMapAppId || ""
			visible: page.service === 'OpenWeatherMap' && (!appId || appId === page.configBridge.readDefault('openWeatherMapAppId', ''))
			text: i18n("The built-in app id is shared by everyone using this widget, and so is its request limit: the weather may stop updating at times. A free app id of your own: sign up at <a href=\"https://home.openweathermap.org/users/sign_up\">openweathermap.org</a>, then copy it from \"API keys\". Open-Meteo needs none.")
			textFormat: Text.StyledText
			onLinkActivated: function(link) { Qt.openUrlExternally(link) }
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
					{ value: 'system', text: i18n("System") },
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

		//--- The Weather panel's hourly chart (Day view)
		FormCard.FormHeader {
			title: i18n("Forecast chart")
		}
		FormCard.FormCard {
			FormConfigCombo {
				text: i18n("Style")
				description: i18n("Also the meteogram above the agenda")
				configKey: 'weatherChartStyle'
				model: [
					{ value: 'simple', text: i18n("Simple") },
					{ value: 'fancy', text: i18n("Fancy") },
				]
			}
			FormCard.FormDelegateSeparator {}
			FormConfigSwitch {
				text: i18n("Larger icons")
				description: i18n("In the chart and the next days")
				configKey: 'weatherChartLargeIcons'
			}
			FormCard.FormDelegateSeparator {}
			FormConfigSwitch {
				text: i18n("Rain amounts")
				description: i18n("The total above the chart, the amounts at the heaviest hours")
				configKey: 'weatherChartRainAmounts'
			}
		}
	}
}
