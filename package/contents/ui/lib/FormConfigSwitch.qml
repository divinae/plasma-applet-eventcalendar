import QtQuick
import org.kde.kirigamiaddons.formcard as FormCard

import "ConfigUtils.js" as ConfigUtils

// FormCard switch row bound to a config key (via the page's configBridge).
FormCard.FormSwitchDelegate {
	id: control
	property string configKey
	property var configBridge: null
	Component.onCompleted: configBridge = ConfigUtils.findBridge(control)

	checked: !!configKey && !!configBridge && !!configBridge.read(configKey, false)
	onToggled: {
		if (configBridge && configKey) {
			configBridge.write(configKey, checked)
		}
	}
}
