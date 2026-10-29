import QtQml
import QtQuick

// One layer-shell alert per screen, in a file of its own: main.qml reaches it through a Loader
// source URL, never by type name (a type name is resolved when main.qml loads, and would fail the
// whole applet where org.kde.layershell is missing).
QtObject {
	id: alertSet

	property var eventItem: null
	property var meetingLink: null

	signal joinRequested()
	signal snoozeRequested()
	signal closeRequested()

	property Instantiator alerts: Instantiator {
		active: !!alertSet.eventItem
		model: Qt.application.screens
		delegate: MeetingAlertLayer {
			screen: modelData
			screenGeometry: Qt.rect(modelData.virtualX, modelData.virtualY, modelData.width, modelData.height)
			eventItem: alertSet.eventItem
			meetingLink: alertSet.meetingLink
			onJoinRequested: alertSet.joinRequested()
			onSnoozeRequested: alertSet.snoozeRequested()
			onCloseRequested: alertSet.closeRequested()
		}
	}
}
