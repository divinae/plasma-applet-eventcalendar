import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import ".."
import "../lib"
import "../Shared.js" as Shared

// Panel clock: time / date formats, font, next meeting chip.
ConfigPage {
	id: page
	showAppletVersion: true

	readonly property string localeTimeFormat: Qt.locale().timeFormat(Locale.ShortFormat)
	readonly property string localeDateFormat: Qt.locale().dateFormat(Locale.ShortFormat)
	readonly property string longDateNoWeekday: {
		// Like org.kde.plasma.digitalclock: drop "dddd" from the long date format.
		return Qt.locale().dateFormat(Locale.LongFormat).replace(/(^dddd.?\s)|(,?\sdddd$)/, "")
	}

	// Format presets; "" means the locale default. The last entry is "Custom".
	readonly property var timePresets: [
		{ format: "", text: i18n("Default (%1)", Qt.formatTime(new Date(), localeTimeFormat)) },
		{ format: "HH:mm", text: Qt.formatTime(new Date(), "HH:mm") + " " + i18n("(24-hour)") },
		{ format: "h:mm AP", text: Qt.formatTime(new Date(), "h:mm AP") + " " + i18n("(12-hour)") },
		{ format: localeTimeFormat.replace('mm', 'mm:ss'), text: Qt.formatTime(new Date(), localeTimeFormat.replace('mm', 'mm:ss')) + " " + i18n("(with seconds)") },
	]
	readonly property var datePresets: [
		{ format: "", text: i18n("Default (%1)", Qt.formatDate(new Date(), localeDateFormat)) },
		{ format: longDateNoWeekday, text: Qt.formatDate(new Date(), longDateNoWeekday) },
		{ format: "ddd d MMM", text: Qt.formatDate(new Date(), "ddd d MMM") },
		{ format: "MMM d", text: Qt.formatDate(new Date(), "MMM d") },
	]

	// A format combo: presets + "Custom…" that shows the text field.
	component FormatPicker: RowLayout {
		id: picker
		property string configKey
		property var presets: []
		property alias field: formatField
		readonly property string currentFormat: formatField.value
		readonly property int presetIndex: {
			for (var i = 0; i < presets.length; i++) {
				if (presets[i].format === currentFormat) {
					return i
				}
			}
			return -1
		}
		property bool customChosen: false
		readonly property bool showCustom: customChosen || presetIndex < 0

		ComboBox {
			model: picker.presets.map(function(p) { return p.text }).concat([i18n("Custom…")])
			currentIndex: picker.showCustom ? picker.presets.length : picker.presetIndex
			onActivated: function(index) {
				if (index < picker.presets.length) {
					picker.customChosen = false
					formatField.text = picker.presets[index].format
				} else {
					picker.customChosen = true
					formatField.forceActiveFocus()
				}
			}
		}
		ConfigString {
			id: formatField
			visible: picker.showCustom
			configKey: picker.configKey
			Layout.preferredWidth: Kirigami.Units.gridUnit * 7
		}
		Label {
			visible: picker.showCustom
			text: formatField.value ? Qt.formatDateTime(new Date(), formatField.value) : ""
			opacity: 0.7
		}
	}

	Kirigami.FormLayout {
		Layout.fillWidth: true

		//--- Time
		Kirigami.Separator {
			Kirigami.FormData.isSection: true
			Kirigami.FormData.label: i18n("Time")
		}
		FormatPicker {
			Kirigami.FormData.label: i18n("Format:")
			configKey: 'clockTimeFormat1'
			presets: page.timePresets
		}
		ConfigCheckBox {
			configKey: 'clockLineBold1'
			text: i18n("Bold")
		}
		ConfigFontFamily {
			Kirigami.FormData.label: i18n("Font:")
			configKey: 'clockFontFamily'
		}
		ConfigSpinBox {
			Kirigami.FormData.label: i18n("Maximum height:")
			configKey: 'clockMaxHeight'
			suffix: i18n(" px")
			after: i18n("(0 = fit the panel)")
		}
		Label {
			Layout.fillWidth: true
			Layout.maximumWidth: Kirigami.Units.gridUnit * 20
			wrapMode: Text.Wrap
			opacity: 0.7
			text: i18n("Custom formats use the <a href=\"https://doc.qt.io/qt-6/qml-qtqml-qt.html#formatDateTime-method\">Qt date and time format</a>, eg: HH:mm, ddd d MMM.")
			onLinkActivated: function(link) { Shared.openExternalUrl(link) }
		}

		//--- Second line
		Kirigami.Separator {
			Kirigami.FormData.isSection: true
			Kirigami.FormData.label: i18n("Second Line")
		}
		ConfigCheckBox {
			id: clockShowLine2
			configKey: 'clockShowLine2'
			text: i18n("Show a second line (eg: the date)")
		}
		FormatPicker {
			enabled: clockShowLine2.checked
			Kirigami.FormData.label: i18n("Format:")
			configKey: 'clockTimeFormat2'
			presets: page.datePresets
		}
		ConfigCheckBox {
			enabled: clockShowLine2.checked
			configKey: 'clockLineBold2'
			text: i18n("Bold")
		}
		ConfigSlider {
			enabled: clockShowLine2.checked
			Kirigami.FormData.label: i18n("Size:")
			configKey: 'clockLine2HeightRatio'
			minimumValue: 0.3
			maximumValue: 0.7
			stepSize: 0.05
			Layout.preferredWidth: Kirigami.Units.gridUnit * 10
		}

		//--- Next meeting
		Kirigami.Separator {
			Kirigami.FormData.isSection: true
			Kirigami.FormData.label: i18n("Next Meeting")
		}
		RowLayout {
			ConfigCheckBox {
				id: clockShowNextEvent
				configKey: 'clockShowNextEvent'
				text: i18n("Show next to the clock when it starts within")
			}
			ConfigSpinBox {
				enabled: clockShowNextEvent.checked
				configKey: 'clockNextEventMinutes'
				suffix: i18n(" min")
				minimumValue: 5
				maximumValue: 1440
			}
		}
		Label {
			Layout.fillWidth: true
			Layout.maximumWidth: Kirigami.Units.gridUnit * 20
			wrapMode: Text.Wrap
			opacity: 0.7
			text: i18n("Middle-click the clock to join the current or next meeting.")
		}

		//--- Other
		Kirigami.Separator {
			Kirigami.FormData.isSection: true
			Kirigami.FormData.label: i18n("Other")
		}
		ConfigCheckBox {
			configKey: 'showBackground'
			text: i18n("Show background (desktop widget)")
		}
		ConfigCheckBox {
			configKey: 'debugging'
			text: i18n("Debug logging and extra settings pages")
		}
	}
}
