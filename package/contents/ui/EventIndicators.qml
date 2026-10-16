import QtQuick
import org.kde.kirigami as Kirigami

import "MeetingLink.js" as MeetingLink
import "Shared.js" as Shared

// Small icons for what an event has set (place, join link, guests, repeats, notes), shown after
// its time. Views hide the ones they already show, eg: the location as text or a Join button.
Row {
	id: indicators
	property var eventItem: null
	property color color: Kirigami.Theme.textColor
	property int iconSize: Kirigami.Units.iconSizes.small
	property bool showLocation: true
	property bool showMeeting: true
	property bool showDescription: true
	property bool showRepeat: true
	// Only as many icons as fit in this width.
	property real maxWidth: Infinity

	readonly property var keys: Shared.eventIndicatorKeys(eventItem, showMeeting && !!MeetingLink.find(eventItem), {
		location: !showLocation,
		meeting: !showMeeting,
		description: !showDescription,
		repeat: !showRepeat,
	})
	readonly property var shownKeys: {
		var fit = Math.floor((maxWidth + spacing) / (iconSize + spacing))
		return keys.slice(0, Math.max(0, fit))
	}
	visible: shownKeys.length > 0
	spacing: Math.round(iconSize / 4)

	Repeater {
		model: indicators.shownKeys
		Kirigami.Icon {
			width: indicators.iconSize
			height: indicators.iconSize
			anchors.verticalCenter: parent ? parent.verticalCenter : undefined
			source: Shared.EVENT_INDICATOR_ICONS[modelData]
			isMask: true
			color: indicators.color
		}
	}
}
