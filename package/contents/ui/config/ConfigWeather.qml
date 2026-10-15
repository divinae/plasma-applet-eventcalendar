import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import ".."
import "../lib"

// Weather source, units and meteogram look.
ConfigPage {
	id: page

	AppletConfig { id: config }

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
				{ value: 'OpenWeatherMap', text: 'OpenWeatherMap' },
				{ value: 'WeatherCanada', text: 'Weather Canada' },
			]
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
			visible: page.configBridge.read("debugging", false) && weatherService.value === 'OpenWeatherMap'
			Kirigami.FormData.label: i18n("API app id:")
			configKey: 'openWeatherMapAppId'
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

		//--- Colors
		Kirigami.Separator {
			Kirigami.FormData.isSection: true
			Kirigami.FormData.label: i18n("Meteogram Colors")
		}
		ConfigColor {
			Kirigami.FormData.label: i18n("Text:")
			label: ""
			configKey: 'meteogramTextColor'
			defaultColor: config.meteogramTextColorDefault
		}
		ConfigColor {
			Kirigami.FormData.label: i18n("Grid:")
			label: ""
			configKey: 'meteogramGridColor'
			defaultColor: config.meteogramScaleColorDefault
		}
		ConfigColor {
			Kirigami.FormData.label: i18n("Rain:")
			label: ""
			configKey: 'meteogramRainColor'
			defaultColor: config.meteogramPrecipitationRawColorDefault
		}
		ConfigColor {
			Kirigami.FormData.label: i18n("Above zero:")
			label: ""
			configKey: 'meteogramPositiveTempColor'
			defaultColor: config.meteogramPositiveTempColorDefault
		}
		ConfigColor {
			Kirigami.FormData.label: i18n("Below zero:")
			label: ""
			configKey: 'meteogramNegativeTempColor'
			defaultColor: config.meteogramNegativeTempColorDefault
		}
		ConfigColor {
			Kirigami.FormData.label: i18n("Icons:")
			label: ""
			configKey: 'meteogramIconColor'
			defaultColor: config.meteogramIconColorDefault
		}
	}
}
