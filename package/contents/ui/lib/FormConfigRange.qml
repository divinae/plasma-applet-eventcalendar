import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kirigamiaddons.formcard as FormCard

import "ConfigUtils.js" as ConfigUtils

// Two integer config keys in one FormCard row: a label, then "[first] separator [second]" (eg:
// popup width × height, working hours from – to). Plain SpinBoxes, so it works with every Kirigami
// Addons version.
FormCard.AbstractFormDelegate {
	id: control
	property string label
	property string firstKey
	property string secondKey
	property int firstFrom: 0
	property int firstTo: 100
	property int secondFrom: 0
	property int secondTo: 100
	property int stepSize: 1
	property string separator: "–"
	property string suffix: "" // After each value (eg: " px", ":00")
	property var configBridge: null
	Component.onCompleted: configBridge = ConfigUtils.findBridge(control)

	background: null
	contentItem: RowLayout {
		spacing: Kirigami.Units.smallSpacing
		QQC2.Label {
			Layout.fillWidth: true
			text: control.label
			textFormat: Text.PlainText
			elide: Text.ElideRight
		}
		RangeSpin {
			configKey: control.firstKey
			from: control.firstFrom
			to: control.firstTo
			Accessible.name: control.label
		}
		QQC2.Label {
			text: control.separator
			textFormat: Text.PlainText
		}
		RangeSpin {
			configKey: control.secondKey
			from: control.secondFrom
			to: control.secondTo
			Accessible.name: control.label
		}
	}

	component RangeSpin: QQC2.SpinBox {
		property string configKey
		editable: true
		stepSize: control.stepSize
		value: configKey && control.configBridge ? (control.configBridge.read(configKey, 0) || 0) : 0
		textFromValue: function(value, locale) {
			return Number(value).toLocaleString(locale, 'f', 0) + control.suffix
		}
		valueFromText: function(text, locale) {
			return Number.fromLocaleString(locale, String(text).replace(control.suffix, '').trim())
		}
		onValueModified: {
			if (control.configBridge && configKey) {
				control.configBridge.write(configKey, value)
			}
		}
	}
}
