import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore

import ".."
import "../Shared.js" as Shared

// Google Calendar (Android) style: event titles as colored bars below the day number.
Item {
	id: eventTitlesBadge

	readonly property int topOffset: dayStyle.eventTitlesHeaderHeight
	readonly property int rowSpacing: 1
	// Theme fonts are set in points (pixelSize is -1), so size from the font itself.
	readonly property font titleFont: appletConfig.eventFont
	FontMetrics {
		id: titleFontMetrics
		font: eventTitlesBadge.titleFont
	}
	readonly property int rowHeight: Math.ceil(titleFontMetrics.height) + 4
	readonly property int availableHeight: height - topOffset - rowSpacing
	readonly property int maxRows: Math.max(0, Math.floor((availableHeight + rowSpacing) / (rowHeight + rowSpacing)))
	readonly property int eventCount: modelEventsCount
	// Multi-day bars (drawn by DaysCalendar) take the first spanRows rows; spanHiddenCount of them don't fit.
	readonly property int barRows: spanRows
	readonly property int hiddenBarCount: spanHiddenCount
	readonly property int freeRows: Math.max(0, maxRows - barRows)
	// When not everything fits, the last row becomes "+N". With room for a single row (and no bars),
	// show the first event.
	readonly property int visibleEventCount: {
		if (hiddenBarCount === 0 && eventCount <= freeRows) {
			return eventCount
		}
		if (barRows === 0 && hiddenBarCount === 0 && freeRows <= 1) {
			return freeRows
		}
		return Math.min(eventCount, Math.max(0, freeRows - 1))
	}
	readonly property int hiddenEventCount: eventCount - visibleEventCount + hiddenBarCount
	// "+N" only where there is a row left for it, not over the cell below.
	readonly property bool showHiddenCount: hiddenEventCount > 0 && visibleEventCount < freeRows

	// The month grid (DaysCalendar), for dragging events to other days.
	readonly property Item calendarView: dayStyle.calendarView

	function eventAt(i) {
		return modelEvents && i < modelEvents.count ? modelEvents.get(i) : null
	}

	Column {
		x: 1
		y: eventTitlesBadge.topOffset + eventTitlesBadge.barRows * (eventTitlesBadge.rowHeight + eventTitlesBadge.rowSpacing)
		width: eventTitlesBadge.width - 2
		spacing: eventTitlesBadge.rowSpacing
		clip: true

		Repeater {
			model: eventTitlesBadge.visibleEventCount

			Rectangle {
				id: eventBar
				readonly property var eventItem: {
					var _ = eventTitlesBadge.eventCount // Re-evaluate when the day's events change.
					return eventTitlesBadge.eventAt(index)
				}
				readonly property color barColor: appletConfig.eventColor(eventItem ? eventItem.backgroundColor : null)
				readonly property string response: Shared.myResponse(eventItem)
				width: parent.width
				height: eventTitlesBadge.rowHeight
				// Being dragged: faded (not for a copy); once dropped the ghost stands in for it.
				readonly property bool dragSource: !!eventTitlesBadge.calendarView && eventTitlesBadge.calendarView.isDragSource(eventItem)
				opacity: dragSource && !eventTitlesBadge.calendarView.eventDrag.copy ? (eventTitlesBadge.calendarView.eventDrag.pending ? 0 : 0.35) : 1
				radius: Math.min(7, height / 2)
				color: appletConfig.eventFillColor(barColor, response)
				border.width: 1
				border.color: appletConfig.eventOutlineColor(barColor, response)

				StripeFill {
					visible: eventBar.response === 'tentative'
					anchors.fill: parent
					anchors.margins: 1
					radius: Math.max(0, eventBar.radius - 1)
					stripeColor: eventBar.barColor
				}

				Text {
					anchors.fill: parent
					anchors.leftMargin: 4
					anchors.rightMargin: 1
					verticalAlignment: Text.AlignVCenter
					text: eventBar.eventItem ? eventBar.eventItem.summary : ""
					color: appletConfig.eventTextColor(eventBar.barColor, eventBar.response)
					font.strikeout: eventBar.response === 'declined'
					font.family: eventTitlesBadge.titleFont.family
					font.pointSize: eventTitlesBadge.titleFont.pointSize
					// Event in progress
					font.bold: !!eventBar.eventItem && !(eventBar.eventItem.start && eventBar.eventItem.start.date)
						&& eventBar.eventItem.startDateTime <= timeModel.currentTime && timeModel.currentTime < eventBar.eventItem.endDateTime
					elide: Text.ElideRight
					wrapMode: Text.NoWrap
				}

				// Click opens the event, right click its menu, press and drag moves it to another day
				// (Ctrl: a copy).
				MouseArea {
					anchors.fill: parent
					cursorShape: dragged ? Qt.ClosedHandCursor : Qt.PointingHandCursor
					acceptedButtons: Qt.LeftButton | Qt.RightButton
					readonly property Item calendarView: eventTitlesBadge.calendarView
					readonly property bool draggable: !!calendarView && calendarView.canDragEvent(eventBar.eventItem)
					preventStealing: draggable
					property point pressPoint
					property bool dragged: false
					onPressed: function(mouse) {
						dragged = false
						pressPoint = Qt.point(mouse.x, mouse.y)
					}
					onPositionChanged: function(mouse) {
						if (!draggable || !(pressedButtons & Qt.LeftButton)) {
							return
						}
						var copy = !!(mouse.modifiers & Qt.ControlModifier)
						if (dragged) {
							calendarView.eventDragMove(mapToItem(calendarView, mouse.x, mouse.y), copy)
						} else if (Math.abs(mouse.x - pressPoint.x) + Math.abs(mouse.y - pressPoint.y) >= Qt.styleHints.startDragDistance) {
							dragged = true
							calendarView.eventDragBegin(eventBar.eventItem, mapToItem(calendarView, pressPoint.x, pressPoint.y), copy)
							calendarView.eventDragMove(mapToItem(calendarView, mouse.x, mouse.y), copy)
						}
					}
					onReleased: function(mouse) {
						if (dragged) {
							calendarView.eventDragDrop(!!(mouse.modifiers & Qt.ControlModifier))
						}
					}
					onCanceled: {
						if (dragged) {
							dragged = false
							calendarView.eventDragCancel()
						}
					}
					onClicked: function(mouse) {
						if (dragged) { // The end of a drag, not a click
							dragged = false
						} else if (mouse.button === Qt.RightButton) {
							popup.showEventMenu(eventBar.eventItem, eventBar, mouse.x, mouse.y)
						} else {
							popup.activateEvent(eventBar.eventItem)
						}
					}
				}

				PlasmaCore.ToolTipArea {
					anchors.fill: parent
					mainText: eventBar.eventItem ? eventBar.eventItem.summary : ""
					subText: containsMouse ? eventModel.eventDetailsText(eventBar.eventItem) : ""
					textFormat: Text.PlainText
				}
			}
		}

		Text {
			visible: eventTitlesBadge.showHiddenCount
			width: parent.width
			height: eventTitlesBadge.rowHeight
			horizontalAlignment: Text.AlignHCenter
			verticalAlignment: Text.AlignVCenter
			text: i18nc("more events not shown in a month day cell", "+%1", eventTitlesBadge.hiddenEventCount)
			color: Kirigami.Theme.textColor
			opacity: 0.7
			font: eventTitlesBadge.titleFont
		}
	}
}
