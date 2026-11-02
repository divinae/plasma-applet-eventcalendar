import QtQuick
import QtQuick.Window
import org.kde.kirigami as Kirigami

// The camera check (CameraCheckView.qml) in its own window, on top of the others: it stays open
// beside the meeting's window while the popup closes. main.qml makes one (openCameraCheck) and
// drops it when it's closed. The camera and the sound run while it's shown (not minimized).
Window {
	id: cameraWindow

	property var meetingLink: null
	signal joinRequested()

	flags: Qt.Window | Qt.WindowStaysOnTopHint
	transientParent: null // Its own window, not one tied to the panel
	title: i18n("Camera Check")
	color: Kirigami.Theme.backgroundColor
	// The picture is 16:9 by the width: the height follows it.
	width: Kirigami.Units.gridUnit * 26
	height: view.implicitHeight
	minimumWidth: Kirigami.Units.gridUnit * 18
	minimumHeight: view.implicitHeight
	maximumHeight: view.implicitHeight

	Kirigami.Theme.colorSet: Kirigami.Theme.Window
	Kirigami.Theme.inherit: false

	CameraCheckView {
		id: view
		anchors.fill: parent
		meetingLink: cameraWindow.meetingLink
		running: cameraWindow.visible && cameraWindow.visibility !== Window.Minimized
		onCloseRequested: cameraWindow.close()
		onJoinRequested: cameraWindow.joinRequested()
	}

	function bringUp() {
		show()
		raise()
		requestActivate()
	}
	Component.onCompleted: bringUp()
}
