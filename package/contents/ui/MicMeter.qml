import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.private.volume

import "CameraPrefs.js" as CameraPrefs

// The camera check's sound (CameraCheckView.qml, loaded by URL only with plasma-pa, see
// PlasmaPaProbe.qml): the microphone's level while running, a warning when it's muted, and the
// microphone and speaker to use (Plasma's defaults, set as the volume applet sets them).
ColumnLayout {
	id: meter

	property bool running: false
	readonly property var source: PreferredDevice.source
	readonly property bool muted: !!source && source.muted
	spacing: Kirigami.Units.smallSpacing

	VolumeMonitor {
		id: monitor
		target: meter.running ? meter.source : null
	}

	// Microphone: the level bar.
	RowLayout {
		Layout.fillWidth: true
		spacing: Kirigami.Units.smallSpacing
		Kirigami.Icon {
			implicitWidth: Kirigami.Units.iconSizes.small
			implicitHeight: implicitWidth
			source: meter.muted ? "microphone-sensitivity-muted" : "audio-input-microphone"
		}
		Rectangle {
			Layout.fillWidth: true
			implicitHeight: Math.round(Kirigami.Units.smallSpacing * 1.5)
			radius: height / 2
			color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
			Rectangle {
				height: parent.height
				radius: parent.radius
				width: parent.width * (meter.muted ? 0 : CameraPrefs.meterLevel(monitor.volume))
				color: Kirigami.Theme.positiveTextColor
				Behavior on width {
					NumberAnimation { duration: 80 }
				}
			}
		}
	}
	Kirigami.InlineMessage {
		Layout.fillWidth: true
		visible: meter.muted
		type: Kirigami.MessageType.Warning
		text: i18n("The microphone is muted.")
		actions: [
			Kirigami.Action {
				icon.name: "audio-input-microphone"
				text: i18n("Unmute")
				onTriggered: meter.source.muted = false
			}
		]
	}

	// The devices: [{ text, device, isDefault }] from a PulseAudio model.
	component DeviceCombo: PlasmaComponents3.ComboBox {
		id: combo
		property var pulseModel
		property bool microphones: false
		property var devices: []
		function refresh() {
			var list = []
			for (var i = 0; i < rows.count; i++) {
				var row = rows.objectAt(i)
				if (row && row.device && (!combo.microphones || CameraPrefs.isMicrophone(row.device.name))) {
					list.push({ text: row.label, device: row.device, isDefault: row.isDefault })
				}
			}
			devices = list
		}
		Instantiator {
			id: rows
			model: combo.pulseModel
			delegate: QtObject {
				readonly property string label: model.Description || ""
				readonly property var device: model.PulseObject
				readonly property bool isDefault: !!model.Default
				onIsDefaultChanged: Qt.callLater(combo.refresh)
				onLabelChanged: Qt.callLater(combo.refresh)
			}
			onObjectAdded: Qt.callLater(combo.refresh)
			onObjectRemoved: Qt.callLater(combo.refresh)
		}
		model: devices
		textRole: "text"
		enabled: devices.length > 1
		currentIndex: {
			for (var i = 0; i < devices.length; i++) {
				if (devices[i].isDefault) {
					return i
				}
			}
			return devices.length ? 0 : -1
		}
		onActivated: function(index) {
			devices[index].device.default = true
		}
	}

	RowLayout {
		Layout.fillWidth: true
		spacing: Kirigami.Units.smallSpacing
		Kirigami.Icon {
			implicitWidth: Kirigami.Units.iconSizes.small
			implicitHeight: implicitWidth
			source: "audio-input-microphone"
		}
		DeviceCombo {
			Layout.fillWidth: true
			pulseModel: SourceModel {}
			microphones: true
		}
	}
	RowLayout {
		Layout.fillWidth: true
		spacing: Kirigami.Units.smallSpacing
		Kirigami.Icon {
			implicitWidth: Kirigami.Units.iconSizes.small
			implicitHeight: implicitWidth
			source: "audio-speakers"
		}
		DeviceCombo {
			Layout.fillWidth: true
			pulseModel: SinkModel {}
		}
	}
}
