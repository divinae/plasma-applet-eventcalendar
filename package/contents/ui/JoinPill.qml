import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "lib/ColorUtil.js" as ColorUtil
import "Shared.js" as Shared

// "Join" meeting button drawn on an event tile: a small pill in the popup's background and text
// colors with a thin border, so it stands out on any tile (tinted, striped, solid).
// meetingLink: from MeetingLink.find(). (textColor / baseColor: the tile's, kept for callers.)
Rectangle {
	id: joinPill

	property var meetingLink: null
	property color textColor: Kirigami.Theme.textColor
	property color baseColor: Kirigami.Theme.backgroundColor
	property real verticalPadding: Kirigami.Units.smallSpacing

	// Room around the icon and the text (at least a little above and below, also when slim).
	implicitWidth: joinRow.implicitWidth + Kirigami.Units.largeSpacing * 3
	implicitHeight: joinRow.implicitHeight + Math.max(2, verticalPadding) * 2
	radius: height / 2
	readonly property color pillTextColor: Kirigami.Theme.textColor
	color: Qt.tint(ColorUtil.setAlpha(Kirigami.Theme.backgroundColor, 1),
		ColorUtil.setAlpha(Kirigami.Theme.textColor, joinMouse.pressed ? 0.16 : joinMouse.containsMouse ? 0.08 : 0))
	border.width: 1
	border.color: ColorUtil.setAlpha(Kirigami.Theme.textColor, 0.25)

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
			Kirigami.Theme.textColor: joinPill.pillTextColor
			isMask: true
			color: joinPill.pillTextColor
		}
		PlasmaComponents3.Label {
			anchors.verticalCenter: parent.verticalCenter
			text: i18n("Join")
			color: joinPill.pillTextColor
			font: Kirigami.Theme.smallFont
		}
	}
	MouseArea {
		id: joinMouse
		anchors.fill: parent
		hoverEnabled: true
		cursorShape: Qt.PointingHandCursor
		onClicked: meetingOpener.open(joinPill.meetingLink.url)
	}
	PlasmaComponents3.ToolTip.text: meetingLink ? i18nc("%1 = Google Meet, Zoom, ...", "Join %1", meetingLink.label) : ""
	PlasmaComponents3.ToolTip.visible: joinMouse.containsMouse
	Accessible.role: Accessible.Button
	Accessible.name: i18n("Join")
}
