import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import "ColorUtil.js" as ColorUtil
import "../code/GooglePalette.js" as GooglePalette

// Round color swatches to pick one from (Google Calendar's colors by default): the selected one
// has a checkmark. Used by the Google calendar edit dialog and the CalDAV / iCalendar color button.
GridLayout {
	id: grid
	property string selectedColor: ""
	property var colors: GooglePalette.calendarPalette // [{ name, color }]
	signal picked(string color)

	columns: 8
	rowSpacing: Kirigami.Units.smallSpacing
	columnSpacing: Kirigami.Units.smallSpacing

	Repeater {
		model: grid.colors
		delegate: AbstractButton {
			id: swatch
			readonly property bool selected: String(grid.selectedColor).toLowerCase() === modelData.color
			implicitWidth: Kirigami.Units.gridUnit * 1.75
			implicitHeight: implicitWidth
			// Google's color names aren't translated here; they're its own names.
			text: modelData.name
			checkable: true
			checked: selected
			onClicked: grid.picked(modelData.color)
			Accessible.name: modelData.name
			ToolTip.text: modelData.name
			ToolTip.visible: hovered
			ToolTip.delay: Kirigami.Units.toolTipDelay

			contentItem: Item {}
			background: Rectangle {
				radius: width / 2
				color: modelData.color
				border.width: swatch.selected ? 2 : (swatch.visualFocus || swatch.hovered ? 2 : 1)
				border.color: swatch.selected || swatch.visualFocus
					? Kirigami.Theme.textColor
					: ColorUtil.setAlpha(Kirigami.Theme.textColor, swatch.hovered ? 0.6 : 0.3)
				Kirigami.Icon {
					anchors.centerIn: parent
					width: Kirigami.Units.iconSizes.small
					height: width
					visible: swatch.selected
					source: "checkmark"
					color: GooglePalette.foregroundFor(modelData.color)
					isMask: true
				}
			}
		}
	}
}
