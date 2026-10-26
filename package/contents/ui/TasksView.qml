import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "Tasks.js" as Tasks

// The Tasks tab, by date (tasksGroupBy 'date': Overdue, Today, Tomorrow, This week, Later, No
// date; Tasks.dateRows) or by list (every selected task list as a section, grouped by account when
// there are several; Tasks.taskRows), the done ones with "Show completed". "Add a task…" rows add
// without the editor: at the bottom of each list, or of the open tasks by date (undated, on a
// picked list). A task can be dragged onto a list (same account: moved) or onto Today, Tomorrow
// or No date (its due day changes).
Item {
	id: tasksView

	property var eventModel: null
	readonly property bool showCompleted: !!plasmoid.configuration.tasksShowCompleted
	readonly property bool byList: plasmoid.configuration.tasksGroupBy === 'list'
	readonly property string today: Tasks.dayString(timeModel.currentTime)
	readonly property int firstDayOfWeek: {
		var setting = plasmoid.configuration.firstDayOfWeek
		return setting >= 0 ? setting : Qt.locale().firstDayOfWeek % 7
	}

	property var rows: []
	property var lists: []
	property int openCount: 0

	// "Add a task…" text and focus by row key, across rebuilds (they make the rows again).
	property var addDrafts: ({})

	function rebuild() {
		if (!eventModel) {
			rows = []
			lists = []
			openCount = 0
			return
		}
		var newLists = eventModel.getSelectedTaskLists()
		var itemsByList = {}
		for (var i = 0; i < newLists.length; i++) {
			var calendar = eventModel.eventsByCalendar[newLists[i].id]
			itemsByList[newLists[i].id] = calendar && calendar.items ? calendar.items : []
		}
		var flick = scrollView.contentItem
		var y = flick ? flick.contentY : 0
		var newRows = byList ? Tasks.taskRows(newLists, itemsByList, showCompleted)
			: Tasks.dateRows(newLists, itemsByList, today, firstDayOfWeek, showCompleted)
		var count = 0
		for (var j = 0; j < newRows.length; j++) {
			if (newRows[j].type === 'task' && !newRows[j].done) {
				count++
			}
		}
		rememberAddFocus()
		openCount = count
		lists = newLists
		rows = newRows
		// Toggling a task rebuilds the rows: stay where the list was.
		if (flick) {
			flick.contentY = Math.max(0, Math.min(y, flick.contentHeight - flick.height))
		}
	}
	function deferredRebuild() {
		Qt.callLater(rebuild)
	}
	// Which "Add a task…" field has the focus, to give it back once the rows are made again.
	function rememberAddFocus() {
		var item = Window.activeFocusItem
		var key = ""
		while (item) {
			if (item.draftKey !== undefined && item.addDrafts !== undefined) {
				key = item.draftKey
				break
			}
			item = item.parent
		}
		if (key && !addDrafts[key]) {
			addDrafts[key] = { text: "" }
		}
		for (var k in addDrafts) {
			addDrafts[k].focused = k === key
		}
	}
	Component.onCompleted: rebuild()
	onShowCompletedChanged: rebuild()
	onByListChanged: rebuild()
	onTodayChanged: deferredRebuild()
	onFirstDayOfWeekChanged: deferredRebuild()
	onEventModelChanged: deferredRebuild()

	Connections {
		target: tasksView.eventModel
		function onCalendarFetched(calendarId, data) { tasksView.deferredRebuild() }
		function onAllDataFetched() { tasksView.deferredRebuild() }
		function onDataCleared() { tasksView.deferredRebuild() }
		function onEventAdded(calendarId, data) { tasksView.deferredRebuild() }
		function onEventRemoved(calendarId, eventId, data) { tasksView.deferredRebuild() }
		function onEventUpdated(calendarId, eventId, data) { tasksView.deferredRebuild() }
	}

	//--- A short note (eg: a drop that can't be done)
	property string notice: ""
	function showNotice(text) {
		notice = text
		noticeTimer.restart()
	}
	Timer {
		id: noticeTimer
		interval: 4000
		onTriggered: tasksView.notice = ""
	}

	//--- Drag a task onto a list or a date section
	property var dragRow: null // The dragged row's data
	property real dragWidth: 0
	property real dragGrabX: 0
	property real dragGrabY: 0
	property point dragAt
	property string dropKey: "" // The header the drop goes to
	property bool dropRefused: false
	property var dropAction: null // { kind: 'move', listId } | { kind: 'due', day }
	readonly property bool dragActive: !!dragRow

	function startDrag(row, rowItem, at) {
		dragRow = row
		dragWidth = rowItem.width
		var grab = rowItem.mapFromItem(null, at.x, at.y)
		dragGrabX = grab.x
		dragGrabY = grab.y
		moveDrag(at)
	}
	// The drop target under at (scene coordinates): a header, or a row of its section.
	function moveDrag(at) {
		dragAt = at
		var p = rowsColumn.mapFromItem(null, at.x, at.y)
		var loader = rowsColumn.childAt(Math.max(0, Math.min(p.x, rowsColumn.width - 1)), p.y)
		var target = loader ? loader.row : null
		var key = ""
		var refused = false
		var action = null
		if (target && dragRow) {
			if (byList && target.list) {
				var drop = Tasks.listDrop(dragRow.list.id, target.list.id)
				if (drop !== 'none') {
					key = 'list:' + target.list.id
					refused = drop === 'refuse'
					action = refused ? null : { kind: 'move', listId: target.list.id }
				}
			} else if (!byList && target.section) {
				var day = Tasks.sectionDueDay(target.section, today)
				if (day !== null && day !== Tasks.dueDay(dragRow.item)) {
					key = 'section:' + target.section
					action = { kind: 'due', day: day }
				}
			}
		}
		dropKey = key
		dropRefused = refused
		dropAction = action
	}
	function endDrag(drop) {
		var row = dragRow
		var action = dropAction
		var refused = dropRefused
		dragRow = null
		dropKey = ""
		dropRefused = false
		dropAction = null
		if (!drop || !row) {
			return
		}
		if (refused) {
			showNotice(i18n("Tasks can only move to a list of the same account"))
			return
		}
		if (!action || !eventModel) {
			return
		}
		var item = row.item
		if (action.kind === 'due') {
			eventModel.setEventProperties(row.list.id, item.id, Tasks.editBody({ dueDay: action.day }), {})
		} else if (action.kind === 'move') {
			var view = tasksView
			eventModel.moveEvent(row.list.id, item.id, action.listId, function(err) {
				if (err) {
					view.showNotice(i18n("Couldn't move the task"))
				}
				logic.update()
			})
		}
	}
	// Near the top or bottom while dragging: scroll.
	Timer {
		interval: 30
		repeat: true
		running: tasksView.dragActive
		onTriggered: {
			var flick = scrollView.contentItem
			if (!flick) {
				return
			}
			var y = scrollView.mapFromItem(null, tasksView.dragAt.x, tasksView.dragAt.y).y
			var edge = Kirigami.Units.gridUnit * 1.5
			var step = y < edge ? -(edge - y) / 2 : y > scrollView.height - edge ? (y - scrollView.height + edge) / 2 : 0
			if (step !== 0) {
				var max = Math.max(0, flick.contentHeight - flick.height)
				flick.contentY = Math.max(0, Math.min(max, flick.contentY + step))
				tasksView.moveDrag(tasksView.dragAt)
			}
		}
	}

	ColumnLayout {
		anchors.fill: parent
		anchors.margins: Kirigami.Units.smallSpacing
		spacing: Kirigami.Units.largeSpacing

		RowLayout {
			Layout.fillWidth: true
			Layout.leftMargin: Kirigami.Units.largeSpacing
			Layout.rightMargin: Kirigami.Units.largeSpacing
			spacing: Kirigami.Units.smallSpacing

			PlasmaComponents3.Label {
				Layout.fillWidth: true
				Layout.minimumWidth: 0
				text: tasksView.openCount > 0 ? i18np("%1 open task", "%1 open tasks", tasksView.openCount) : i18n("No open tasks")
				textFormat: Text.PlainText
				opacity: 0.85
				elide: Text.ElideRight
			}
			// By date / by list.
			Row {
				spacing: 0
				PlasmaComponents3.ToolButton {
					text: i18n("By date")
					checkable: true
					checked: !tasksView.byList
					onClicked: plasmoid.configuration.tasksGroupBy = 'date'
				}
				PlasmaComponents3.ToolButton {
					text: i18n("By list")
					checkable: true
					checked: tasksView.byList
					onClicked: plasmoid.configuration.tasksGroupBy = 'list'
				}
			}
			PlasmaComponents3.Switch {
				Layout.leftMargin: Kirigami.Units.smallSpacing
				text: i18n("Show completed")
				checked: tasksView.showCompleted
				onToggled: plasmoid.configuration.tasksShowCompleted = checked
			}
		}

		PlasmaComponents3.Label {
			visible: !!tasksView.notice
			Layout.fillWidth: true
			Layout.minimumWidth: 0
			Layout.leftMargin: Kirigami.Units.largeSpacing
			Layout.rightMargin: Kirigami.Units.largeSpacing
			text: tasksView.notice
			textFormat: Text.PlainText
			color: Kirigami.Theme.negativeTextColor
			elide: Text.ElideRight
		}

		PlasmaComponents3.ScrollView {
			id: scrollView
			Layout.fillWidth: true
			Layout.fillHeight: true
			contentWidth: availableWidth
			QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

			ColumnLayout {
				id: rowsColumn
				width: scrollView.availableWidth
				spacing: 0

				Repeater {
					model: tasksView.rows
					Loader {
						readonly property var row: modelData
						Layout.fillWidth: true
						sourceComponent: row.type === 'group' ? groupComponent
							: row.type === 'list' ? listComponent
							: row.type === 'section' ? sectionComponent
							: row.type === 'empty' ? emptyComponent
							: row.type === 'add' ? addComponent
							: taskComponent
					}
				}
				Item {
					implicitHeight: Kirigami.Units.smallSpacing
				}
			}
		}
	}

	// The dragged task, under the pointer.
	Loader {
		active: tasksView.dragActive
		x: tasksView.mapFromItem(null, tasksView.dragAt.x, tasksView.dragAt.y).x - tasksView.dragGrabX
		y: tasksView.mapFromItem(null, tasksView.dragAt.x, tasksView.dragAt.y).y - tasksView.dragGrabY
		z: 10
		width: tasksView.dragWidth
		opacity: 0.85
		sourceComponent: TaskRow {
			eventItem: tasksView.dragRow ? tasksView.dragRow.item : null
			today: tasksView.today
			showList: tasksView.byList || !tasksView.dragRow ? null : tasksView.dragRow.list
			actionsEnabled: false
			clickable: false
			backgroundColor: Kirigami.Theme.backgroundColor
			border.width: 1
			border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.2)
		}
	}

	// A header as a drop target: tinted while a drop goes there (red when it can't).
	component DropHighlight: Rectangle {
		property string key: ""
		readonly property bool targeted: tasksView.dragActive && tasksView.dropKey === key
		readonly property color tint: tasksView.dropRefused ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.highlightColor
		radius: 6
		color: targeted ? Qt.rgba(tint.r, tint.g, tint.b, 0.2) : "transparent"
		border.width: targeted ? 1 : 0
		border.color: tint
	}

	// An account's heading (several accounts only).
	Component {
		id: groupComponent
		Kirigami.Heading {
			readonly property var row: parent ? parent.row : null
			topPadding: Kirigami.Units.largeSpacing * 2
			bottomPadding: Kirigami.Units.smallSpacing
			leftPadding: Kirigami.Units.largeSpacing
			level: 5
			text: row ? row.text : ""
			textFormat: Text.PlainText // User text (account label)
			opacity: 0.85
			elide: Text.ElideRight
		}
	}

	// A list: its color, name, open count and "+" (the editor).
	Component {
		id: listComponent
		Item {
			readonly property var row: parent ? parent.row : null
			implicitHeight: listRow.implicitHeight
			DropHighlight {
				anchors.fill: parent
				anchors.topMargin: Kirigami.Units.largeSpacing
				key: row ? row.key : ""
			}
			RowLayout {
				id: listRow
				anchors.left: parent.left
				anchors.right: parent.right
				spacing: Kirigami.Units.smallSpacing
				// A list starts a new block: room above, the dot lined up with the task checks.
				Item {
					implicitWidth: Kirigami.Units.largeSpacing - Kirigami.Units.smallSpacing + 2
					implicitHeight: Kirigami.Units.largeSpacing * 2
				}
				Rectangle {
					implicitWidth: Math.round(Kirigami.Units.gridUnit * 0.6)
					implicitHeight: implicitWidth
					radius: width / 2
					color: appletConfig.eventColoredTextColor(appletConfig.eventColor(row && row.list.color ? row.list.color : null))
				}
				PlasmaComponents3.Label {
					Layout.fillWidth: true
					Layout.minimumWidth: 0
					text: row ? row.list.name : ""
					textFormat: Text.PlainText // User text (list name)
					font.weight: Font.DemiBold
					elide: Text.ElideRight
				}
				PlasmaComponents3.Label {
					visible: !!row && row.openCount > 0
					text: row ? String(row.openCount) : ""
					textFormat: Text.PlainText
					opacity: 0.75
				}
				PlasmaComponents3.ToolButton {
					Layout.rightMargin: Kirigami.Units.smallSpacing
					icon.name: "list-add"
					icon.width: Kirigami.Units.iconSizes.small
					icon.height: Kirigami.Units.iconSizes.small
					display: QQC2.AbstractButton.IconOnly
					text: row ? i18nc("%1 = task list name", "New task in %1", row.list.name) : ""
					onClicked: popup.newTask(null, "", row.list.id)
					PlasmaComponents3.ToolTip.text: text
					PlasmaComponents3.ToolTip.visible: hovered
				}
			}
		}
	}

	// A date section (by date): its name and count.
	Component {
		id: sectionComponent
		Item {
			id: sectionHeader
			readonly property var row: parent ? parent.row : null
			readonly property string section: row ? row.section : ""
			implicitHeight: sectionRow.implicitHeight
			DropHighlight {
				anchors.fill: parent
				anchors.topMargin: Kirigami.Units.largeSpacing
				key: row ? row.key : ""
			}
			RowLayout {
				id: sectionRow
				anchors.left: parent.left
				anchors.right: parent.right
				spacing: Kirigami.Units.smallSpacing
				Item {
					implicitWidth: Kirigami.Units.largeSpacing - Kirigami.Units.smallSpacing
					implicitHeight: Kirigami.Units.largeSpacing * 2 + Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing
				}
				PlasmaComponents3.Label {
					Layout.alignment: Qt.AlignBottom
					Layout.bottomMargin: Kirigami.Units.smallSpacing
					Layout.minimumWidth: 0
					text: {
						switch (sectionHeader.section) {
							case 'overdue': return i18n("Overdue")
							case 'today': return i18n("Today")
							case 'tomorrow': return i18n("Tomorrow")
							case 'week': return i18n("This week")
							case 'later': return i18n("Later")
							case 'nodate': return i18n("No date")
							case 'done': return i18n("Completed")
						}
						return ""
					}
					textFormat: Text.PlainText
					font.weight: Font.DemiBold
					color: sectionHeader.section === 'overdue' ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
					elide: Text.ElideRight
				}
				PlasmaComponents3.Label {
					Layout.alignment: Qt.AlignBottom
					Layout.bottomMargin: Kirigami.Units.smallSpacing
					Layout.fillWidth: true
					Layout.minimumWidth: 0
					text: row ? String(row.count) : ""
					textFormat: Text.PlainText
					opacity: 0.75
				}
			}
		}
	}

	Component {
		id: emptyComponent
		PlasmaComponents3.Label {
			readonly property var row: parent ? parent.row : null
			leftPadding: Kirigami.Units.largeSpacing * 2 + Kirigami.Units.iconSizes.small
			topPadding: Kirigami.Units.largeSpacing
			bottomPadding: Kirigami.Units.smallSpacing
			text: i18n("No open tasks")
			textFormat: Text.PlainText
			opacity: 0.75
			font.italic: true
		}
	}

	// "Add a task…": on the list (by list), else undated on a picked list.
	Component {
		id: addComponent
		QuickAddTaskRow {
			readonly property var row: parent ? parent.row : null
			eventModel: tasksView.eventModel
			listId: row && row.list ? row.list.id : ""
			lists: row && row.list ? [row.list] : tasksView.lists
			draftKey: row ? row.key : ""
			addDrafts: tasksView.addDrafts
		}
	}

	Component {
		id: taskComponent
		TaskRow {
			id: taskDelegate
			readonly property var row: parent ? parent.row : null
			eventItem: row ? row.item : null
			today: tasksView.today
			showList: !tasksView.byList && row ? row.list : null
			sectionDueKind: !tasksView.byList && row && (row.section === 'today' || row.section === 'tomorrow') ? row.section : ""
			draggable: true
			opacity: tasksView.dragActive && tasksView.dragRow === row ? 0.4 : 1
			onDragStarted: function(at) { tasksView.startDrag(taskDelegate.row, taskDelegate, at) }
			onDragMoved: function(at) { tasksView.moveDrag(at) }
			onDropped: function(at) {
				tasksView.moveDrag(at)
				tasksView.endDrag(true)
			}
			onDragCanceled: tasksView.endDrag(false)
			// Rows made again (a fetch) while dragging: no drop.
			Component.onDestruction: {
				if (dragging) {
					tasksView.endDrag(false)
				}
			}
		}
	}
}
