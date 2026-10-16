import QtQuick
import org.kde.kirigamiaddons.formcard as FormCard

import "ConfigUtils.js" as ConfigUtils

// FormCard combo row bound to a config key. model: [{ value, text }, ...]
FormCard.FormComboBoxDelegate {
	id: control
	property string configKey
	property var configBridge: null
	Component.onCompleted: configBridge = ConfigUtils.findBridge(control)

	textRole: "text"
	valueRole: "value"
	readonly property var configValue: configKey && configBridge ? configBridge.read(configKey, "") : ""
	currentIndex: {
		var list = model || []
		for (var i = 0; i < list.length; i++) {
			if (list[i].value === configValue) {
				return i
			}
		}
		return 0
	}
	onActivated: function(index) {
		if (configBridge && configKey && model && model[index]) {
			configBridge.write(configKey, model[index].value)
		}
	}
}
