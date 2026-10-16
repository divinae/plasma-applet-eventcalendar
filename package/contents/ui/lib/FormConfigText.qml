import QtQuick
import org.kde.kirigamiaddons.formcard as FormCard

import "ConfigUtils.js" as ConfigUtils

// FormCard text field row bound to a string config key.
FormCard.FormTextFieldDelegate {
	id: control
	property string configKey
	property var configBridge: null
	Component.onCompleted: {
		configBridge = ConfigUtils.findBridge(control)
		if (configBridge && configKey) {
			text = configBridge.read(configKey, "") || ""
		}
	}
	onTextEdited: {
		if (configBridge && configKey) {
			configBridge.write(configKey, text)
		}
	}
}
