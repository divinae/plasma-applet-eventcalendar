import QtQuick

// "Bar" event look (EventStyle.showBar): a bar in the event's full color on the start side, cut from
// the event's rounded shape so it runs flush along the left edge and follows the rounded corners,
// and the fill right of it. Put it first in the event's item, whose own fill and border should match
// (fillColor, borderColor) as they show at the right corners.
// Bar and fill don't overlap: a faded event (past events, dimmed days) gets the opacity on each part
// and shows no patch where one would show through the other, without a layer of its own.
Item {
	id: colorBarFill

	property color barColor
	property color fillColor
	property color borderColor
	property real barWidth: 5
	// Not yet answered: the shape outlined in the bar color around a fill that may be transparent.
	property bool outlined: false
	// The event item's corner radii.
	property real topLeftRadius: 0
	property real bottomLeftRadius: 0
	property real topRightRadius: 0
	property real bottomRightRadius: 0

	anchors.fill: parent

	// The bar: the left slice of the whole rounded shape.
	Item {
		width: Math.min(parent.width, colorBarFill.barWidth)
		height: parent.height
		clip: true
		Rectangle {
			width: colorBarFill.width
			height: colorBarFill.height
			color: colorBarFill.barColor
			topLeftRadius: colorBarFill.topLeftRadius
			bottomLeftRadius: colorBarFill.bottomLeftRadius
			topRightRadius: colorBarFill.topRightRadius
			bottomRightRadius: colorBarFill.bottomRightRadius
		}
	}

	Rectangle {
		visible: !colorBarFill.outlined
		anchors.fill: parent
		anchors.leftMargin: colorBarFill.barWidth
		color: colorBarFill.fillColor
		border.width: 1
		border.color: colorBarFill.borderColor
		topRightRadius: colorBarFill.topRightRadius
		bottomRightRadius: colorBarFill.bottomRightRadius
	}

	// Outlined (the inside may be transparent): the rest of the whole shape, outlined in the bar color.
	Item {
		visible: colorBarFill.outlined
		x: colorBarFill.barWidth
		width: Math.max(0, parent.width - colorBarFill.barWidth)
		height: parent.height
		clip: true
		Rectangle {
			x: -colorBarFill.barWidth
			width: colorBarFill.width
			height: colorBarFill.height
			color: colorBarFill.fillColor
			border.width: 1
			border.color: colorBarFill.barColor
			topLeftRadius: colorBarFill.topLeftRadius
			bottomLeftRadius: colorBarFill.bottomLeftRadius
			topRightRadius: colorBarFill.topRightRadius
			bottomRightRadius: colorBarFill.bottomRightRadius
		}
	}
}
