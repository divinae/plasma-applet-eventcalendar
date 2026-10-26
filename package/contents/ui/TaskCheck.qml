import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami

import "Tasks.js" as Tasks

// A task's done check before its title: an empty circle, or a circle with a tick once done, in the
// task's text color. A click marks it done / not done (eventModel.toggleTask) and is only that: it
// doesn't open the task or start a drag of it.
Item {
	id: taskCheck

	property var eventItem: null
	property color color: Kirigami.Theme.textColor
	property int size: Kirigami.Units.iconSizes.small
	readonly property bool done: Tasks.isDone(eventItem)
	readonly property bool canToggle: !!eventItem && eventItem.canEdit !== false

	implicitWidth: size
	implicitHeight: size

	activeFocusOnTab: canToggle
	Accessible.role: Accessible.CheckBox
	Accessible.checkable: true
	Accessible.checked: done
	Accessible.name: done ? i18n("Mark as not done") : i18n("Mark as done")
	Accessible.onToggleAction: toggle()
	Accessible.onPressAction: toggle()
	Keys.onSpacePressed: toggle()

	function toggle() {
		if (!canToggle || typeof eventModel === "undefined" || !eventModel) {
			return
		}
		// Month and agenda delegates hand over ListModel copies: the original task when loaded.
		var item = eventItem
		if (item.calendarId && item.id && eventModel.eventsByCalendar && eventModel.eventsByCalendar[item.calendarId]) {
			item = eventModel.getEvent(item.calendarId, item.id) || item
		}
		if (typeof eventModel.toggleTask === "function") {
			eventModel.toggleTask(item, !done)
		} else {
			eventModel.setEventProperties(item.calendarId, item.id, Tasks.toggleBody(!done))
		}
	}

	Rectangle {
		id: circle
		anchors.centerIn: parent
		width: Math.round(taskCheck.size * 0.85)
		height: width
		radius: width / 2
		color: mouseArea.containsMouse && taskCheck.canToggle
			? Qt.rgba(taskCheck.color.r, taskCheck.color.g, taskCheck.color.b, 0.2) : "transparent"
		border.width: Math.max(1, Math.round(taskCheck.size / 12))
		border.color: taskCheck.visualFocus ? Kirigami.Theme.focusColor : taskCheck.color
	}

	Shape {
		visible: taskCheck.done
		anchors.fill: circle
		preferredRendererType: Shape.CurveRenderer
		ShapePath {
			strokeColor: taskCheck.color
			strokeWidth: Math.max(1.5, taskCheck.size / 9)
			fillColor: "transparent"
			capStyle: ShapePath.RoundCap
			joinStyle: ShapePath.RoundJoin
			startX: circle.width * 0.28
			startY: circle.height * 0.52
			PathLine { x: circle.width * 0.44; y: circle.height * 0.68 }
			PathLine { x: circle.width * 0.73; y: circle.height * 0.34 }
		}
	}

	MouseArea {
		id: mouseArea
		// A bit larger than the circle: easier to hit in thin bars.
		anchors.fill: parent
		anchors.margins: -2
		enabled: taskCheck.canToggle
		hoverEnabled: true
		preventStealing: true // Not the start of a drag of the bar under it
		acceptedButtons: Qt.LeftButton
		cursorShape: Qt.PointingHandCursor
		onClicked: function(mouse) {
			mouse.accepted = true
			taskCheck.toggle()
		}
	}
}
