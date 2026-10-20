import QtQuick

// "Bar" event look (EventStyle.showBar): the event's shape in its full color, covered by its fill
// except for a bar on the start side, so the bar runs flush along the left edge and follows the
// rounded corners. Put it first in the event's item (the item's own color and border are covered).
Item {
	id: colorBarFill

	property color barColor
	property color fillColor
	property color borderColor
	property real barWidth: 5
	// The event item's corner radii.
	property real topLeftRadius: 0
	property real bottomLeftRadius: 0
	property real topRightRadius: 0
	property real bottomRightRadius: 0

	anchors.fill: parent

	Rectangle {
		anchors.fill: parent
		color: colorBarFill.barColor
		topLeftRadius: colorBarFill.topLeftRadius
		bottomLeftRadius: colorBarFill.bottomLeftRadius
		topRightRadius: colorBarFill.topRightRadius
		bottomRightRadius: colorBarFill.bottomRightRadius
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
