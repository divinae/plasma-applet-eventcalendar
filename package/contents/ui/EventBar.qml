import QtQuick
import org.kde.plasma.core as PlasmaCore

// An event as a bar or block in the month and week views: filled and outlined in the event color
// (EventStyle: outlined, striped or struck through by the user's answer), with its title. Click
// opens the event, right click its menu, press and drag moves it (Ctrl: a copy): the view handles
// the drag signals. Children added by the view (eg: a longer title) go on top.
Rectangle {
	id: bar

	property var eventItem: null
	readonly property EventStyle eventStyle: EventStyle {
		eventItem: bar.eventItem
	}
	// The EventModel, for the tooltip's details.
	property var detailsModel: null

	// Square corners where the event continues beyond what's shown. Views that cut corners set
	// cuttable: the corners are then set one by one (otherwise radius alone, drawn a bit differently).
	property bool cuttable: false
	property bool cutLeft: false
	property bool cutRight: false
	property bool cutTop: false
	property bool cutBottom: false
	property real maxRadius: 7
	readonly property real cornerRadius: Math.min(maxRadius, height / 2)
	property real stripeRadius: Math.max(0, cornerRadius - 1)

	// Being dragged: faded where it was, not for a copy; dropped (pending): hidden, the view's
	// preview stands in for it. Otherwise dimmed when the view shows it as past.
	property bool dragSource: false
	property bool dragCopy: false
	property bool dragPending: false
	property bool dimmed: false

	// The one-line title; off when the view lays out its own text.
	property bool showTitle: true
	readonly property bool inProgress: !!eventItem && !(eventItem.start && eventItem.start.date)
		&& typeof timeModel !== "undefined"
		&& eventItem.startDateTime <= timeModel.currentTime && timeModel.currentTime < eventItem.endDateTime

	property alias draggable: dragArea.draggable
	// Drag points are given in this item's coordinates.
	property alias dragMapTo: dragArea.mapTo
	signal dragStarted(point from, point at, bool copy)
	signal dragMoved(point at, bool copy)
	signal dropped(bool copy)
	signal dragCanceled()

	opacity: dragSource && !dragCopy ? (dragPending ? 0 : 0.35) : dimmed ? appletConfig.pastOpacity : 1
	radius: cornerRadius
	topLeftRadius: !cuttable ? undefined : cutLeft || cutTop ? 0 : cornerRadius
	topRightRadius: !cuttable ? undefined : cutRight || cutTop ? 0 : cornerRadius
	bottomLeftRadius: !cuttable ? undefined : cutLeft || cutBottom ? 0 : cornerRadius
	bottomRightRadius: !cuttable ? undefined : cutRight || cutBottom ? 0 : cornerRadius
	color: eventStyle.fillColor
	border.width: 1
	border.color: eventStyle.outlineColor

	StripeFill {
		visible: bar.eventStyle.striped
		anchors.fill: parent
		anchors.margins: 1
		radius: bar.stripeRadius
		stripeColor: bar.eventStyle.stripeColor
	}

	Text {
		visible: bar.showTitle
		anchors.fill: parent
		anchors.leftMargin: 4
		anchors.rightMargin: 1
		verticalAlignment: Text.AlignVCenter
		text: bar.showTitle && bar.eventItem ? bar.eventItem.summary : ""
		color: bar.eventStyle.textColor
		font.strikeout: bar.eventStyle.declined
		font.family: appletConfig.eventFont.family
		font.pointSize: appletConfig.eventFont.pointSize
		font.bold: bar.inProgress // Event in progress
		elide: Text.ElideRight
		wrapMode: Text.NoWrap
	}

	DragMouseArea {
		id: dragArea
		anchors.fill: parent
		onDragStarted: function(from, at, copy) { bar.dragStarted(from, at, copy) }
		onDragMoved: function(at, copy) { bar.dragMoved(at, copy) }
		onDropped: function(copy) { bar.dropped(copy) }
		onDragCanceled: bar.dragCanceled()
		onEventClicked: function(button, x, y) {
			if (button === Qt.RightButton) {
				popup.showEventMenu(bar.eventItem, bar, x, y)
			} else {
				popup.activateEvent(bar.eventItem)
			}
		}
	}

	PlasmaCore.ToolTipArea {
		anchors.fill: parent
		mainText: bar.eventItem ? bar.eventItem.summary : ""
		subText: containsMouse && bar.detailsModel ? bar.detailsModel.eventDetailsText(bar.eventItem) : ""
		textFormat: Text.PlainText
	}
}
