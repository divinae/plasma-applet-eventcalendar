import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami

import "Tasks.js" as Tasks
import "TaskPending.js" as TaskPending

// A task's done check before its title: an empty circle, or a circle with a tick once done, in the
// task's text color; with a priority in its color (like TickTick: high red, medium orange, low
// blue). A click marks it done / not done (eventModel.toggleTask) and is only that: it doesn't open
// the task or start a drag of it. The check shows the new state at once (pending) and goes back
// when saving fails; toggled(done) tells (eg: for an undo offer). The state being saved is kept
// in TaskPending.js, not here: a check made again meanwhile (rows rebuilt) shows it too.
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
	property int pending: TaskPending.get(TaskPending.key(eventItem, subtaskId))
	readonly property bool done: pending >= 0 ? pending === 1 : subtaskId ? subtaskDone : Tasks.isDone(eventItem)
	readonly property bool canToggle: !!eventItem && eventItem.canEdit !== false
	// The task (or item) changed: as it is, unless a save of it still runs.
	function syncPending() {
		pending = TaskPending.get(TaskPending.key(eventItem, subtaskId))
	}
	onEventItemChanged: syncPending()
	onSubtaskIdChanged: syncPending()
	onSubtaskDoneChanged: syncPending()

	signal toggled(bool done)

	// 'high', 'medium', 'low' or 'none' (Tasks.priorityKey); none for a checklist item.
	readonly property string priority: subtaskId ? 'none' : Tasks.priorityKey(eventItem)
	readonly property color priorityColor: Tasks.priorityColor(priority) || color
	readonly property bool hasPriority: priority !== 'none'
	// Marked in progress (the widget's own mark, Tasks.isInProgress): half filled.
	readonly property bool inProgress: !subtaskId && !done && Tasks.isInProgress(eventItem, plasmoid.configuration.tasksInProgress)
	// The callbacks of a save may come after the row is gone.
	property var alive: ({ value: true })
	// A save of this task (or item) failed, maybe started by an earlier check of it: as it is.
	property var failedListener: null
	Component.onCompleted: {
		var check = taskCheck
		var alive = taskCheck.alive
		// As it was before: this check (made again meanwhile) may show a copy taken after the click.
		failedListener = function(key, wasDone) {
			if (alive.value && key === TaskPending.key(check.eventItem, check.subtaskId)) {
				check.pending = wasDone ? 1 : 0
			}
		}
		TaskPending.listen(failedListener)
	}
	Component.onDestruction: {
		alive.value = false
		TaskPending.unlisten(failedListener)
	}

	implicitWidth: size
	implicitHeight: size

	activeFocusOnTab: canToggle
	Accessible.role: Accessible.CheckBox
	Accessible.checkable: true
	Accessible.checked: done
	Accessible.name: done ? i18n("Mark as not done") : i18n("Mark as done")
	Accessible.description: inProgress ? i18nc("tasks filter", "In progress") : ""
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
		var wasDone = done
		var next = !wasDone
		var store = TaskPending // The callback may run once this check is gone (and its imports)
		var key = store.key(item, subtaskId)
		var token = store.start(key, next)
		pending = next ? 1 : 0
		// A checklist item: on the loaded task right away, so a quick second tick (its save is
		// made from the task's checklist) doesn't undo this one.
		var subtask = null
		if (subtaskId && Array.isArray(item.subtasks)) {
			subtask = item.subtasks.filter(function(s) { return s && s.id === subtaskId })[0] || null
		}
		var before = subtask ? !!subtask.done : false
		if (subtask) {
			subtask.done = next
		}
		var saved = function(err) {
			if (err && subtask && !!subtask.done === next) {
				subtask.done = before
			}
			store.finish(key, token, !!err, wasDone) // Failed: back to what it was (every check of it)
		}
		if (subtaskId) {
			eventModel.toggleSubtask(item, subtaskId, next, saved)
		} else {
			if (next && appletConfig.animations) {
				// Done: saved now, but the check pops and the title is struck through here first;
				// the task views move it (to Completed) a moment later (EventModel.holdTaskMoves).
				popAnimation.restart()
				eventModel.holdTaskMoves(350)
			}
			eventModel.toggleTask(item, next, saved)
		}
		toggled(next)
	}
	// The check when a task is marked done: up a little and back.
	SequentialAnimation {
		id: popAnimation
		NumberAnimation { target: taskCheck; property: "scale"; to: 1.3; duration: appletConfig.shortDuration * 0.6; easing.type: Easing.OutQuad }
		NumberAnimation { target: taskCheck; property: "scale"; to: 1; duration: appletConfig.shortDuration; easing.type: Easing.OutBack }
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

	// In progress: the lower half filled, inside the border.
	Item {
		visible: taskCheck.inProgress
		readonly property real inset: circle.border.width + 1
		x: circle.x + inset
		y: circle.y + circle.height / 2
		width: circle.width - inset * 2
		height: circle.height / 2 - inset
		clip: true
		Rectangle {
			y: -(circle.height / 2 - parent.inset)
			width: parent.width
			height: width
			radius: taskCheck.square ? 1.5 : width / 2
			// Islands: the accent when it has no priority (the neutral border is too faint to fill with).
			color: taskCheck.square ? (taskCheck.hasPriority ? taskCheck.priorityColor : Kirigami.Theme.highlightColor) : taskCheck.circleColor
		}
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
