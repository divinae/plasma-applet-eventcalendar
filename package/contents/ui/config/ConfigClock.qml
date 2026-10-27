import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kirigamiaddons.formcard as FormCard

import ".."
import "../lib"
import "../Shared.js" as Shared

// Panel clock: time / date formats, font, next meeting chip.
ConfigPage {
	id: page

	readonly property string localeTimeFormat: Qt.locale().timeFormat(Locale.ShortFormat)
	readonly property string localeDateFormat: Qt.locale().dateFormat(Locale.ShortFormat)
	readonly property string longDateNoWeekday: {
		// Like org.kde.plasma.digitalclock: drop "dddd" from the long date format.
		return Qt.locale().dateFormat(Locale.LongFormat).replace(/(^dddd.?\s)|(,?\sdddd$)/, "")
	}

	// Format presets; "" means the locale default. The last entry is "Custom".
	readonly property var timePresets: [
		{ format: "", text: i18n("Default (%1)", Shared.formatTime(new Date(), localeTimeFormat)) },
		{ format: "HH:mm", text: Shared.formatTime(new Date(), "HH:mm") + " " + i18n("(24-hour)") },
		{ format: "h:mm AP", text: Shared.formatTime(new Date(), "h:mm AP") + " " + i18n("(12-hour)") },
		{ format: localeTimeFormat.replace('mm', 'mm:ss'), text: Shared.formatTime(new Date(), localeTimeFormat.replace('mm', 'mm:ss')) + " " + i18n("(with seconds)") },
	]
	readonly property var datePresets: [
		{ format: "", text: i18n("Default (%1)", Shared.formatDate(new Date(), localeDateFormat)) },
		{ format: longDateNoWeekday, text: Shared.formatDate(new Date(), longDateNoWeekday) },
		{ format: "ddd d MMM", text: Shared.formatDate(new Date(), "ddd d MMM") },
		{ format: "MMM d", text: Shared.formatDate(new Date(), "MMM d") },
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
			Layout.fillWidth: true
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
			text: formatField.value ? Shared.formatDateTime(new Date(), formatField.value) : ""
			opacity: 0.7
		}
	}

	// A labeled custom row inside a card: title above, any control below.
	component LabeledRow: FormCard.AbstractFormDelegate {
		id: labeledRow
		property string title
		default property alias rowContent: rowColumn.data
		Layout.fillWidth: true
		background: null
		contentItem: ColumnLayout {
			id: rowColumn
			spacing: Kirigami.Units.smallSpacing
			Label {
				Layout.fillWidth: true
				text: labeledRow.title
				elide: Text.ElideRight
			}
		}
	}

	ColumnLayout {
		Layout.fillWidth: true
		spacing: 0

		//--- Time
		FormCard.FormHeader {
			title: i18n("Time")
		}
		FormCard.FormCard {
			LabeledRow {
				title: i18n("Format")
				FormatPicker {
					Layout.fillWidth: true
					configKey: 'clockTimeFormat1'
					presets: page.timePresets
				}
			}
			FormCard.FormDelegateSeparator {}
			FormConfigSwitch {
				text: i18n("Bold")
				configKey: 'clockLineBold1'
			}
			FormCard.FormDelegateSeparator {}
			LabeledRow {
				title: i18n("Font")
				ConfigFontFamily {
					Layout.fillWidth: true
					configKey: 'clockFontFamily'
				}
			}
			FormCard.FormDelegateSeparator {}
			FormConfigSpin {
				label: i18n("Maximum height")
				hint: i18n("0 = fit the panel")
				configKey: 'clockMaxHeight'
				suffix: i18n(" px")
				from: 0
				to: 1000
			}
		}
		FormCard.FormSectionText {
			text: i18n("Custom formats use the <a href=\"https://doc.qt.io/qt-6/qml-qtqml-qt.html#formatDateTime-method\">Qt date and time format</a>, eg: HH:mm, ddd d MMM.")
			onLinkActivated: function(link) { Shared.openExternalUrl(link) }
		}

		//--- Second line
		FormCard.FormHeader {
			title: i18n("Second Line")
		}
		FormCard.FormCard {
			FormConfigSwitch {
				id: clockShowLine2
				text: i18n("Show a second line")
				description: i18n("Eg: the date")
				configKey: 'clockShowLine2'
			}
			FormCard.FormDelegateSeparator { visible: clockShowLine2.checked }
			LabeledRow {
				visible: clockShowLine2.checked
				title: i18n("Format")
				FormatPicker {
					Layout.fillWidth: true
					configKey: 'clockTimeFormat2'
					presets: page.datePresets
				}
			}
			FormCard.FormDelegateSeparator { visible: clockShowLine2.checked }
			FormConfigSwitch {
				visible: clockShowLine2.checked
				text: i18n("Bold")
				configKey: 'clockLineBold2'
			}
			FormCard.FormDelegateSeparator { visible: clockShowLine2.checked }
			LabeledRow {
				visible: clockShowLine2.checked
				title: i18n("Size")
				ConfigSlider {
					Layout.fillWidth: true
					configKey: 'clockLine2HeightRatio'
					minimumValue: 0.3
					maximumValue: 0.7
					stepSize: 0.05
				}
			}
		}

		//--- Next meeting
		FormCard.FormHeader {
			title: i18n("Next Meeting")
		}
		FormCard.FormCard {
			FormConfigSwitch {
				id: clockShowNextEvent
				text: i18n("Show next to the clock")
				configKey: 'clockShowNextEvent'
			}
			FormCard.FormDelegateSeparator { visible: clockShowNextEvent.checked }
			FormConfigSpin {
				visible: clockShowNextEvent.checked
				label: i18n("When it starts within")
				configKey: 'clockNextEventMinutes'
				suffix: i18n(" min")
				from: 5
				to: 1440
			}
			FormCard.FormDelegateSeparator { visible: clockShowNextEvent.checked }
			FormConfigSwitch {
				visible: clockShowNextEvent.checked
				text: i18n("Progress of the current meeting")
				description: i18n("A thin bar under the meeting's name, in its calendar's color.")
				configKey: 'clockShowMeetingProgress'
			}
		}
		FormCard.FormSectionText {
			text: i18n("Middle-click the clock to join the current or next meeting.")
		}

		//--- Other
		FormCard.FormHeader {
			title: i18n("Other")
		}
		FormCard.FormCard {
			FormConfigSwitch {
				text: i18n("Show background")
				description: i18n("Desktop widget")
				configKey: 'showBackground'
			}
			FormCard.FormDelegateSeparator {}
			FormConfigSwitch {
				text: i18n("Debug logging and extra settings pages")
				configKey: 'debugging'
			}
		}
	}
}
