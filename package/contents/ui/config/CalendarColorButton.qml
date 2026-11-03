import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import "../lib"
import "../lib/ColorUtil.js" as ColorUtil

// A calendar's color dot, clickable: a popup with the palette, Custom… (any color) and, when
// resetText is set, a way back to the calendar's own color (the server's). colorChosen("") is
// that reset.
AbstractButton {
	id: button
	property color shownColor: Kirigami.Theme.highlightColor
	property string resetText: ""
	signal colorChosen(string color)

	implicitWidth: Kirigami.Units.iconSizes.small
	implicitHeight: implicitWidth
	Accessible.name: i18n("Color")
	ToolTip.text: i18n("Color")
	ToolTip.visible: hovered && !popup.visible
	ToolTip.delay: Kirigami.Units.toolTipDelay
	onClicked: popup.open()

	contentItem: Item {}
	background: Rectangle {
		radius: width / 2
		color: button.shownColor
		border.width: button.hovered || button.visualFocus ? 2 : 0
		border.color: ColorUtil.setAlpha(Kirigami.Theme.textColor, 0.6)
	}

	function choose(color) {
		popup.close()
		button.colorChosen(color)
	}

	Popup {
		id: popup
		y: button.height + Kirigami.Units.smallSpacing
		margins: 0 // Kept inside the window (a row at the bottom: shown above it)
		padding: Kirigami.Units.largeSpacing
		// Built when opened: a settings page has one of these per calendar.
		contentItem: Loader {
			active: popup.visible
			sourceComponent: popupContent
		}
	}
	Component {
		id: popupContent
		ColumnLayout {
			spacing: Kirigami.Units.largeSpacing
			ColorSwatchGrid {
				selectedColor: String(button.shownColor)
				onPicked: function(color) { button.choose(color) }
			}
			RowLayout {
				Button {
					icon.name: "color-picker"
					text: i18n("Custom…")
					onClicked: {
						colorDialogLoader.active = true
						colorDialogLoader.item.selectedColor = button.shownColor
						colorDialogLoader.item.open()
						popup.close() // Last: it unloads this button
					}
				}
				Item { Layout.fillWidth: true }
				Button {
					visible: !!button.resetText
					icon.name: "edit-undo"
					text: button.resetText
					onClicked: button.choose("")
				}
			}
		}
	}

	Loader {
		id: colorDialogLoader
		active: false // On first use
		sourceComponent: ColorDialog {
			title: i18n("Calendar Color")
			onAccepted: button.colorChosen(String(selectedColor))
		}
	}
}
