import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "TaskLists.js" as TaskLists
import "Tasks.js" as Tasks

// The Tasks tab, by date (tasksGroupBy 'date': Overdue, Today, Tomorrow, This week, Later, No
// date; Tasks.dateRows) or by list (every selected task list as a section, grouped by account when
// there are several; Tasks.taskRows), the done ones with "Show completed". "Add a task…" rows add
// without the editor: at the bottom of each list, or of the open tasks by date (undated, on a
// picked list). A task can be dragged onto a list (same account: moved) or onto Today, Tomorrow
// or No date (its due day changes).
// By list, the lists can be managed (TaskLists.js): a list header's "⋯" menu (or right click) has
// Rename (inline), Color (TickTick), Clear completed (Google) and Delete (confirmed inline), and
// "New list" at the end makes one. By date, "Manage lists" switches to by list.
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
		taskAccounts = typeof eventModel.getTaskAccounts === 'function' ? eventModel.getTaskAccounts() : []
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
		function onTaskListsChanged() { tasksView.deferredRebuild() }
	}

	//--- Managing the lists (by list)
	// The accounts lists can be made in: [{ id, label, provider }] (EventModel.getTaskAccounts).
	property var taskAccounts: []
	// The list being renamed, and the name typed so far (kept across rebuilds).
	property string renamingListId: ""
	property string renameDraft: ""
	// The list whose delete waits for a confirmation.
	property string confirmDeleteListId: ""
	// The list a request runs for.
	property string busyListId: ""
	// What went wrong, by list id ('' for "New list").
	property var listErrors: ({})

	function listCaps(listId) {
		return eventModel && typeof eventModel.taskListCapabilities === 'function'
			? eventModel.taskListCapabilities(listId)
			: { rename: false, delete: false, color: false, clearCompleted: false }
	}
	function setListError(listId, text) {
		var next = {}
		for (var key in listErrors) {
			next[key] = listErrors[key]
		}
		if (text) {
			next[listId] = text
			listErrorTimer.restart()
		} else {
			delete next[listId]
		}
		listErrors = next
	}
	Timer {
		id: listErrorTimer
		interval: 6000
		onTriggered: tasksView.listErrors = ({})
	}
	// Run a list request: busy meanwhile, the error inline when it fails.
	function runListAction(listId, errorText, start, onDone) {
		if (busyListId || !eventModel) {
			return
		}
		setListError(listId, "")
		busyListId = listId || "new"
		var view = tasksView
		start(function(err, result) {
			view.busyListId = ""
			if (err) {
				view.setListError(listId, errorText)
			} else if (onDone) {
				onDone(result)
			}
		})
	}

	function startRename(list) {
		confirmDeleteListId = ""
		renameDraft = list.name
		renamingListId = list.id
	}
	function cancelRename() {
		renamingListId = ""
		renameDraft = ""
	}
	function commitRename(list, text) {
		var title = TaskLists.cleanTitle(text)
		if (!title || title === list.name) {
			cancelRename()
			return
		}
		runListAction(list.id, i18n("Couldn't rename the list"), function(done) {
			eventModel.renameTaskList(list.id, title, done)
		}, function() {
			tasksView.cancelRename()
		})
	}
	function askDelete(list) {
		cancelRename()
		confirmDeleteListId = list.id
	}
	function deleteList(list) {
		confirmDeleteListId = ""
		runListAction(list.id, i18n("Couldn't delete the list"), function(done) {
			eventModel.deleteTaskList(list.id, done)
		}, null)
	}
	function setListColor(list, color) {
		runListAction(list.id, i18n("Couldn't change the list's color"), function(done) {
			eventModel.setTaskListColor(list.id, color, done)
		}, null)
	}
	function clearCompleted(list) {
		runListAction(list.id, i18n("Couldn't clear the completed tasks"), function(done) {
			eventModel.clearCompleted(list.id, done)
		}, null)
	}
	// The tasks a delete takes with it (those loaded: TickTick loads open tasks only).
	function listTaskCount(listId) {
		var calendar = eventModel ? eventModel.eventsByCalendar[listId] : null
		return TaskLists.taskCount(calendar && calendar.items)
	}

	// "New list": the field is open, the account it goes to, the name typed so far.
	property bool addingList: false
	property string newListAccount: ""
	property string newListDraft: ""
	// The account "New list" goes to: the picked one, else the first.
	function newListAccountEntry() {
		for (var i = 0; i < taskAccounts.length; i++) {
			if (taskAccounts[i].id === newListAccount) {
				return taskAccounts[i]
			}
		}
		return taskAccounts.length ? taskAccounts[0] : null
	}
	function createList(text) {
		var title = TaskLists.cleanTitle(text)
		var entry = newListAccountEntry()
		var account = entry ? entry.id : ""
		if (!title || !account) {
			return
		}
		runListAction("", i18n("Couldn't create the list"), function(done) {
			eventModel.createTaskList(account, title, done)
		}, function() {
			tasksView.newListDraft = ""
			tasksView.addingList = false
		})
	}

	function openListMenu(list, parentItem, x, y) {
		listMenu.list = list
		listMenu.caps = listCaps(list.id)
		listMenu.showColorMenu(listMenu.caps.color)
		listMenu.popup(parentItem, x, y)
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
				// By list: "New list" after the lists.
				Loader {
					Layout.fillWidth: true
					active: tasksView.byList && tasksView.taskAccounts.length > 0
					visible: active
					sourceComponent: newListComponent
				}
				// By date: the lists are managed by list.
				PlasmaComponents3.ToolButton {
					visible: !tasksView.byList && tasksView.taskAccounts.length > 0
					Layout.topMargin: Kirigami.Units.largeSpacing
					Layout.leftMargin: Kirigami.Units.smallSpacing
					icon.name: "view-list-details"
					icon.width: Kirigami.Units.iconSizes.small
					icon.height: Kirigami.Units.iconSizes.small
					text: i18n("Manage lists")
					opacity: hovered ? 1 : 0.75
					onClicked: plasmoid.configuration.tasksGroupBy = 'list'
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

	// A list: its color, name, open count, "+" (the editor) and "⋯" (the list's menu). Renaming,
	// its name is a field; a delete waits for the confirmation below it.
	Component {
		id: listComponent
		Item {
			id: listHeader
			readonly property var row: parent ? parent.row : null
			readonly property var list: row ? row.list : null
			readonly property string listId: list ? list.id : ""
			readonly property var caps: tasksView.listCaps(listId)
			readonly property bool manageable: TaskLists.hasAny(caps)
			readonly property bool renaming: !!listId && tasksView.renamingListId === listId
			readonly property bool confirming: !!listId && tasksView.confirmDeleteListId === listId
			readonly property bool busy: !!listId && tasksView.busyListId === listId
			readonly property string errorText: tasksView.listErrors[listId] || ""
			implicitHeight: headerColumn.implicitHeight
			DropHighlight {
				x: 0
				y: listRow.y + Kirigami.Units.largeSpacing
				width: parent.width
				height: listRow.height - Kirigami.Units.largeSpacing
				key: row ? row.key : ""
			}
			// Right click: the list's menu.
			MouseArea {
				id: listRightClick
				x: 0
				y: listRow.y
				width: parent.width
				height: listRow.height
				acceptedButtons: Qt.RightButton
				enabled: listHeader.manageable && !listHeader.renaming && !tasksView.busyListId
				onClicked: function(mouse) { tasksView.openListMenu(listHeader.list, listRightClick, mouse.x, mouse.y) }
			}
			ColumnLayout {
				id: headerColumn
				anchors.left: parent.left
				anchors.right: parent.right
				spacing: 0
				RowLayout {
					id: listRow
					Layout.fillWidth: true
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
						visible: !listHeader.renaming
						Layout.fillWidth: true
						Layout.minimumWidth: 0
						text: row ? row.list.name : ""
						textFormat: Text.PlainText // User text (list name)
						font.weight: Font.DemiBold
						elide: Text.ElideRight
					}
					// Rename: Enter saves, Esc cancels.
					Loader {
						active: listHeader.renaming
						visible: active
						Layout.fillWidth: true
						Layout.rightMargin: Kirigami.Units.smallSpacing
						Layout.minimumWidth: 0
						sourceComponent: PlasmaComponents3.TextField {
							text: tasksView.renameDraft
							topPadding: 2
							bottomPadding: 2
							font.weight: Font.DemiBold
							readOnly: listHeader.busy
							Accessible.name: i18n("List name")
							Component.onCompleted: {
								forceActiveFocus()
								selectAll()
							}
							onTextEdited: tasksView.renameDraft = text
							onAccepted: tasksView.commitRename(listHeader.list, text)
							Keys.onEscapePressed: function(event) {
								tasksView.cancelRename()
								event.accepted = true
							}
						}
					}
					PlasmaComponents3.BusyIndicator {
						visible: listHeader.busy
						running: visible
						Layout.preferredWidth: Kirigami.Units.iconSizes.small
						Layout.preferredHeight: Kirigami.Units.iconSizes.small
					}
					PlasmaComponents3.Label {
						visible: !listHeader.renaming && !!row && row.openCount > 0
						text: row ? String(row.openCount) : ""
						textFormat: Text.PlainText
						opacity: 0.75
					}
					PlasmaComponents3.ToolButton {
						visible: !listHeader.renaming
						Layout.rightMargin: listHeader.manageable ? 0 : Kirigami.Units.smallSpacing
						icon.name: "list-add"
						icon.width: Kirigami.Units.iconSizes.small
						icon.height: Kirigami.Units.iconSizes.small
						display: QQC2.AbstractButton.IconOnly
						text: row ? i18nc("%1 = task list name", "New task in %1", row.list.name) : ""
						onClicked: popup.newTask(null, "", row.list.id)
						PlasmaComponents3.ToolTip.text: text
						PlasmaComponents3.ToolTip.visible: hovered
					}
					PlasmaComponents3.ToolButton {
						id: listMenuButton
						visible: listHeader.manageable && !listHeader.renaming
						Layout.rightMargin: Kirigami.Units.smallSpacing
						enabled: !tasksView.busyListId
						icon.name: "overflow-menu"
						icon.width: Kirigami.Units.iconSizes.small
						icon.height: Kirigami.Units.iconSizes.small
						display: QQC2.AbstractButton.IconOnly
						text: row ? i18nc("%1 = task list name", "Manage %1", row.list.name) : ""
						onClicked: tasksView.openListMenu(listHeader.list, listMenuButton, 0, listMenuButton.height)
						PlasmaComponents3.ToolTip.text: text
						PlasmaComponents3.ToolTip.visible: hovered
					}
				}
				// Delete: confirmed here first.
				ColumnLayout {
					visible: listHeader.confirming
					Layout.fillWidth: true
					Layout.leftMargin: Kirigami.Units.largeSpacing * 2 + Kirigami.Units.iconSizes.small
					Layout.rightMargin: Kirigami.Units.largeSpacing
					Layout.topMargin: Kirigami.Units.smallSpacing
					spacing: Kirigami.Units.smallSpacing
					PlasmaComponents3.Label {
						Layout.fillWidth: true
						Layout.minimumWidth: 0
						text: listHeader.confirming ? i18ncp("%2 = task list name", "Delete the list \"%2\" and its %1 task? This can't be undone.", "Delete the list \"%2\" and its %1 tasks? This can't be undone.", tasksView.listTaskCount(listHeader.listId), listHeader.list.name) : ""
						textFormat: Text.PlainText // User text (list name)
						wrapMode: Text.Wrap
					}
					RowLayout {
						spacing: Kirigami.Units.smallSpacing
						PlasmaComponents3.Button {
							icon.name: "edit-delete"
							text: i18n("Delete")
							onClicked: tasksView.deleteList(listHeader.list)
						}
						PlasmaComponents3.Button {
							text: i18n("Cancel")
							onClicked: tasksView.confirmDeleteListId = ""
						}
					}
				}
				PlasmaComponents3.Label {
					visible: !!listHeader.errorText
					Layout.fillWidth: true
					Layout.minimumWidth: 0
					Layout.leftMargin: Kirigami.Units.largeSpacing * 2 + Kirigami.Units.iconSizes.small
					Layout.rightMargin: Kirigami.Units.largeSpacing
					text: listHeader.errorText
					textFormat: Text.PlainText
					color: Kirigami.Theme.negativeTextColor
					elide: Text.ElideRight
				}
			}
		}
	}

	// "New list" (by list): a button, then a field (and the account it goes to, when there are
	// several). Enter makes the list, Esc closes the field.
	Component {
		id: newListComponent
		ColumnLayout {
			id: newList
			readonly property bool busy: tasksView.busyListId === "new"
			readonly property string errorText: tasksView.listErrors[""] || ""
			spacing: 0
			PlasmaComponents3.ToolButton {
				visible: !tasksView.addingList
				Layout.topMargin: Kirigami.Units.largeSpacing
				Layout.leftMargin: Kirigami.Units.smallSpacing
				icon.name: "list-add"
				icon.width: Kirigami.Units.iconSizes.small
				icon.height: Kirigami.Units.iconSizes.small
				text: i18n("New list")
				opacity: hovered ? 1 : 0.75
				onClicked: {
					tasksView.cancelRename()
					tasksView.addingList = true
				}
			}
			RowLayout {
				visible: tasksView.addingList
				Layout.fillWidth: true
				Layout.topMargin: Kirigami.Units.largeSpacing
				Layout.leftMargin: Kirigami.Units.largeSpacing
				Layout.rightMargin: Kirigami.Units.largeSpacing
				spacing: Kirigami.Units.smallSpacing
				PlasmaComponents3.TextField {
					id: newListField
					Layout.fillWidth: true
					Layout.minimumWidth: 0
					placeholderText: i18n("New list name")
					text: tasksView.newListDraft
					readOnly: newList.busy
					onTextEdited: tasksView.newListDraft = text
					onAccepted: tasksView.createList(text)
					Keys.onEscapePressed: function(event) {
						tasksView.addingList = false
						tasksView.newListDraft = ""
						event.accepted = true
					}
					onVisibleChanged: {
						if (visible) {
							forceActiveFocus()
						}
					}
					Component.onCompleted: {
						if (visible) {
							forceActiveFocus()
						}
					}
				}
				// The account it goes to, when there's a choice.
				// Like the list picker of "Add a task…": the account's name and an arrow.
				PlasmaComponents3.ToolButton {
					id: accountButton
					readonly property var account: tasksView.newListAccountEntry()
					visible: tasksView.taskAccounts.length > 1
					Layout.maximumWidth: Kirigami.Units.gridUnit * 9
					text: account ? account.label : ""
					Accessible.name: i18nc("%1 = account name", "Account: %1", text)
					PlasmaComponents3.ToolTip.text: i18n("The account the new list goes to")
					PlasmaComponents3.ToolTip.visible: hovered
					contentItem: RowLayout {
						spacing: Kirigami.Units.smallSpacing
						PlasmaComponents3.Label {
							Layout.fillWidth: true
							Layout.minimumWidth: 0
							text: accountButton.text
							textFormat: Text.PlainText // User text (account label)
							opacity: 0.85
							elide: Text.ElideRight
						}
						Kirigami.Icon {
							implicitWidth: Kirigami.Units.iconSizes.small / 2 + 4
							implicitHeight: implicitWidth
							source: "arrow-down"
							opacity: 0.75
						}
					}
					onClicked: accountMenu.popup(accountButton, 0, accountButton.height)
					PlasmaComponents3.Menu {
						id: accountMenu
						Instantiator {
							model: tasksView.taskAccounts
							delegate: PlasmaComponents3.MenuItem {
								text: modelData.label
								checkable: true
								checked: !!accountButton.account && accountButton.account.id === modelData.id
								onTriggered: {
									tasksView.newListAccount = modelData.id
									newListField.forceActiveFocus()
								}
							}
							onObjectAdded: function(index, object) { accountMenu.insertItem(index, object) }
							onObjectRemoved: function(index, object) { accountMenu.removeItem(object) }
						}
					}
				}
				PlasmaComponents3.BusyIndicator {
					visible: newList.busy
					running: visible
					Layout.preferredWidth: Kirigami.Units.iconSizes.small
					Layout.preferredHeight: Kirigami.Units.iconSizes.small
				}
			}
			PlasmaComponents3.Label {
				visible: !!newList.errorText
				Layout.fillWidth: true
				Layout.minimumWidth: 0
				Layout.leftMargin: Kirigami.Units.largeSpacing
				Layout.rightMargin: Kirigami.Units.largeSpacing
				text: newList.errorText
				textFormat: Text.PlainText
				color: Kirigami.Theme.negativeTextColor
				elide: Text.ElideRight
			}
		}
	}

	// A list's menu ("⋯" or right click on its header).
	PlasmaComponents3.Menu {
		id: listMenu
		property var list: null
		property var caps: ({})

		// A submenu can't be hidden, so Color is only inserted for lists that have one (TickTick).
		readonly property int colorMenuIndex: 1 // After Rename
		function showColorMenu(show) {
			var shown = listMenu.itemAt(colorMenuIndex) && listMenu.itemAt(colorMenuIndex).subMenu === colorMenu
			if (show && !shown) {
				listMenu.insertMenu(colorMenuIndex, colorMenu)
			} else if (!show && shown) {
				listMenu.takeMenu(colorMenuIndex)
			}
		}
		property PlasmaComponents3.Menu colorMenu: PlasmaComponents3.Menu {
			title: i18n("Color")
			icon.name: "color-management"
			Repeater {
				model: TaskLists.swatches
				PlasmaComponents3.MenuItem {
					id: swatchItem
					readonly property string swatch: modelData
					readonly property bool current: !!listMenu.list && TaskLists.hexColor(listMenu.list.color) === swatch
					text: [i18nc("color", "Red"), i18nc("color", "Orange"), i18nc("color", "Yellow"), i18nc("color", "Blue"),
						i18nc("color", "Green"), i18nc("color", "Indigo"), i18nc("color", "Purple"), i18nc("color", "Gray")][index] || swatch
					contentItem: RowLayout {
						spacing: Kirigami.Units.smallSpacing
						Rectangle {
							implicitWidth: Kirigami.Units.iconSizes.small
							implicitHeight: implicitWidth
							radius: width / 2
							color: swatchItem.swatch
							border.width: swatchItem.current ? 2 : 0
							border.color: Kirigami.Theme.textColor
						}
						PlasmaComponents3.Label {
							Layout.fillWidth: true
							text: swatchItem.text
							textFormat: Text.PlainText
							font.weight: swatchItem.current ? Font.DemiBold : Font.Normal
						}
					}
					onTriggered: tasksView.setListColor(listMenu.list, swatch)
				}
			}
		}

		PlasmaComponents3.MenuItem {
			visible: !!listMenu.caps.rename
			height: visible ? implicitHeight : 0
			text: i18n("Rename…")
			icon.name: "edit-rename"
			onTriggered: tasksView.startRename(listMenu.list)
		}
		PlasmaComponents3.MenuItem {
			visible: !!listMenu.caps.clearCompleted
			height: visible ? implicitHeight : 0
			text: i18n("Clear completed")
			icon.name: "edit-clear-history"
			onTriggered: tasksView.clearCompleted(listMenu.list)
		}
		PlasmaComponents3.MenuSeparator {
			visible: !!listMenu.caps.delete
			height: visible ? implicitHeight : 0
		}
		PlasmaComponents3.MenuItem {
			visible: !!listMenu.caps.delete
			height: visible ? implicitHeight : 0
			text: i18n("Delete list…")
			icon.name: "edit-delete"
			onTriggered: tasksView.askDelete(listMenu.list)
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
