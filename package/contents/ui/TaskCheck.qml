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
		eventModel.toggleTask(item, !done)
	}

	// The islands style's look (like TickTick): a rounded square with a neutral border (red when
	// overdue), filled in the accent color with a light tick once done.
	property bool square: false
	property bool overdue: false
	readonly property color squareBorderColor: done ? Kirigami.Theme.highlightColor
		: overdue ? Kirigami.Theme.negativeTextColor
		: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.45)
	readonly property color hoverColor: square ? squareBorderColor : color

	Rectangle {
		id: circle
		anchors.centerIn: parent
		width: Math.round(taskCheck.size * (taskCheck.square ? 0.8 : 0.85))
		height: width
		radius: taskCheck.square ? 3 : width / 2
		color: taskCheck.square && taskCheck.done ? Kirigami.Theme.highlightColor
			: mouseArea.containsMouse && taskCheck.canToggle
			? Qt.rgba(taskCheck.hoverColor.r, taskCheck.hoverColor.g, taskCheck.hoverColor.b, 0.2) : "transparent"
		border.width: taskCheck.square ? 2 : Math.max(2, Math.round(taskCheck.size / 9))
		border.color: taskCheck.visualFocus ? Kirigami.Theme.focusColor : taskCheck.square ? taskCheck.squareBorderColor : taskCheck.color
	}

	Shape {
		visible: taskCheck.done
		anchors.fill: circle
		preferredRendererType: Shape.CurveRenderer
		ShapePath {
			strokeColor: taskCheck.square ? Kirigami.Theme.highlightedTextColor : taskCheck.color
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
