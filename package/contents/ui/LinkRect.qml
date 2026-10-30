import QtQuick
import org.kde.plasma.core as PlasmaCore

import "lib"

Rectangle {
	id: linkRect
	width: implicitWidth
	height: implicitHeight
	implicitWidth: childrenRect.width
	implicitHeight: childrenRect.height
	property color backgroundColor: "transparent"
	property color backgroundHoverColor: appletConfig.agendaHoverBackground
	color: clickable && hovered ? backgroundHoverColor : backgroundColor
	property string tooltipMainText
	property string tooltipSubText
	property alias acceptedButtons: mouseArea.acceptedButtons
	// Not Item.enabled: that would also disable children, eg: an inline edit form.
	property bool clickable: true
	readonly property alias hovered: mouseArea.containsMouse
	// For press-and-drag on top of the clicks (TaskRow).
	readonly property alias linkMouseArea: mouseArea

	signal clicked(var mouse)
	signal leftClicked(var mouse)
	signal doubleClicked(var mouse)
	signal loadContextMenu(var contextMenu)
	
	PlasmaCore.ToolTipArea {
		id: tooltip
		anchors.fill: parent
		mainText: linkRect.tooltipMainText
		subText: linkRect.tooltipSubText

		MouseArea {
			id: mouseArea
			anchors.fill: parent
			hoverEnabled: true
			acceptedButtons: Qt.LeftButton | Qt.RightButton
			cursorShape: linkRect.clickable && containsMouse ? Qt.PointingHandCursor : Qt.ArrowCursor
			enabled: linkRect.clickable
			onClicked: function(mouse) {
				mouse.accepted = false
				linkRect.clicked(mouse)
				if (!mouse.accepted) {
					if (mouse.button == Qt.LeftButton) {
						linkRect.leftClicked(mouse)
					} else if (mouse.button == Qt.RightButton) {
						linkRect.contextMenu().show(mouse.x, mouse.y)
						mouse.accepted = true
					}
				}
			}
			onDoubleClicked: function(mouse) {
				linkRect.doubleClicked(mouse)
			}
		}
	}

	// Made on the first right click: a Menu for every row of a list costs a lot when the view opens.
	property var contextMenuObject: null
	function contextMenu() {
		if (!contextMenuObject) {
			contextMenuObject = contextMenuComponent.createObject(linkRect)
		}
		return contextMenuObject
	}
	Component {
		id: contextMenuComponent
		ContextMenu {
			onPopulate: function(menu) { linkRect.loadContextMenu(menu) }
		}
	}
}
