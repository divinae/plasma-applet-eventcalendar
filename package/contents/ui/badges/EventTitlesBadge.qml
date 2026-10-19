import QtQuick
import org.kde.kirigami as Kirigami

import ".."

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

			// Click opens the event, right click its menu, press and drag moves it to another day
			// (Ctrl: a copy).
			EventBar {
				readonly property Item calendarView: eventTitlesBadge.calendarView
				eventItem: {
					var _ = eventTitlesBadge.eventCount // Re-evaluate when the day's events change.
					return eventTitlesBadge.eventAt(index)
				}
				detailsModel: typeof eventModel !== "undefined" ? eventModel : null
				width: parent.width
				height: eventTitlesBadge.rowHeight
				dragSource: !!calendarView && calendarView.isDragSource(eventItem)
				dragCopy: !!calendarView && !!calendarView.eventDrag && calendarView.eventDrag.copy
				dragPending: !!calendarView && !!calendarView.eventDrag && calendarView.eventDrag.pending
				draggable: !!calendarView && calendarView.canDragEvent(eventItem)
				dragMapTo: calendarView
				onDragStarted: function(from, at, copy) {
					calendarView.eventDragBegin(eventItem, from, copy)
					calendarView.eventDragMove(at, copy)
				}
				onDragMoved: function(at, copy) { calendarView.eventDragMove(at, copy) }
				onDropped: function(copy) { calendarView.eventDragDrop(copy) }
				onDragCanceled: calendarView.eventDragCancel()
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
