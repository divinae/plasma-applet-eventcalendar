import QtQuick
import QtQuick.Window

// One full-screen meeting alert, a plain window: made once per screen (a window covers only its
// own display), and only while an alert is up. The variant that stays on every virtual desktop and
// above panels is MeetingAlertLayer.qml (layer-shell, optional). Both as in the Fokus plasmoid's
// break overlay.
Window {
	id: alertWindow

	property var eventItem: null
	property var meetingLink: null
	// Where it belongs, in virtual desktop coordinates; the output itself comes from the screen
	// property the creator binds (geometry set before the first show doesn't move it off the
	// primary screen).
	property rect screenGeometry

	signal joinRequested()
	signal snoozeRequested()
	signal closeRequested()

	function showOnItsScreen() {
		alertWindow.x = screenGeometry.x
		alertWindow.y = screenGeometry.y
		alertWindow.width = screenGeometry.width
		alertWindow.height = screenGeometry.height
		alertWindow.showFullScreen()
		alertWindow.raise()
		alertWindow.requestActivate()
	}
	Component.onCompleted: showOnItsScreen()

	flags: Qt.WindowStaysOnTopHint | Qt.FramelessWindowHint
	color: "transparent"
	title: i18n("Meeting")

	MeetingAlertContent {
		anchors.fill: parent
		eventItem: alertWindow.eventItem
		meetingLink: alertWindow.meetingLink
		onJoinRequested: alertWindow.joinRequested()
		onSnoozeRequested: alertWindow.snoozeRequested()
		onCloseRequested: alertWindow.closeRequested()
	}
}
