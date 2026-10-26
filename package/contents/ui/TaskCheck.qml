import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami

import "Tasks.js" as Tasks

// A task's done check before its title: an empty circle, or a circle with a tick once done, in the
// task's text color; with a priority in its color (like TickTick: high red, medium orange, low
// blue). A click marks it done / not done (eventModel.toggleTask) and is only that: it doesn't open
// the task or start a drag of it. The check shows the new state at once (pending) and goes back
// when saving fails; toggled(done) tells (eg: for an undo offer).
// subtaskId: a TickTick checklist item of eventItem instead (eventModel.toggleSubtask), checked
// while subtaskDone.
Item {
	id: taskCheck

	property var eventItem: null
	property color color: Kirigami.Theme.textColor
	property int size: Kirigami.Units.iconSizes.small
	property string subtaskId: ""
	property bool subtaskDone: false
	// -1: as the task is; 0 / 1: unchecked / checked here, while (or once) it's saved.
	property int pending: -1
	readonly property bool done: pending >= 0 ? pending === 1 : subtaskId ? subtaskDone : Tasks.isDone(eventItem)
	readonly property bool canToggle: !!eventItem && eventItem.canEdit !== false
	onEventItemChanged: pending = -1
	onSubtaskDoneChanged: pending = -1

	signal toggled(bool done)

	// 'high', 'medium', 'low' or 'none' (Tasks.priorityKey); none for a checklist item.
	readonly property string priority: subtaskId ? 'none' : Tasks.priorityKey(eventItem)
	readonly property color priorityColor: priority === 'high' ? "#e03b30"
		: priority === 'medium' ? "#f0a020"
		: priority === 'low' ? "#4c7cf6"
		: color
	readonly property bool hasPriority: priority !== 'none'
	// The callbacks of a save may come after the row is gone.
	property var alive: ({ value: true })
	Component.onDestruction: alive.value = false

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
		var next = !done
		var check = taskCheck
		var alive = taskCheck.alive
		pending = next ? 1 : 0
		var saved = function(err) {
			if (err && alive.value) {
				check.pending = -1 // Back to what it is
			}
		}
		if (subtaskId) {
			eventModel.toggleSubtask(item, subtaskId, next, saved)
		} else {
			eventModel.toggleTask(item, next, saved)
		}
		toggled(next)
	}

	// The islands style's look (like TickTick): a rounded square with a neutral border (red when
	// overdue), filled in the accent color with a light tick once done.
	property bool square: false
	property bool overdue: false
	// With a priority: its color (overdue or not, the date says it); else neutral, red when overdue.
	readonly property color squareBorderColor: done ? Kirigami.Theme.highlightColor
		: hasPriority ? priorityColor
		: overdue ? Kirigami.Theme.negativeTextColor
		: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.45)
	readonly property color circleColor: hasPriority ? priorityColor : color
	readonly property color hoverColor: square ? squareBorderColor : circleColor

	Rectangle {
		id: circle
		anchors.centerIn: parent
		width: Math.round(taskCheck.size * (taskCheck.square ? 0.8 : 0.85))
		height: width
		radius: taskCheck.square ? 3 : width / 2
		// A priority: a light tint of its color inside.
		color: taskCheck.square && taskCheck.done ? Kirigami.Theme.highlightColor
			: mouseArea.containsMouse && taskCheck.canToggle
			? Qt.rgba(taskCheck.hoverColor.r, taskCheck.hoverColor.g, taskCheck.hoverColor.b, 0.2)
			: taskCheck.hasPriority && !taskCheck.done
			? Qt.rgba(taskCheck.priorityColor.r, taskCheck.priorityColor.g, taskCheck.priorityColor.b, 0.12)
			: "transparent"
		border.width: taskCheck.square ? (taskCheck.size < 14 ? 1.5 : 2) : Math.max(2, Math.round(taskCheck.size / 9))
		border.color: taskCheck.visualFocus ? Kirigami.Theme.focusColor : taskCheck.square ? taskCheck.squareBorderColor : taskCheck.circleColor
	}

	Shape {
		visible: taskCheck.done
		anchors.fill: circle
		preferredRendererType: Shape.CurveRenderer
		ShapePath {
			strokeColor: taskCheck.square ? Kirigami.Theme.highlightedTextColor : taskCheck.circleColor
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
