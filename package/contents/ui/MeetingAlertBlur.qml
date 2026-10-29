import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.private.kicker as Kicker

// The full-screen meeting alert with the desktop blurred behind it, as the Fokus plasmoid's break
// overlay: Kicker's DashboardWindow asks KWin for the blur (there's no QML API for it), and the
// translucent color it paints is what the blur shows through. Reached by URL only (KickerProbe).
Kicker.DashboardWindow {
	id: alertWindow

	property var eventItem: null
	property var meetingLink: null
	// Where it belongs, in virtual desktop coordinates: a DashboardWindow has no screen property, the
	// geometry set before the first show picks the output (also for its layer surface).
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

	// Frameless too (setting flags replaces DashboardWindow's own).
	flags: Qt.WindowStaysOnTopHint | Qt.FramelessWindowHint
	// Dark, translucent over the blur: the content's complementary background (a window's own
	// Kirigami.Theme may not follow a color set).
	backgroundColor: Qt.alpha(alertContent.Kirigami.Theme.backgroundColor, 0.72)

	// DashboardWindow takes Esc itself (keyEscapePressed) and passes the other keys to its
	// keyEventProxy: Return reaches the content.
	onKeyEscapePressed: alertWindow.closeRequested()
	keyEventProxy: alertContent

	MeetingAlertContent {
		id: alertContent
		anchors.fill: parent
		backgroundOpacity: 0
		eventItem: alertWindow.eventItem
		meetingLink: alertWindow.meetingLink
		onJoinRequested: alertWindow.joinRequested()
		onSnoozeRequested: alertWindow.snoozeRequested()
		onCloseRequested: alertWindow.closeRequested()
	}
}
