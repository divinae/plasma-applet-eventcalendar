import QtQuick
import org.kde.kirigamiaddons.formcard as FormCard

import "ConfigUtils.js" as ConfigUtils

// FormCard combo row bound to a config key. model: [{ value, text }, ...]
FormCard.FormComboBoxDelegate {
	id: control
	property string configKey
	property var configBridge: null
	Component.onCompleted: {
		configBridge = ConfigUtils.findBridge(control)
		Qt.callLater(syncIndex)
	}

	textRole: "text"
	valueRole: "value"
	readonly property var configValue: configKey && configBridge ? configBridge.read(configKey, "") : ""
	// The row of the value, set (not bound): the inner ComboBox resets its index when the model is
	// replaced (eg: "System (%1)" once the icon theme's name is known) and a choice overwrites a
	// binding, so the row showed another value than the one kept, and choosing that one changed nothing.
	function syncIndex() {
		var list = model || []
		var index = 0
		for (var i = 0; i < list.length; i++) {
			if (list[i].value === configValue) {
				index = i
				break
			}
		}
		if (currentIndex !== index) {
			currentIndex = index
		}
	}
	onConfigValueChanged: syncIndex()
	onModelChanged: Qt.callLater(syncIndex) // After the inner ComboBox's reset
	onActivated: function(index) {
		if (configBridge && configKey && model && model[index]) {
			configBridge.write(configKey, model[index].value)
		}
	}
}
