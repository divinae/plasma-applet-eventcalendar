import QtQuick
import org.kde.kirigami as Kirigami

Item {
	id: dotsBadge
	property int dotSize: (height / 8) + dotBorderWidth*2
	property color dotColor: Kirigami.Theme.highlightColor // Fallback when an event has no color.
	property int dotBorderWidth: plasmoid.configuration.showOutlines ? 1 : 0
	property color dotBorderColor: Kirigami.Theme.backgroundColor

	// One dot per event (max 3), colored like the event / its calendar.
	function dotColorAt(i) {
		var eventItem = modelEvents && i < modelEvents.count ? modelEvents.get(i) : null
		return eventItem && eventItem.backgroundColor ? eventItem.backgroundColor : dotsBadge.dotColor
	}

	Row {
		anchors.horizontalCenter: dotsBadge.horizontalCenter
		anchors.bottom: dotsBadge.bottom
		anchors.margins: dotsBadge.height / 8
		spacing: Kirigami.Units.smallSpacing

		Repeater {
			model: Math.min(3, modelEventsCount)

			Rectangle {
				width: dotsBadge.dotSize
				height: dotsBadge.dotSize
				radius: width / 2
				color: {
					var _ = modelEventsCount // Re-evaluate when the day's events change.
					return dotsBadge.dotColorAt(index)
				}
				border.width: dotsBadge.dotBorderWidth
				border.color: dotsBadge.dotBorderColor
			}
		}
	}
}
