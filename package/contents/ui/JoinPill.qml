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

	// The height it may take (0: any): on a very short tile it gets slimmer, then drops the text and
	// shrinks the icon, never taller than that.
	property real maxHeight: 0
	readonly property real fullIconSize: Math.round(Kirigami.Units.iconSizes.small * 0.875)
	readonly property bool showLabel: maxHeight <= 0 || Math.ceil(joinLabel.implicitHeight) + 2 <= maxHeight
	readonly property real contentHeight: Math.ceil(joinRow.implicitHeight)
	// Even room around the icon and the text: above and below at least 3 px (slimmer, down to 1, only
	// to fit maxHeight), and on the sides 3 px plus a little for the round ends (not slimmer: the text
	// keeps clear of them).
	readonly property real fullPad: Math.max(3, verticalPadding)
	readonly property real vPad: maxHeight > 0
		? Math.max(1, Math.min(fullPad, Math.floor((maxHeight - contentHeight) / 2)))
		: fullPad
	readonly property real hPad: Math.round(fullPad + Kirigami.Units.smallSpacing)
	implicitWidth: Math.ceil(joinRow.implicitWidth) + hPad * 2
	implicitHeight: contentHeight + vPad * 2
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
			width: joinPill.maxHeight > 0 ? Math.max(8, Math.min(joinPill.fullIconSize, Math.floor(joinPill.maxHeight - 2))) : joinPill.fullIconSize
			height: width
			source: "call-start-symbolic"
			// Symbolic icons follow the theme text color: use the tile's.
			Kirigami.Theme.inherit: false
			Kirigami.Theme.textColor: joinPill.pillTextColor
			isMask: true
			color: joinPill.pillTextColor
		}
		PlasmaComponents3.Label {
			id: joinLabel
			visible: joinPill.showLabel
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
