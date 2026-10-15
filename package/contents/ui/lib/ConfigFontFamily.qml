// Version 3

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs as QtDialogs
import QtQuick.Layouts

import "ConfigUtils.js" as ConfigUtils

// A ComboBox listing Qt.fontFamilies() takes seconds to load with the
// org.kde.desktop style, which measures every item. Use the font dialog instead.
RowLayout {
	id: configFontFamily

	property string configKey: ''
	property alias before: labelBefore.text
	property alias after: labelAfter.text
	property var configBridge: null

	readonly property string configValue: {
		if (!configKey) {
			return ""
		}
		if (configBridge) {
			var bridged = configBridge.read(configKey, "")
			return (bridged === undefined || bridged === null) ? "" : String(bridged)
		}
		if (typeof plasmoid !== "undefined" && plasmoid.configuration) {
			var directValue = plasmoid.configuration[configKey]
			return (directValue === undefined || directValue === null) ? "" : String(directValue)
		}
		return ""
	}

	Component.onCompleted: {
		configBridge = ConfigUtils.findBridge(configFontFamily)
	}

	function setValue(val) {
		if (!configKey) {
			return
		}
		if (configBridge) {
			configBridge.write(configKey, val)
		} else if (typeof plasmoid !== "undefined" && plasmoid.configuration) {
			plasmoid.configuration[configKey] = val
			if (typeof kcm !== "undefined") {
				kcm.needsSave = true
			}
		}
	}

	// Same name as ConfigComboBox.selectValue
	function selectValue(val) {
		setValue(val)
	}

	Label {
		id: labelBefore
		text: ""
		visible: text
	}

	Button {
		text: configFontFamily.configValue || i18nc("Use default font", "Default")
		icon.name: "preferences-desktop-font"
		onClicked: {
			if (configFontFamily.configValue) {
				fontDialog.selectedFont = Qt.font({ family: configFontFamily.configValue })
			}
			fontDialog.open()
		}
	}

	Button {
		icon.name: "edit-clear"
		visible: configFontFamily.configValue !== ""
		onClicked: configFontFamily.setValue("")
		ToolTip.text: i18nc("Use default font", "Default")
		ToolTip.visible: hovered
	}

	Label {
		id: labelAfter
		text: ""
		visible: text
	}

	QtDialogs.FontDialog {
		id: fontDialog
		title: i18n("Choose a Font")
		onAccepted: configFontFamily.setValue(selectedFont.family)
	}
}
