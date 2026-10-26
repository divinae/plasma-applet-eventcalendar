import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "Tasks.js" as Tasks

// A task as a list row (Tasks view, Day view), like a to-do app rather than an event tile: its done
// check in the list's color, the title in the theme's text color on one line, and at the right end
// of that line its list (Tasks view by date) and when it's due (a chip, red when overdue); a second
// line only for the first line of its notes. Click opens it, right click the shared event menu;
// the check marks it done / not done. Done ones are dimmed and struck through. Hovered (or with the
// keyboard focus): buttons for due today / tomorrow, edit and delete, in place of the list and chip.
// With draggable, press and drag past the start drag distance drags it (dragStarted, dragMoved,
// dropped, dragCanceled; points in scene coordinates); the click that ends a drag isn't a click.
LinkRect {
	id: taskRow

	property var eventItem: null
	// Today, 'YYYY-MM-DD': for "Today", "Tomorrow" and "Overdue".
	property string today: Tasks.dayString(new Date())
	// Tighter, no notes, the due date only when overdue (Day view, Agenda).
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
	// The hover background also while it has the keyboard focus.
	color: clickable && (hovered || focusInside) ? backgroundHoverColor : backgroundColor
	// Room around the text: comfortable to read and click, one line per task.
	readonly property real verticalPadding: compact ? Kirigami.Units.smallSpacing + 1 : Kirigami.Units.smallSpacing + 2
	// The left and right room inside the row (its hover background is the full width).
	readonly property real sideMargin: compact ? Kirigami.Units.smallSpacing * 2 : Kirigami.Units.largeSpacing
	// Secondary text: dimmed, still clear on the popup's translucent background.
	readonly property real dimOpacity: 0.8
	implicitWidth: contents.implicitWidth + sideMargin * 2
	implicitHeight: contents.implicitHeight + verticalPadding * 2

	// The islands style (like TickTick): a square check, when it's due as accent-colored text (a
	// repeat icon below it), and the list's color as a thin stripe along the left edge (by date: in
	// place of the list's name, which is in the tooltip).
	property bool cardStyle: appletConfig.islands
	readonly property bool repeats: !!eventItem && (!!eventItem.recurringEventId || !!eventItem.repeatFlag)
	readonly property string dueTextShort: due.kind === 'overdue' ? dueDateText : dueText
	readonly property bool showDueText: cardStyle && !!dueTextShort && (compact ? overdue : true)
	readonly property bool showStripe: cardStyle && (compact || !!showList)

	// The list (by date) and when it's due, at the right end of the title's line.
	readonly property bool showListName: !cardStyle && !compact && !!showList
	readonly property bool showDueChip: !cardStyle && (compact ? overdue : showChip)
	readonly property bool showInfo: showListName || showDueChip || showDueText || (cardStyle && repeats && !compact)

	Rectangle {
		visible: taskRow.showStripe
		x: 0
		y: taskRow.compact ? 3 : 0
		width: 3
		height: parent.height - y * 2
		radius: taskRow.compact ? 1.5 : 0
		color: appletConfig.eventBarColor(taskRow.eventStyle.color)
		opacity: taskRow.eventStyle.doneOpacity
	}
	PlasmaComponents3.ToolTip.text: cardStyle && showList ? (showList.name || "") : ""
	PlasmaComponents3.ToolTip.visible: cardStyle && !!showList && !!showList.name && rowHover.hovered && !dragging
	PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay

	RowLayout {
		id: contents
		anchors.left: parent.left
		anchors.right: parent.right
		anchors.verticalCenter: parent.verticalCenter
		anchors.leftMargin: taskRow.sideMargin
		anchors.rightMargin: taskRow.sideMargin
		spacing: Kirigami.Units.largeSpacing

		TaskCheck {
			id: taskCheck
			Layout.alignment: Qt.AlignTop
			Layout.topMargin: Math.max(0, (titleLabel.implicitHeight - height) / 2)
			size: 2 * Math.round(Math.min(Kirigami.Units.iconSizes.small * 1.1, titleLabel.implicitHeight) / 2)
			eventItem: taskRow.eventItem
			color: taskRow.listColor
			square: taskRow.cardStyle
			overdue: taskRow.overdue
			opacity: taskRow.eventStyle.doneOpacity
		}

		ColumnLayout {
			Layout.fillWidth: true
			Layout.minimumWidth: 0
			Layout.alignment: Qt.AlignTop
			spacing: 1
			opacity: taskRow.eventStyle.doneOpacity

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
				maximumLineCount: 1
				wrapMode: Text.NoWrap
			}
			// The first line of the notes.
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
		}

		// Its list (by date) and the due chip, on the title's line. The hover buttons show in
		// their place.
		RowLayout {
			visible: taskRow.showInfo && !taskRow.showActions
			Layout.alignment: Qt.AlignTop
			// Islands: as tall as the date and the repeat icon below it.
			Layout.preferredHeight: taskRow.cardStyle ? -1 : titleLabel.implicitHeight
			spacing: Kirigami.Units.smallSpacing * 2
			opacity: taskRow.eventStyle.doneOpacity
			// A Row (not a layout): exactly as wide as the dot and the name.
			Row {
				visible: taskRow.showListName
				Layout.alignment: Qt.AlignVCenter
				spacing: Kirigami.Units.smallSpacing
				Rectangle {
					anchors.verticalCenter: parent.verticalCenter
					width: Math.round(Kirigami.Units.gridUnit * 0.45)
					height: width
					radius: width / 2
					color: taskRow.listColor
				}
				PlasmaComponents3.Label {
					width: Math.min(implicitWidth, Kirigami.Units.gridUnit * 6)
					text: taskRow.showList ? taskRow.showList.name || "" : ""
					textFormat: Text.PlainText // User text (list name)
					color: Kirigami.Theme.textColor
					opacity: taskRow.dimOpacity
					font: taskRow.detailFont
					elide: Text.ElideRight
				}
			}
			TaskDueChip {
				visible: taskRow.showDueChip
				Layout.alignment: Qt.AlignVCenter
				text: taskRow.chipText
				kind: taskRow.overdue ? 'overdue' : taskRow.due.kind
				font: taskRow.detailFont
			}
			// Islands: when it's due as text, a repeat icon below it.
			Column {
				visible: taskRow.cardStyle
				Layout.alignment: Qt.AlignTop
				spacing: 0
				PlasmaComponents3.Label {
					anchors.right: parent.right
					visible: taskRow.showDueText
					text: taskRow.dueTextShort
					textFormat: Text.PlainText
					font: taskRow.detailFont
					color: taskRow.overdue ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.linkColor
				}
				Kirigami.Icon {
					anchors.right: parent.right
					visible: taskRow.repeats && !taskRow.compact
					width: Kirigami.Units.iconSizes.small * 0.75
					height: width
					source: "media-playlist-repeat"
					color: Kirigami.Theme.textColor
					isMask: true
					opacity: 0.6
				}
			}
		}

		// The hover buttons, centered on the title's line: they take no height.
		Item {
			visible: taskRow.showActions
			Layout.alignment: Qt.AlignTop
			implicitWidth: actions.implicitWidth
			implicitHeight: titleLabel.implicitHeight
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
