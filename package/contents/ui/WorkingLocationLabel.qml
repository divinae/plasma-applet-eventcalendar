import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "Shared.js" as Shared

// Where you work on a day (Google working location: "Home", "Office", an office or custom name),
// shown small in day headers instead of as an event. From eventModel.workingLocations.
Row {
	id: workingLocationLabel
	property var date: null
	property bool showIcon: true
	property color color: Kirigami.Theme.textColor
	// Only as wide as this; the text is elided.
	property real maxWidth: Infinity
	readonly property string text: {
		if (!date || typeof eventModel === "undefined" || !eventModel.workingLocations) {
			return ""
		}
		return eventModel.workingLocations[Shared.dayKey(date)] || ""
	}
	visible: !!text
	spacing: 2
	opacity: 0.75

	Kirigami.Icon {
		id: icon
		visible: workingLocationLabel.showIcon
		anchors.verticalCenter: parent.verticalCenter
		width: 2 * Math.round(label.implicitHeight * 0.8 / 2)
		height: width
		source: "mark-location"
		isMask: true
		color: workingLocationLabel.color
	}
	PlasmaComponents3.Label {
		id: label
		anchors.verticalCenter: parent.verticalCenter
		width: Math.min(implicitWidth, Math.max(0, workingLocationLabel.maxWidth - (icon.visible ? icon.width + workingLocationLabel.spacing : 0)))
		text: workingLocationLabel.text
		color: workingLocationLabel.color
		font: Kirigami.Theme.smallFont
		elide: Text.ElideRight
	}
	PlasmaComponents3.ToolTip.text: i18nc("%1 = Home, Office, ...", "Working location: %1", text)
	PlasmaComponents3.ToolTip.visible: hover.hovered && label.truncated
	HoverHandler {
		id: hover
	}
}
