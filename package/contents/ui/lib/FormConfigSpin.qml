import QtQuick
import org.kde.kirigamiaddons.formcard as FormCard

import "ConfigUtils.js" as ConfigUtils

// FormCard spin box row bound to an integer config key, with an optional unit suffix.
FormCard.FormSpinBoxDelegate {
	id: control
	property string configKey
	property string suffix: ""
	property var configBridge: null
	// A line under the label (eg: "0 = off"). FormSpinBoxDelegate has a description only in newer
	// Kirigami Addons (not 1.7, Debian 13): set when it's there, else left out, since assigning an
	// unknown property fails the whole settings page.
	property string hint: ""
	Component.onCompleted: {
		configBridge = ConfigUtils.findBridge(control)
		if (hint && 'description' in control) {
			control.description = hint
		}
	}

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
