import QtQuick

// "Bar" event look (EventStyle.showBar): the event's shape in its full color, covered by its fill
// except for a bar on the start side, so the bar runs flush along the left edge and follows the
// rounded corners. Put it first in the event's item, whose own fill and border should match
// (fillColor, borderColor) as they show at the right corners.
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
	// One layer: faded (past events, dimmed days) as a whole. Otherwise each part gets the opacity on
	// its own and the bar layer shows through the fill as a wider patch.
	layer.enabled: visible

	// Only the left part (bar plus the rounding of the left corners): under the right corners it
	// would show through the fill's anti-aliased edge as a second outline.
	Rectangle {
		visible: !colorBarFill.outlined
		anchors.top: parent.top
		anchors.bottom: parent.bottom
		anchors.left: parent.left
		width: Math.min(parent.width, colorBarFill.barWidth + Math.max(colorBarFill.topLeftRadius, colorBarFill.bottomLeftRadius) + 1)
		color: colorBarFill.barColor
		topLeftRadius: colorBarFill.topLeftRadius
		bottomLeftRadius: colorBarFill.bottomLeftRadius
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

	// Outlined (the inside may be transparent): the whole shape outlined in the bar color, and the
	// bar cut from the same rounded shape, so it follows the left corners.
	Rectangle {
		visible: colorBarFill.outlined
		anchors.fill: parent
		color: colorBarFill.fillColor
		border.width: 1
		border.color: colorBarFill.barColor
		topLeftRadius: colorBarFill.topLeftRadius
		bottomLeftRadius: colorBarFill.bottomLeftRadius
		topRightRadius: colorBarFill.topRightRadius
		bottomRightRadius: colorBarFill.bottomRightRadius
	}
	Item {
		visible: colorBarFill.outlined
		width: colorBarFill.barWidth
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
}
