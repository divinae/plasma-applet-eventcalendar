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
	// Not yet answered: the bar outlined in its color instead of filled.
	property bool hollow: false
	// The event item's corner radii.
	property real topLeftRadius: 0
	property real bottomLeftRadius: 0
	property real topRightRadius: 0
	property real bottomRightRadius: 0

	anchors.fill: parent

	// Only the left part (bar plus the rounding of the left corners): under the right corners it
	// would show through the fill's anti-aliased edge as a second outline.
	Rectangle {
		anchors.top: parent.top
		anchors.bottom: parent.bottom
		anchors.left: parent.left
		width: Math.min(parent.width, colorBarFill.barWidth + Math.max(colorBarFill.topLeftRadius, colorBarFill.bottomLeftRadius) + 1)
		color: colorBarFill.hollow ? colorBarFill.fillColor : colorBarFill.barColor
		border.width: colorBarFill.hollow ? 1 : 0
		border.color: colorBarFill.barColor
		topLeftRadius: colorBarFill.topLeftRadius
		bottomLeftRadius: colorBarFill.bottomLeftRadius
	}
	Rectangle {
		anchors.fill: parent
		anchors.leftMargin: colorBarFill.barWidth
		color: colorBarFill.fillColor
		border.width: 1
		border.color: colorBarFill.borderColor
		topRightRadius: colorBarFill.topRightRadius
		bottomRightRadius: colorBarFill.bottomRightRadius
	}
}
