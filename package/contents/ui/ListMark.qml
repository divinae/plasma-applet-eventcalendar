import QtQuick
import org.kde.plasma.components as PlasmaComponents3

// A task list's mark: the emoji its name starts with (list.icon, like TickTick), else a dot in its
// color. size: the dot's diameter; an emoji is drawn a bit larger, centered in the same place.
Item {
	id: mark

	property var list: null
	property real size: 8
	property color color: "transparent"
	readonly property string icon: list && list.icon ? String(list.icon) : ""

	implicitWidth: icon ? emoji.implicitWidth : size
	implicitHeight: icon ? emoji.implicitHeight : size

	PlasmaComponents3.Label {
		id: emoji
		visible: !!mark.icon
		anchors.centerIn: parent
		text: mark.icon
		textFormat: Text.PlainText
		font.pixelSize: Math.max(9, Math.round(mark.size * 1.4))
	}
	Rectangle {
		visible: !mark.icon
		anchors.centerIn: parent
		width: mark.size
		height: width
		radius: width / 2
		color: mark.color
	}
}
