import QtQuick
import org.kde.kirigami as Kirigami

import "lib/ColorUtil.js" as ColorUtil

// A part of the popup in its own rounded card (Settings > Views > Style = "Islands"): the card
// color, a 1 px border and a faint shadow behind the content, the content inset by padding. Flat
// style: nothing drawn and no padding, so the content keeps its place.
// The content is the card's first child, sized to the card minus the padding; the card's implicit
// size follows the content's.
// joinTop / joinBottom: a slice of a card made of several items one below the other (the Tasks
// tab's rows): that edge is left open, the next slice continues the card.
Item {
	id: card

	default property alias content: contentArea.data
	readonly property Item contentChild: contentArea.children.length ? contentArea.children[0] : null

	property bool shown: appletConfig.islands
	property real padding: shown ? appletConfig.cardPadding : 0
	property real leftPadding: padding
	property real rightPadding: padding
	property real topPadding: padding
	property real bottomPadding: padding

	property bool joinTop: false
	property bool joinBottom: false
	property color borderColor: appletConfig.cardBorderColor
	// Laid over the card color (eg: a drop target's highlight).
	property color tint: "transparent"
	property real radius: appletConfig.cardRadius

	implicitWidth: (contentChild ? contentChild.implicitWidth : 0) + leftPadding + rightPadding
	implicitHeight: (contentChild ? contentChild.implicitHeight : 0) + topPadding + bottomPadding

	// The shadow's reach: the frame below is that much larger, except at an open (joined) edge.
	readonly property real shadowSize: 6
	Item {
		id: frame
		visible: card.shown
		z: -1
		x: -card.shadowSize
		y: card.joinTop ? 0 : -card.shadowSize
		width: card.width + card.shadowSize * 2
		height: card.height + (card.joinTop ? 0 : card.shadowSize) + (card.joinBottom ? 0 : card.shadowSize)
		clip: card.joinTop || card.joinBottom
		// An open edge: the rectangle goes on past it (corners, border and shadow cut off).
		readonly property real overshoot: card.radius + card.shadowSize + 2

		Kirigami.ShadowedRectangle {
			x: card.shadowSize
			y: card.joinTop ? -frame.overshoot : card.shadowSize
			width: card.width
			height: card.height + (card.joinTop ? frame.overshoot : 0) + (card.joinBottom ? frame.overshoot : 0)
			radius: card.radius
			color: card.tint.a > 0 ? Qt.tint(appletConfig.cardColor, card.tint) : appletConfig.cardColor
			border.width: 1
			border.color: card.borderColor
			shadow.size: card.shadowSize
			shadow.color: ColorUtil.setAlpha(Kirigami.Theme.textColor, 0.08)
			shadow.yOffset: 1
		}
	}

	Item {
		id: contentArea
		x: card.leftPadding
		y: card.topPadding
		width: Math.max(0, card.width - card.leftPadding - card.rightPadding)
		height: Math.max(0, card.height - card.topPadding - card.bottomPadding)
		// The content fills the area.
		onChildrenChanged: {
			for (var i = 0; i < children.length; i++) {
				children[i].width = Qt.binding(function() { return contentArea.width })
				children[i].height = Qt.binding(function() { return contentArea.height })
			}
		}
	}
}
