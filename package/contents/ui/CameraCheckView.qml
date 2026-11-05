import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

// Camera check (like Hand Mirror): how you look and whether you're heard, before a meeting. The
// camera as a mirror (CameraMirror.qml, with Qt Multimedia), the microphone's level and the
// microphone and speaker to use (MicMeter.qml, with plasma-pa), and Join when there's a meeting.
// Both are loaded by URL, after their probes (main.qml): a missing module only hides its part.
// Nothing is recorded; the camera and the level run only while running.
Item {
	id: cameraCheck

	property var meetingLink: null
	property bool running: false
	signal closeRequested()
	signal joinRequested()

	// The title, and Join when there's a meeting; its window (CameraCheckWindow.qml) closes it.
	implicitHeight: header.implicitHeight + Kirigami.Units.smallSpacing * 2 + 1
		+ body.implicitHeight + Kirigami.Units.largeSpacing * 2
	Keys.onEscapePressed: closeRequested()
	Component.onCompleted: forceActiveFocus()

	ColumnLayout {
		anchors.fill: parent
		spacing: 0

		CardHeader {
			id: header
			cancelVisible: false
			title: i18n("Camera Check")
			Layout.fillWidth: true
			Layout.margins: Kirigami.Units.smallSpacing
			actionVisible: !!cameraCheck.meetingLink
			actionText: cameraCheck.meetingLink ? i18nc("%1 = Google Meet, Zoom, ...", "Join %1", cameraCheck.meetingLink.label) : ""
			actionIcon: "call-start"
			onActionClicked: cameraCheck.joinRequested()
		}

		Kirigami.Separator {
			Layout.fillWidth: true
		}

		ColumnLayout {
			id: body
			Layout.fillWidth: true
			Layout.margins: Kirigami.Units.largeSpacing
			spacing: Kirigami.Units.largeSpacing

			Loader {
				Layout.fillWidth: true
				source: root.cameraCheckAvailable ? "CameraMirror.qml" : ""
				onLoaded: item.running = Qt.binding(function() { return cameraCheck.running })
			}
			Loader {
				Layout.fillWidth: true
				source: root.moduleAvailable("PlasmaPaProbe.qml") ? "MicMeter.qml" : ""
				onLoaded: item.running = Qt.binding(function() { return cameraCheck.running })
			}
			PlasmaComponents3.Label {
				Layout.fillWidth: true
				wrapMode: Text.Wrap
				font: Kirigami.Theme.smallFont
				opacity: 0.6
				text: i18n("Nothing is recorded. The camera and the microphone are used only while this is open.")
			}
		}
	}
}
