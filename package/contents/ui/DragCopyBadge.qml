import QtQuick
import org.kde.kirigami as Kirigami

// "+" in the corner of a drag preview while Ctrl is held: the drop makes a copy.
Rectangle {
	id: copyBadge
	property int size: Kirigami.Units.iconSizes.small
	width: size
	height: size
	radius: size / 2
	color: Kirigami.Theme.highlightColor
	border.width: 1
	border.color: Kirigami.Theme.backgroundColor
	Kirigami.Icon {
		anchors.fill: parent
		anchors.margins: 2
		source: "list-add-symbolic"
		fallback: "list-add"
		color: Kirigami.Theme.highlightedTextColor
		isMask: true
	}
}
