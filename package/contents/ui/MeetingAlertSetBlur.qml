import QtQml
import QtQuick

// One blurred alert per screen, without layer-shell (see MeetingAlertSetLayer.qml).
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
		delegate: MeetingAlertBlur {
			screenGeometry: Qt.rect(modelData.virtualX, modelData.virtualY, modelData.width, modelData.height)
			eventItem: alertSet.eventItem
			meetingLink: alertSet.meetingLink
			onJoinRequested: alertSet.joinRequested()
			onSnoozeRequested: alertSet.snoozeRequested()
			onCloseRequested: alertSet.closeRequested()
		}
	}
}
