import QtQuick
import org.kde.kirigamiaddons.formcard as FormCard

import "ConfigUtils.js" as ConfigUtils

// FormCard spin box row bound to an integer config key, with an optional unit suffix.
FormCard.FormSpinBoxDelegate {
	id: control
	property string configKey
	property string suffix: ""
	property var configBridge: null
	Component.onCompleted: configBridge = ConfigUtils.findBridge(control)

	value: configKey && configBridge ? (configBridge.read(configKey, 0) || 0) : 0
	textFromValue: function(value, locale) {
		return Number(value).toLocaleString(locale, 'f', 0) + control.suffix
	}
	valueFromText: function(text, locale) {
		return Number.fromLocaleString(locale, String(text).replace(control.suffix, '').trim())
	}
	onValueModified: {
		if (configBridge && configKey) {
			configBridge.write(configKey, value)
		}
	}
}
