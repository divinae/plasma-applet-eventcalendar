import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "Tasks.js" as Tasks

// A task as a list row (Tasks view, Day view), like a to-do app rather than an event tile: its done
// check in the list's color, the title in the theme's text color, when it's due (a chip, red when
// overdue), its list (Tasks view by date) and the first line of its notes. Click opens it, right
// click the shared event menu; the check marks it done / not done. Done ones are dimmed and struck
// through. Hovered (or with the keyboard focus): buttons for due today / tomorrow, edit and delete.
// With draggable, press and drag past the start drag distance drags it (dragStarted, dragMoved,
// dropped, dragCanceled; points in scene coordinates); the click that ends a drag isn't a click.
LinkRect {
	id: taskRow

	property var eventItem: null
	// Today, 'YYYY-MM-DD': for "Today", "Tomorrow" and "Overdue".
	property string today: Tasks.dayString(new Date())
	// One line: the due date after the title (only when overdue), no notes (Day view).
	property bool compact: false
	// The task's list ({ name, color }), shown before the due date (Tasks view by date), or null.
	property var showList: null
	// A due kind ('today', 'tomorrow') the row's section already says: no chip for it.
	property string sectionDueKind: ""
	// The hover buttons.
	property bool actionsEnabled: true
	property bool draggable: false

	signal dragStarted(point at)
	signal dragMoved(point at)
	signal dropped(point at)
	signal dragCanceled()

	readonly property EventStyle eventStyle: EventStyle {
		eventItem: taskRow.eventItem
	}
	// The list's color, dark enough (light theme) or light enough (dark theme) to read on the
	// popup's translucent background, like colored text.
	readonly property color listColor: appletConfig.eventColoredTextColor(eventStyle.color)
	readonly property bool overdue: due.kind === 'overdue' && !eventStyle.done
	readonly property var due: {
		var parts = today.split('-')
		return Tasks.dueInfo(eventItem, new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]), 12))
	}
	readonly property string dueDateText: {
		if (!due.day) {
			return ""
		}
		var parts = due.day.split('-')
		var date = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
		return Qt.formatDate(date, i18nc("short month+date format", "MMM d"))
	}
	readonly property string dueText: {
		switch (due.kind) {
			case 'today': return i18n("Today")
			case 'tomorrow': return i18n("Tomorrow")
			case 'overdue': return i18nc("%1 = short date", "Overdue · due %1", dueDateText)
			case 'date': return dueDateText
		}
		return ""
	}
	readonly property string chipText: due.kind === 'overdue' ? dueDateText : dueText
	readonly property bool showChip: !!chipText && due.kind !== sectionDueKind
	readonly property string notesLine: compact || !eventItem ? "" : Tasks.firstLine(eventItem.notes || eventItem.description || "")
	// The due date and notes: a bit smaller than the title, larger than the views' small font.
	readonly property font detailFont: appletConfig.scaledFont(appletConfig.eventFont, 0.9)
	readonly property string title: eventItem ? (eventItem.summary || eventItem.title || "") : ""
	readonly property bool canEdit: !!eventItem && eventItem.canEdit !== false

	activeFocusOnTab: true
	Accessible.role: Accessible.Button
	Accessible.name: title || i18n("Task")
	Accessible.description: [eventStyle.done ? i18n("Done") : i18n("Not done"), dueText].filter(function(t) { return !!t }).join(". ")
	Accessible.onPressAction: open()
	Keys.onReturnPressed: open()
	Keys.onEnterPressed: open()
	Keys.onSpacePressed: taskCheck.toggle()
	Keys.onDeletePressed: remove()
	function open() {
		popup.activateEvent(eventItem)
	}

	//--- Hover buttons
	function setDue(day) {
		if (!canEdit || typeof eventModel === "undefined" || !eventModel) {
			return
		}
		eventModel.setEventProperties(eventItem.calendarId, eventItem.id, Tasks.editBody({ dueDay: day }), {})
	}
	function edit() {
		if (canEdit) {
			popup.editEvent(eventItem)
		}
	}
	function remove() {
		if (canEdit) {
			popup.deleteWithUndo(eventItem, false)
		}
	}
	HoverHandler {
		id: rowHover
	}
	readonly property bool focusInside: activeFocus || taskCheck.activeFocus || todayButton.activeFocus
		|| tomorrowButton.activeFocus || editButton.activeFocus || deleteButton.activeFocus
	readonly property bool showActions: actionsEnabled && canEdit && !dragging
		&& (hovered || rowHover.hovered || focusInside)

	//--- Drag
	property bool dragging: false
	property bool dragEnded: false // The click that ends a drag isn't one
	property point pressPoint
	Binding {
		target: taskRow.linkMouseArea
		property: "preventStealing"
		value: taskRow.draggable // The view doesn't scroll while dragging
	}
	Connections {
		target: taskRow.linkMouseArea
		enabled: taskRow.draggable
		function onPressed(mouse) {
			taskRow.dragging = false
			taskRow.dragEnded = false
			taskRow.pressPoint = Qt.point(mouse.x, mouse.y)
		}
		function onPositionChanged(mouse) {
			var area = taskRow.linkMouseArea
			if (!(area.pressedButtons & Qt.LeftButton)) {
				return
			}
			var at = area.mapToItem(null, mouse.x, mouse.y)
			if (taskRow.dragging) {
				taskRow.dragMoved(at)
			} else if (Math.abs(mouse.x - taskRow.pressPoint.x) + Math.abs(mouse.y - taskRow.pressPoint.y) >= Qt.styleHints.startDragDistance) {
				taskRow.dragging = true
				taskRow.dragStarted(at)
			}
		}
		function onReleased(mouse) {
			if (taskRow.dragging) {
				taskRow.dragging = false
				taskRow.dragEnded = true
				taskRow.dropped(taskRow.linkMouseArea.mapToItem(null, mouse.x, mouse.y))
			}
		}
		function onCanceled() {
			if (taskRow.dragging) {
				taskRow.dragging = false
				taskRow.dragCanceled()
			}
		}
	}

	radius: 6
	backgroundColor: "transparent"
	backgroundHoverColor: appletConfig.agendaHoverBackground
	// Room around the text: a list to read and click, not packed rows.
	readonly property real verticalPadding: compact ? Kirigami.Units.smallSpacing + 1 : Kirigami.Units.smallSpacing * 2
	implicitWidth: contents.implicitWidth + Kirigami.Units.largeSpacing * 2
	implicitHeight: contents.implicitHeight + verticalPadding * 2

	RowLayout {
		id: contents
		anchors.left: parent.left
		anchors.right: parent.right
		anchors.verticalCenter: parent.verticalCenter
		anchors.leftMargin: compact ? Kirigami.Units.smallSpacing * 2 : Kirigami.Units.largeSpacing
		anchors.rightMargin: compact ? Kirigami.Units.smallSpacing * 2 : Kirigami.Units.largeSpacing
		spacing: Kirigami.Units.largeSpacing

		TaskCheck {
			id: taskCheck
			Layout.alignment: Qt.AlignTop
			Layout.topMargin: Math.max(0, (titleLabel.implicitHeight - height) / 2)
			size: 2 * Math.round(Math.min(Kirigami.Units.iconSizes.small * 1.1, titleLabel.implicitHeight) / 2)
			eventItem: taskRow.eventItem
			color: taskRow.listColor
			opacity: taskRow.eventStyle.doneOpacity
		}

		ColumnLayout {
			Layout.fillWidth: true
			Layout.minimumWidth: 0
			spacing: 2
			opacity: taskRow.eventStyle.doneOpacity

			RowLayout {
				Layout.fillWidth: true
				spacing: Kirigami.Units.smallSpacing
				PlasmaComponents3.Label {
					id: titleLabel
					Layout.fillWidth: true
					Layout.minimumWidth: 0
					text: taskRow.title
					textFormat: Text.PlainText // User text: never parsed as HTML
					color: Kirigami.Theme.textColor
					font.family: appletConfig.eventFont.family
					font.pointSize: appletConfig.eventFont.pointSize
					font.strikeout: taskRow.eventStyle.struckThrough
					elide: Text.ElideRight
					maximumLineCount: taskRow.compact ? 1 : 2
					wrapMode: taskRow.compact ? Text.NoWrap : Text.Wrap
				}
				// Compact: the date after the title when it's overdue (the rest are due on this day).
				TaskDueChip {
					visible: taskRow.compact && taskRow.overdue
					text: taskRow.dueDateText
					kind: 'overdue'
					font: taskRow.detailFont
				}
			}

			RowLayout {
				visible: !taskRow.compact && (!!taskRow.showList || taskRow.showChip || !!taskRow.notesLine)
				Layout.fillWidth: true
				spacing: Kirigami.Units.smallSpacing * 2
				// Its list (by date).
				// A Row (not a layout): exactly as wide as the dot and the name, so the chip follows it.
				Row {
					visible: !!taskRow.showList
					Layout.preferredWidth: implicitWidth
					spacing: Kirigami.Units.smallSpacing
					Rectangle {
						anchors.verticalCenter: parent.verticalCenter
						width: Math.round(Kirigami.Units.gridUnit * 0.45)
						height: width
						radius: width / 2
						color: taskRow.listColor
					}
					PlasmaComponents3.Label {
						width: Math.min(implicitWidth, Kirigami.Units.gridUnit * 7)
						text: taskRow.showList ? taskRow.showList.name || "" : ""
						textFormat: Text.PlainText // User text (list name)
						color: Kirigami.Theme.textColor
						opacity: 0.85
						font: taskRow.detailFont
						elide: Text.ElideRight
					}
				}
				TaskDueChip {
					visible: taskRow.showChip
					text: taskRow.chipText
					kind: taskRow.overdue ? 'overdue' : taskRow.due.kind
					font: taskRow.detailFont
				}
				PlasmaComponents3.Label {
					visible: !!text
					Layout.fillWidth: true
					Layout.minimumWidth: 0
					text: taskRow.notesLine
					textFormat: Text.PlainText // User text: never parsed as HTML
					color: Kirigami.Theme.textColor
					opacity: 0.75
					font: taskRow.detailFont
					elide: Text.ElideRight
					wrapMode: Text.NoWrap
					maximumLineCount: 1
				}
				Item {
					visible: !taskRow.notesLine
					Layout.fillWidth: true
				}
			}
		}

		// The hover buttons: room is only taken while they show, never height.
		Item {
			visible: taskRow.showActions
			Layout.fillHeight: true
			implicitWidth: actions.implicitWidth
			implicitHeight: 0
			Row {
				id: actions
				anchors.right: parent.right
				anchors.verticalCenter: parent.verticalCenter
				spacing: 0
				TaskRowButton {
					id: todayButton
					visible: !taskRow.eventStyle.done && taskRow.due.kind !== 'today'
					icon.name: "go-jump-today"
					text: i18n("Due today")
					onClicked: taskRow.setDue(taskRow.today)
				}
				TaskRowButton {
					id: tomorrowButton
					visible: !taskRow.eventStyle.done && taskRow.due.kind !== 'tomorrow'
					icon.name: "go-next"
					text: i18n("Due tomorrow")
					onClicked: taskRow.setDue(Tasks.addDays(taskRow.today, 1))
				}
				TaskRowButton {
					id: editButton
					icon.name: "document-edit"
					text: i18n("Edit")
					onClicked: taskRow.edit()
				}
				TaskRowButton {
					id: deleteButton
					icon.name: "edit-delete"
					text: i18n("Delete")
					onClicked: taskRow.remove()
				}
			}
		}
	}

	onLeftClicked: open()

	// Right click: the shared event menu (LinkRect's own menu is skipped once the click is accepted).
	// Not the end of a drag.
	onClicked: function(mouse) {
		if (dragEnded) {
			dragEnded = false
			mouse.accepted = true
			return
		}
		if (mouse.button === Qt.RightButton) {
			mouse.accepted = true
			popup.showEventMenu(eventItem, taskRow, mouse.x, mouse.y)
		}
	}
}
