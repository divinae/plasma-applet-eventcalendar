import QtQuick
import org.kde.kirigamiaddons.formcard as FormCard

import "ConfigUtils.js" as ConfigUtils

// FormCard password row bound to a string config key: hidden, with the usual button to show it.
FormCard.FormPasswordFieldDelegate {
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
