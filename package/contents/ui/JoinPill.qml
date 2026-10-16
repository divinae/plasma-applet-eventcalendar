import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "lib/ColorUtil.js" as ColorUtil

// "Join" meeting button drawn on an event tile: a pill in the tile's text color, so it reads as
// part of the tile. meetingLink: from MeetingLink.find().
Rectangle {
	id: joinPill

	property var meetingLink: null
	property color textColor: Kirigami.Theme.textColor
	property real verticalPadding: Kirigami.Units.smallSpacing

	implicitWidth: joinRow.implicitWidth + Kirigami.Units.largeSpacing * 2
	implicitHeight: joinRow.implicitHeight + verticalPadding * 2
	radius: height / 2
	color: ColorUtil.setAlpha(textColor, joinMouse.pressed ? 0.35 : joinMouse.containsMouse ? 0.28 : 0.18)

	Row {
		id: joinRow
		anchors.centerIn: parent
		spacing: Kirigami.Units.smallSpacing
		Kirigami.Icon {
			anchors.verticalCenter: parent.verticalCenter
			width: Math.round(Kirigami.Units.iconSizes.small * 0.875)
			height: width
			source: "call-start-symbolic"
			// Symbolic icons follow the theme text color: use the tile's.
			Kirigami.Theme.inherit: false
			Kirigami.Theme.textColor: joinPill.textColor
			isMask: true
			color: joinPill.textColor
		}
		PlasmaComponents3.Label {
			anchors.verticalCenter: parent.verticalCenter
			text: i18n("Join")
			color: joinPill.textColor
			font: Kirigami.Theme.smallFont
		}
	}
	MouseArea {
		id: joinMouse
		anchors.fill: parent
		hoverEnabled: true
		cursorShape: Qt.PointingHandCursor
		onClicked: Qt.openUrlExternally(joinPill.meetingLink.url)
	}
	PlasmaComponents3.ToolTip.text: meetingLink ? i18nc("%1 = Google Meet, Zoom, ...", "Join %1", meetingLink.label) : ""
	PlasmaComponents3.ToolTip.visible: joinMouse.containsMouse
	Accessible.role: Accessible.Button
	Accessible.name: i18n("Join")
}
