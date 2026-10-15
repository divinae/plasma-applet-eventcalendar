import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore

import "../Shared.js" as Shared

// Google Calendar (Android) style: event titles as colored bars below the day number.
Item {
	id: eventTitlesBadge

	readonly property int topOffset: dayStyle.eventTitlesHeaderHeight
	readonly property int rowSpacing: 1
	// Theme fonts are set in points (pixelSize is -1), so size from the font itself.
	readonly property font titleFont: Kirigami.Theme.defaultFont
	FontMetrics {
		id: titleFontMetrics
		font: eventTitlesBadge.titleFont
	}
	readonly property int rowHeight: Math.ceil(titleFontMetrics.height) + 4
	readonly property int availableHeight: height - topOffset - rowSpacing
	readonly property int maxRows: Math.max(0, Math.floor((availableHeight + rowSpacing) / (rowHeight + rowSpacing)))
	readonly property int eventCount: modelEventsCount
	// When not everything fits, the last row becomes "+N". With room for a single row, show the first event.
	readonly property int visibleEventCount: eventCount <= maxRows ? eventCount : (maxRows <= 1 ? maxRows : maxRows - 1)
	readonly property int hiddenEventCount: eventCount - visibleEventCount

	function eventAt(i) {
		return modelEvents && i < modelEvents.count ? modelEvents.get(i) : null
	}

	Column {
		x: 1
		y: eventTitlesBadge.topOffset
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
				readonly property color barColor: eventItem && eventItem.backgroundColor ? eventItem.backgroundColor : Kirigami.Theme.highlightColor
				width: parent.width
				height: eventTitlesBadge.rowHeight
				radius: Math.min(7, height / 2)
				color: barColor
				border.width: 1
				border.color: appletConfig.eventBorderColor

				Text {
					anchors.fill: parent
					anchors.leftMargin: 4
					anchors.rightMargin: 1
					verticalAlignment: Text.AlignVCenter
					text: eventBar.eventItem ? eventBar.eventItem.summary : ""
					color: Shared.contrastTextColor(eventBar.barColor)
					font.family: eventTitlesBadge.titleFont.family
					font.pointSize: eventTitlesBadge.titleFont.pointSize
					// Event in progress
					font.bold: !!eventBar.eventItem && !(eventBar.eventItem.start && eventBar.eventItem.start.date)
						&& eventBar.eventItem.startDateTime <= timeModel.currentTime && timeModel.currentTime < eventBar.eventItem.endDateTime
					elide: Text.ElideRight
					wrapMode: Text.NoWrap
				}

				MouseArea {
					anchors.fill: parent
					cursorShape: Qt.PointingHandCursor
					onClicked: popup.activateEvent(eventBar.eventItem)
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
			visible: eventTitlesBadge.hiddenEventCount > 0
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
