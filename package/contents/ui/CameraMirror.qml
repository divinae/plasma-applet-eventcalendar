import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import QtMultimedia
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "CameraPrefs.js" as CameraPrefs

// The camera check's preview (CameraCheckView.qml, loaded by URL only with Qt Multimedia, see
// MultimediaProbe.qml): the camera as a mirror. Nothing is recorded; the camera is on only while
// running (the card shown in the open popup), and off as soon as it closes.
ColumnLayout {
	id: mirror

	property bool running: false
	readonly property bool mirrored: plasmoid.configuration.cameraMirrored !== false
	spacing: Kirigami.Units.smallSpacing

	MediaDevices { id: mediaDevices }
	readonly property var cameras: mediaDevices.videoInputs
	property int cameraIndex: CameraPrefs.pickIndex(cameras, plasmoid.configuration.cameraDevice)
	property string errorText: ""
	readonly property string cameraState: CameraPrefs.cameraState(cameras.length, camera.active, errorText)

	CaptureSession {
		camera: Camera {
			id: camera
			cameraDevice: mirror.cameraIndex >= 0 ? mirror.cameras[mirror.cameraIndex] : mediaDevices.defaultVideoInput
			active: mirror.running && mirror.cameraIndex >= 0 && !mirror.errorText
			onErrorOccurred: function(error, errorString) {
				mirror.errorText = errorString || i18n("The camera can't be used")
			}
			onCameraDeviceChanged: mirror.errorText = ""
		}
		videoOutput: videoOutput
	}

	// The picture, 16:9 with rounded corners.
	Item {
		Layout.fillWidth: true
		Layout.preferredHeight: Math.round(width * 9 / 16)

		Rectangle {
			anchors.fill: parent
			radius: Kirigami.Units.cornerRadius * 2
			color: Qt.rgba(0, 0, 0, 0.85)
		}
		VideoOutput {
			id: videoOutput
			anchors.fill: parent
			fillMode: VideoOutput.PreserveAspectCrop
			visible: mirror.cameraState === 'live'
			transform: Scale {
				origin.x: videoOutput.width / 2
				xScale: mirror.mirrored ? -1 : 1
			}
			layer.enabled: true
			layer.effect: MultiEffect {
				maskEnabled: true
				maskSource: cornerMask
				maskThresholdMin: 0.5
				maskSpreadAtMin: 1.0
			}
		}
		Rectangle {
			id: cornerMask
			anchors.fill: parent
			radius: Kirigami.Units.cornerRadius * 2
			visible: false
			layer.enabled: true
		}

		// No picture: why.
		ColumnLayout {
			anchors.centerIn: parent
			width: parent.width - Kirigami.Units.gridUnit * 2
			visible: mirror.cameraState !== 'live'
			spacing: Kirigami.Units.smallSpacing
			Kirigami.Icon {
				Layout.alignment: Qt.AlignHCenter
				implicitWidth: Kirigami.Units.iconSizes.large
				implicitHeight: implicitWidth
				source: mirror.cameraState === 'starting' ? "camera-web" : "camera-off"
				color: "white"
				isMask: true
				opacity: 0.8
			}
			PlasmaComponents3.Label {
				Layout.fillWidth: true
				horizontalAlignment: Text.AlignHCenter
				wrapMode: Text.Wrap
				color: "white"
				opacity: 0.85
				text: mirror.cameraState === 'none' ? i18n("No camera found")
					: mirror.cameraState === 'error' ? i18n("The camera can't be used. Another app may be using it.")
					: i18n("Starting the camera…")
			}
			PlasmaComponents3.Button {
				Layout.alignment: Qt.AlignHCenter
				visible: mirror.cameraState === 'error'
				icon.name: "view-refresh"
				text: i18n("Try Again")
				onClicked: mirror.errorText = ""
			}
		}
	}

	RowLayout {
		Layout.fillWidth: true
		spacing: Kirigami.Units.smallSpacing
		Kirigami.Icon {
			implicitWidth: Kirigami.Units.iconSizes.small
			implicitHeight: implicitWidth
			source: "camera-web"
		}
		PlasmaComponents3.ComboBox {
			Layout.fillWidth: true
			enabled: mirror.cameras.length > 1
			model: mirror.cameras
			textRole: "description"
			currentIndex: mirror.cameraIndex
			displayText: mirror.cameras.length ? currentText : i18n("No camera")
			onActivated: function(index) {
				mirror.cameraIndex = index
				plasmoid.configuration.cameraDevice = mirror.cameras[index].description
			}
		}
		PlasmaComponents3.ToolButton {
			icon.name: "object-flip-horizontal"
			checkable: true
			checked: mirror.mirrored
			onToggled: plasmoid.configuration.cameraMirrored = checked
			PlasmaComponents3.ToolTip.text: i18n("Mirror the picture")
			PlasmaComponents3.ToolTip.visible: hovered
			PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
		}
	}
}
