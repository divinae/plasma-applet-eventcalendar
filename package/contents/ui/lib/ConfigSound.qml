// Version 5

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

RowLayout {
	id: configSound
	property alias label: sfxEnabledCheckBox.text
	property alias sfxEnabledKey: sfxEnabledCheckBox.configKey
	property alias sfxPathKey: sfxPath.configKey

	property alias sfxEnabled: sfxEnabledCheckBox.checked
	property alias sfxPathValue: sfxPath.value
	property alias sfxPathDefaultValue: sfxPath.defaultValue

	// Preview with the same players the notifications use (QtMultimedia crashed plasmashell:
	// https://github.com/Zren/plasma-applet-eventcalendar/issues/84
	// https://github.com/Zren/plasma-applet-eventcalendar/issues/167).
	property var soundPlayer: SoundPlayer {}

	function isAllowedSoundPath(path) {
		if (!path) {
			return false
		}
		var normalizedPath = ("" + path).trim()
		if (normalizedPath.indexOf('file://') === 0) {
			normalizedPath = normalizedPath.slice('file://'.length)
		}
		return normalizedPath.indexOf('/') === 0 && /\.(wav|mp3|oga|ogg)$/i.test(normalizedPath)
	}

	spacing: 0
	ConfigCheckBox {
		id: sfxEnabledCheckBox
	}
	Button {
		icon.name: "media-playback-start-symbolic"
		enabled: sfxEnabled && isAllowedSoundPath(sfxPath.value)
		onClicked: configSound.soundPlayer.play(sfxPath.value)
		ToolTip.text: i18n("Play")
		ToolTip.visible: hovered
	}
	ConfigString {
		id: sfxPath
		enabled: sfxEnabled
		Layout.fillWidth: true
	}
	Button {
		icon.name: "folder-symbolic"
		enabled: sfxEnabled
		onClicked: sfxPathDialog.open()

		FileDialog {
			id: sfxPathDialog
			title: i18n("Choose a sound effect")
			currentFolder: "file:///usr/share/sounds"
			nameFilters: [
				i18n("Sound files (%1)", "*.wav *.mp3 *.oga *.ogg"),
				i18n("All files (%1)", "*"),
			]
			onAccepted: {
				sfxPathValue = selectedFile.toString()
			}
		}
	}
}
