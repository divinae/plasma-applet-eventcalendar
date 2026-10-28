import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "Tasks.js" as Tasks

// The Day view's tasks (Tasks.dayTasks): due on the shown day, and on today the open overdue ones
// too (undated ones are only in the Tasks tab), as compact TaskRows under a "Tasks" heading with a
// "+" for a task due that day, and "Add a task…" below them. Hidden without task lists.
// Collapsible: a strip that folds to its heading (above the hour grid); otherwise always open
// (beside the grid, right of it). Subtasks (Google) are indented under their parent; checking a
// task offers "Completed · Undo" below the list for a few seconds.
ColumnLayout {
	id: dayTasks

	property var eventModel: null
	property date day: new Date()
	property bool collapsible: false
	property bool expanded: true
	// The list's height at most (it scrolls past it).
	property real maxListHeight: Kirigami.Units.gridUnit * 8

	readonly property string dayText: Tasks.dayString(day)
	readonly property string today: Tasks.dayString(timeModel.currentTime)
	readonly property bool open: !collapsible || expanded

	property bool hasLists: false
	property var lists: []
	// The list filter (heading's list picker, dayTasksListId): one list's id, or "" for all. A list
	// that's gone counts as all.
	readonly property string filterListId: {
		var id = String(plasmoid.configuration.dayTasksListId || "")
		return lists.some(function(list) { return list.id === id }) ? id : ""
	}
	readonly property var filterList: {
		for (var i = 0; i < lists.length; i++) {
			if (lists[i].id === filterListId) {
				return lists[i]
			}
		}
		return null
	}
	property var tasks: []
	property var taskRows: [] // Tasks.dayTaskRows: [{ item, depth }], the done ones only with showDone
	// The done tasks are folded away under "N completed" (for the session).
	property bool showDone: false
	property int doneCount: 0
	onShowDoneChanged: deferredRebuild()
	// The tasks whose checklist is open (TaskRow.expandedStore), for the session.
	property var expandedSubtasks: ({})
	readonly property int openCount: tasks.filter(function(t) { return !Tasks.isDone(t) }).length

	visible: hasLists
	spacing: 2

	function rebuild() {
		var lists = eventModel ? eventModel.getSelectedTaskLists() : []
		var shownId = String(plasmoid.configuration.dayTasksListId || "")
		if (!lists.some(function(list) { return list.id === shownId })) {
			shownId = ""
		}
		var items = []
		for (var i = 0; i < lists.length; i++) {
			if (shownId && lists[i].id !== shownId) {
				continue
			}
			var calendar = eventModel.loadedCalendar(lists[i].id)
			if (calendar && calendar.items) {
				items = items.concat(calendar.items)
			}
		}
		if (JSON.stringify(dayTasks.lists) !== JSON.stringify(lists)) {
			dayTasks.lists = lists // Unchanged: not set again (the list menu would be made again)
		}
		hasLists = lists.length > 0
		Tasks.stampInProgress(items, plasmoid.configuration.tasksInProgress)
		var rows = Tasks.dayTaskRows(items, dayText, today)
		var openRows = rows.filter(function(row) { return !Tasks.isDone(row.item) })
		doneCount = rows.length - openRows.length
		taskRows = showDone ? rows : openRows
		tasks = rows.map(function(row) { return row.item })
	}
	function deferredRebuild() {
		Qt.callLater(rebuild)
	}
	// A change of calendarId concerns the panel: one of the task lists (selected now: maybe since
	// the last rebuild).
	function listChanged(calendarId) {
		var has = function(lists) {
			return lists.some(function(list) { return list.id === calendarId })
		}
		if (has(lists) || (!!eventModel && has(eventModel.getSelectedTaskLists()))) {
			deferredRebuild()
		}
	}
	Component.onCompleted: rebuild()
	onDayTextChanged: deferredRebuild()
	onTodayChanged: deferredRebuild()
	onEventModelChanged: deferredRebuild()
	Connections {
		target: plasmoid.configuration
		function onDayTasksListIdChanged() { dayTasks.deferredRebuild() }
		function onTasksInProgressChanged() { dayTasks.deferredRebuild() }
	}

	Connections {
		target: dayTasks.eventModel
		ignoreUnknownSignals: true // taskListsChanged: EventModel's
		// Event calendars' changes: not for this panel.
		function onCalendarFetched(calendarId, data) { dayTasks.listChanged(calendarId) }
		function onAllDataFetched() { dayTasks.deferredRebuild() }
		function onDataCleared() { dayTasks.deferredRebuild() }
		function onEventAdded(calendarId, data) { dayTasks.listChanged(calendarId) }
		function onEventRemoved(calendarId, eventId, data) { dayTasks.listChanged(calendarId) }
		function onEventUpdated(calendarId, eventId, data) { dayTasks.listChanged(calendarId) }
		function onTaskListsChanged() { dayTasks.deferredRebuild() } // A list renamed, recolored, deleted…
	}

	// Heading: (fold arrow) "Tasks", the list filter, "+".
	RowLayout {
		Layout.fillWidth: true
		// Islands: some room between the title and the first task.
		Layout.bottomMargin: appletConfig.islands ? Kirigami.Units.smallSpacing : 0
		spacing: 0

		PlasmaComponents3.ToolButton {
			visible: dayTasks.collapsible
			icon.name: dayTasks.expanded ? "arrow-down" : "arrow-right"
			display: QQC2.AbstractButton.IconOnly
			text: dayTasks.expanded ? i18n("Hide tasks") : i18n("Show tasks")
			onClicked: dayTasks.expanded = !dayTasks.expanded
			PlasmaComponents3.ToolTip.text: text
			PlasmaComponents3.ToolTip.visible: hovered
		}
		// The card's title, like the weather card's location beside it.
		PlasmaComponents3.Label {
			Layout.leftMargin: dayTasks.collapsible || appletConfig.islands ? 0 : Kirigami.Units.smallSpacing
			text: i18n("Tasks")
			textFormat: Text.PlainText
			// Like the weather card's title beside it.
			font.weight: Font.Bold
			font.pointSize: appletConfig.fontPoints(Kirigami.Theme.defaultFont) * 1.25
			MouseArea {
				anchors.fill: parent
				enabled: dayTasks.collapsible
				onClicked: dayTasks.expanded = !dayTasks.expanded
			}
		}
		Item {
			Layout.fillWidth: true
		}
		// The list filter: all lists or one (several lists only), on the right.
		PlasmaComponents3.ToolButton {
			id: listFilterButton
			visible: dayTasks.lists.length > 1
			Layout.minimumWidth: 0
			Layout.maximumWidth: Kirigami.Units.gridUnit * 9
			readonly property string label: dayTasks.filterList ? dayTasks.filterList.name : i18n("All lists")
			text: label.replace(/&/g, "&&") // No mnemonic from a "&" in the list's name
			Accessible.name: label
			icon.name: "view-filter"
			icon.width: Kirigami.Units.iconSizes.small
			icon.height: Kirigami.Units.iconSizes.small
			display: QQC2.AbstractButton.TextBesideIcon
			// The list's name as plain text (never HTML).
			contentItem: RowLayout {
				spacing: listFilterButton.spacing
				Kirigami.Icon {
					Layout.alignment: Qt.AlignVCenter
					implicitWidth: listFilterButton.icon.width
					implicitHeight: listFilterButton.icon.height
					source: listFilterButton.icon.name
				}
				PlasmaComponents3.Label {
					Layout.fillWidth: true
					Layout.minimumWidth: 0
					text: listFilterButton.label
					textFormat: Text.PlainText // User text (list name)
					elide: Text.ElideRight
				}
			}
			onClicked: listFilterMenu.popup(listFilterButton, 0, listFilterButton.height)
			PlasmaComponents3.ToolTip.text: i18n("Task list shown")
			PlasmaComponents3.ToolTip.visible: hovered
		}
		PlasmaComponents3.Menu {
			id: listFilterMenu
			PlasmaComponents3.MenuItem {
				text: i18n("All lists")
				checkable: true
				checked: !dayTasks.filterListId
				onTriggered: plasmoid.configuration.dayTasksListId = ""
			}
			PlasmaComponents3.MenuSeparator {}
			Instantiator {
				model: dayTasks.lists
				delegate: PlainMenuItem {
					required property var modelData
					label: modelData.name
					checkable: true
					checked: dayTasks.filterListId === modelData.id
					onTriggered: plasmoid.configuration.dayTasksListId = modelData.id
				}
				onObjectAdded: function(index, object) { listFilterMenu.insertItem(index + 2, object) }
				onObjectRemoved: function(index, object) { listFilterMenu.removeItem(object) }
			}
		}
		// Islands: "Add a task…" below is enough.
		PlasmaComponents3.ToolButton {
			visible: !appletConfig.islands
			icon.name: "list-add"
			icon.width: Kirigami.Units.iconSizes.small
			icon.height: Kirigami.Units.iconSizes.small
			display: QQC2.AbstractButton.IconOnly
			text: i18n("New Task")
			onClicked: popup.newTask(dayTasks.day, "", "")
			PlasmaComponents3.ToolTip.text: text
			PlasmaComponents3.ToolTip.visible: hovered
		}
	}

	PlasmaComponents3.Label {
		visible: dayTasks.open && dayTasks.taskRows.length === 0
		Layout.fillWidth: true
		Layout.leftMargin: Kirigami.Units.smallSpacing
		// Only done ones left (folded away): all done.
		text: dayTasks.doneCount > 0 ? i18n("All done") : i18n("No tasks")
		textFormat: Text.PlainText
		opacity: 0.75
		elide: Text.ElideRight
	}

	PlasmaComponents3.ScrollView {
		id: scrollView
		visible: dayTasks.open && dayTasks.taskRows.length > 0
		Layout.fillWidth: true
		Layout.preferredHeight: Math.min(taskColumn.implicitHeight, dayTasks.maxListHeight)
		contentWidth: availableWidth
		QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff
		QQC2.ScrollBar.vertical: OverlayScrollBar {
			view: scrollView
		}

		ColumnLayout {
			id: taskColumn
			width: scrollView.availableWidth
			spacing: 1
			Repeater {
				model: dayTasks.taskRows
				TaskRow {
					Layout.fillWidth: true
					eventItem: modelData.item
					depth: modelData.depth
					today: dayTasks.today
					compact: true
					expandedStore: dayTasks.expandedSubtasks
					onCheckToggled: function(item, done) {
						if (done) {
							undoBar.offer(item)
						}
					}
				}
			}
		}
	}

	// "2 completed" / "Hide completed": the done tasks folded away or shown. Laid out like the rows
	// and "Add a task…": the arrow where the checks are, the text in the tasks' font.
	QQC2.AbstractButton {
		id: doneToggle
		readonly property real sideMargin: Kirigami.Units.smallSpacing * 2 // TaskRow's (compact)
		readonly property int checkSize: 2 * Math.round(Kirigami.Units.iconSizes.small * 1.1 / 2)
		visible: dayTasks.open && dayTasks.doneCount > 0
		Layout.fillWidth: true
		hoverEnabled: true
		leftPadding: sideMargin
		rightPadding: sideMargin
		topPadding: Kirigami.Units.smallSpacing
		bottomPadding: Kirigami.Units.smallSpacing
		text: dayTasks.showDone ? i18n("Hide completed") : i18np("%1 completed", "%1 completed", dayTasks.doneCount)
		Accessible.name: text
		onClicked: dayTasks.showDone = !dayTasks.showDone
		background: Rectangle {
			radius: 6
			color: doneToggle.hovered ? appletConfig.agendaHoverBackground : "transparent"
		}
		contentItem: RowLayout {
			spacing: Kirigami.Units.largeSpacing
			Kirigami.Icon {
				Layout.preferredWidth: doneToggle.checkSize
				Layout.preferredHeight: doneToggle.checkSize
				source: dayTasks.showDone ? "arrow-down" : (Qt.application.layoutDirection === Qt.RightToLeft ? "arrow-left" : "arrow-right")
				color: Kirigami.Theme.textColor
				isMask: true
				opacity: 0.7
			}
			PlasmaComponents3.Label {
				Layout.fillWidth: true
				Layout.minimumWidth: 0
				text: doneToggle.text
				textFormat: Text.PlainText
				font.family: appletConfig.eventFont.family
				font.pointSize: appletConfig.eventFont.pointSize
				opacity: 0.7
				elide: Text.ElideRight
			}
		}
	}

	TaskUndoBar {
		id: undoBar
		Layout.alignment: Qt.AlignHCenter
		Layout.preferredHeight: shown ? implicitHeight : 0
		eventModel: dayTasks.eventModel
	}

	// "Add a task…" due on the shown day, on the last used list (a picker when there are several).
	QuickAddTaskRow {
		visible: dayTasks.open
		Layout.fillWidth: true
		eventModel: dayTasks.eventModel
		lists: dayTasks.lists
		// The filtered list, if any: new tasks go there.
		listId: dayTasks.filterListId
		dueDay: dayTasks.dayText
		compact: true
	}

	// A card taller than the tasks (the Day view's right column, down to the grid's bottom): they
	// stay at the top.
	Item {
		Layout.fillHeight: true
	}

	// Apart from what follows (the hours below the strip). Not in the islands style: the card's edge is.
	property bool showSeparator: true
	Kirigami.Separator {
		visible: dayTasks.showSeparator && !appletConfig.islands
		Layout.fillWidth: true
		Layout.topMargin: Kirigami.Units.smallSpacing
		Layout.bottomMargin: Kirigami.Units.smallSpacing
	}
}
