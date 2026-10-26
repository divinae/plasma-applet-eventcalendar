import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore

import "Shared.js" as Shared

// An event as a bar or block in the month and week views: filled and outlined in the event color
// (EventStyle: outlined, striped or struck through by the user's answer), with its title. Click
// opens the event, right click its menu, press and drag moves it (Ctrl: a copy): the view handles
// the drag signals. Children added by the view (eg: a longer title) go on top.
Rectangle {
	id: eventBar

	property var eventItem: null
	readonly property EventStyle eventStyle: EventStyle {
		eventItem: eventBar.eventItem
	}
	// The EventModel, for the tooltip's details.
	property var detailsModel: typeof eventModel !== "undefined" ? eventModel : null

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
	property font titleFont: appletConfig.eventFont
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

	opacity: (dragSource && !dragCopy ? (dragPending ? 0 : 0.35) : dimmed ? appletConfig.pastOpacity : 1) * eventStyle.doneOpacity
	radius: cornerRadius
	topLeftRadius: !cuttable ? undefined : cutLeft || cutTop ? 0 : cornerRadius
	topRightRadius: !cuttable ? undefined : cutRight || cutTop ? 0 : cornerRadius
	bottomLeftRadius: !cuttable ? undefined : cutLeft || cutBottom ? 0 : cornerRadius
	bottomRightRadius: !cuttable ? undefined : cutRight || cutBottom ? 0 : cornerRadius
	color: eventStyle.fillColor
	border.width: 1
	border.color: showBar ? "transparent" : eventStyle.outlineColor // ColorBarFill draws it

	// "Bar" event look: the bar in the event color along the start side (not when the event continues
	// from before what's shown).
	readonly property bool showBar: eventStyle.showBar && !cutLeft
	ColorBarFill {
		visible: eventBar.showBar
		barColor: eventBar.eventStyle.barColor
		outlined: eventBar.eventStyle.outlined
		fillColor: eventBar.eventStyle.fillColor
		borderColor: eventBar.eventStyle.outlineColor
		topLeftRadius: eventBar.cuttable && eventBar.cutTop ? 0 : eventBar.cornerRadius
		bottomLeftRadius: eventBar.cuttable && eventBar.cutBottom ? 0 : eventBar.cornerRadius
		topRightRadius: eventBar.cuttable && (eventBar.cutRight || eventBar.cutTop) ? 0 : eventBar.cornerRadius
		bottomRightRadius: eventBar.cuttable && (eventBar.cutRight || eventBar.cutBottom) ? 0 : eventBar.cornerRadius
	}

	StripeFill {
		visible: eventBar.eventStyle.striped
		anchors.fill: parent
		anchors.margins: 1
		anchors.leftMargin: eventBar.showBar ? 5 : 1
		radius: eventBar.stripeRadius
		stripeColor: eventBar.eventStyle.stripeColor
	}

	// Invitation not answered yet: a small question mark before the title (Shared.isAwaitingAnswer),
	// once per event (not again on a bar continuing from the previous week row) and only where the
	// title keeps some room. An even size, like EventIndicators.
	readonly property int needsActionIconSize: 2 * Math.floor(Math.min(Kirigami.Units.iconSizes.small, height - 4) / 2)
	readonly property bool showNeedsAction: showTitle && !cutLeft && Shared.isAwaitingAnswer(eventStyle.response)
		&& width >= needsActionIconSize * 3 + 12
	Kirigami.Icon {
		id: needsActionIcon
		visible: eventBar.showNeedsAction
		x: eventBar.showBar ? 8 : 4
		anchors.verticalCenter: parent.verticalCenter
		width: eventBar.needsActionIconSize
		height: width
		roundToIconSize: false
		source: Shared.EVENT_INDICATOR_ICONS.needsAction
		isMask: true
		color: eventBar.eventStyle.textColor
	}

	// Tasks: the done check before the title, with the same room rule as the question mark.
	readonly property bool showTaskCheck: showTitle && !cutLeft && eventStyle.isTask
		&& width >= needsActionIconSize * 3 + 12

	Text {
		visible: eventBar.showTitle
		anchors.fill: parent
		anchors.leftMargin: (eventBar.showBar ? 9 : 4) + (eventBar.showNeedsAction ? needsActionIcon.width + 2 : 0)
			+ (eventBar.showTaskCheck ? taskCheck.width + 2 : 0)
		anchors.rightMargin: 1
		verticalAlignment: Text.AlignVCenter
		text: eventBar.showTitle && eventBar.eventItem ? eventBar.eventItem.summary : ""
		textFormat: Text.PlainText // User text: never parsed as HTML
		color: eventBar.eventStyle.textColor
		font.strikeout: eventBar.eventStyle.struckThrough
		font.family: eventBar.titleFont.family
		font.pointSize: eventBar.titleFont.pointSize
		font.bold: eventBar.inProgress // Event in progress
		elide: Text.ElideRight
		wrapMode: Text.NoWrap
	}

	DragMouseArea {
		id: dragArea
		anchors.fill: parent
		eventItem: eventBar.eventItem
		onDragStarted: function(from, at, copy) { eventBar.dragStarted(from, at, copy) }
		onDragMoved: function(at, copy) { eventBar.dragMoved(at, copy) }
		onDropped: function(copy) { eventBar.dropped(copy) }
		onDragCanceled: eventBar.dragCanceled()
	}

	// Above the drag area: its click toggles the task, it doesn't open it or start a drag.
	TaskCheck {
		id: taskCheck
		visible: eventBar.showTaskCheck
		x: eventBar.showBar ? 8 : 3
		anchors.verticalCenter: parent.verticalCenter
		size: eventBar.needsActionIconSize
		eventItem: eventBar.eventItem
		color: eventBar.eventStyle.textColor
	}

	// Title and details always set: ToolTipArea's containsMouse turns false once the tooltip opens,
	// so texts bound to it emptied the open tooltip (a second, title-only or empty one).
	PlasmaCore.ToolTipArea {
		anchors.fill: parent
		mainText: eventBar.eventItem ? eventBar.eventItem.summary : ""
		subText: eventBar.detailsModel ? eventBar.detailsModel.eventDetailsText(eventBar.eventItem) : ""
		textFormat: Text.PlainText
	}
}
