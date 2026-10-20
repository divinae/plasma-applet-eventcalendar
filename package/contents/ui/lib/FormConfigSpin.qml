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
	// Not onValueModified: FormSpinBoxDelegate has it only after Kirigami Addons 1.12 (Debian 14
	// ships 1.12), and an unknown handler fails the whole settings page. Writing the value it was
	// bound to is a no-op (configBridge.write compares).
	onValueChanged: {
		if (configBridge && configKey) {
			configBridge.write(configKey, value)
		}
	}
}
