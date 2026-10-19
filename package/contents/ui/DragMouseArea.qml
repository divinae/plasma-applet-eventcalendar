import QtQuick

// An event's bar / block: click opens it, right click its menu, press and drag (past the start drag
// distance, left button) moves it (Ctrl: a copy). The click that ends a drag isn't a click.
// Points are given in mapTo's coordinates. Clicks open eventItem (left) or its menu (right) in the popup.
MouseArea {
	id: dragArea

	property var eventItem: null
	property bool draggable: false
	property Item mapTo: null
	// A drag started at `from`, the pointer now at `at`.
	signal dragStarted(point from, point at, bool copy)
	signal dragMoved(point at, bool copy)
	signal dropped(bool copy)
	signal dragCanceled()

	property point pressPoint
	property bool dragged: false

	cursorShape: dragged ? Qt.ClosedHandCursor : Qt.PointingHandCursor
	acceptedButtons: Qt.LeftButton | Qt.RightButton
	preventStealing: draggable // The view doesn't scroll while dragging

	onPressed: function(mouse) {
		dragged = false
		pressPoint = Qt.point(mouse.x, mouse.y)
	}
	onPositionChanged: function(mouse) {
		if (!draggable || !(pressedButtons & Qt.LeftButton)) {
			return
		}
		var copy = !!(mouse.modifiers & Qt.ControlModifier)
		var at = mapToItem(mapTo, mouse.x, mouse.y)
		if (dragged) {
			dragMoved(at, copy)
		} else if (Math.abs(mouse.x - pressPoint.x) + Math.abs(mouse.y - pressPoint.y) >= Qt.styleHints.startDragDistance) {
			dragged = true
			dragStarted(mapToItem(mapTo, pressPoint.x, pressPoint.y), at, copy)
		}
	}
	onReleased: function(mouse) {
		if (dragged) {
			dropped(!!(mouse.modifiers & Qt.ControlModifier))
		}
	}
	onCanceled: {
		if (dragged) {
			dragged = false
			dragCanceled()
		}
	}
	onClicked: function(mouse) {
		if (dragged) { // The end of a drag, not a click
			dragged = false
		} else {
			if (!eventItem) {
				return
			}
			if (mouse.button === Qt.RightButton) {
				popup.showEventMenu(eventItem, dragArea, mouse.x, mouse.y)
			} else {
				popup.activateEvent(eventItem)
			}
		}
	}
}
