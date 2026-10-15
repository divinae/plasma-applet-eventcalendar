import QtQuick
import org.kde.kirigami as Kirigami

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

	// Black or white text, whichever reads better on the event color.
	function textColorFor(bg) {
		var c = Qt.color(bg)
		var luminance = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
		return luminance > 0.6 ? "#202124" : "#ffffff"
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
				radius: 2
				color: barColor
				border.width: 1
				border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.25)

				Text {
					anchors.fill: parent
					anchors.leftMargin: 2
					anchors.rightMargin: 1
					verticalAlignment: Text.AlignVCenter
					text: eventBar.eventItem ? eventBar.eventItem.summary : ""
					color: eventTitlesBadge.textColorFor(eventBar.barColor)
					font: eventTitlesBadge.titleFont
					elide: Text.ElideRight
					wrapMode: Text.NoWrap
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
