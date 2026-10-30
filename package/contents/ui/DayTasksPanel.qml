import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "Tasks.js" as Tasks

// The Day view's tasks (Tasks.dayTasks): due on the shown day, and on today the open overdue ones
// too (undated ones are only in the Tasks tab), as compact TaskRows under a "Tasks" heading with a
// "+" beside the title that shows "Add a task…" (due that day) below them. Hidden without task lists.
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
	// Tasks of several lists together: each row marks its list (a dot).
	readonly property bool mixedLists: {
		var ids = {}
		tasks.forEach(function(task) { ids[task.calendarId] = true })
		return Object.keys(ids).length > 1
	}
	// "All open tasks" (dayTasksScope 'all', the list menu): every open task of the shown list(s),
	// any date, in progress first; otherwise the ones due that day.
	readonly property bool allOpen: plasmoid.configuration.dayTasksScope === 'all'
	property var taskRows: [] // Tasks.dayTaskRows: [{ item, depth }], the open ones
	property var progressRows: [] // allOpen: the ones in progress (taskRows: these, then the others)
	property var todoRows: [] // …and the others
	property var doneRows: [] // …and the done ones, with showDone (below "Hide completed")
	// The done tasks are folded away under "N completed" (for the session).
	property bool showDone: false
	// "Add a task…" shown (the title's "+").
	property bool adding: false
	property int doneCount: 0
	onShowDoneChanged: deferredRebuild()
	// The tasks whose checklist is open (TaskRow.expandedStore), for the session.
	property var expandedSubtasks: ({})
	readonly property int openCount: tasks.filter(function(t) { return !Tasks.isDone(t) }).length

	visible: hasLists
	spacing: 2

	property var filterMenuObject: null
	function filterMenu() {
		if (!filterMenuObject) {
			filterMenuObject = listFilterMenuComponent.createObject(dayTasks)
		}
		return filterMenuObject
	}

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
		if (allOpen) {
			// The done ones (all of them, ever) aren't shown here.
			var sections = Tasks.dayAllTaskSections(items)
			progressRows = sections.progress
			todoRows = sections.todo
			taskRows = sections.progress.concat(sections.todo)
			doneCount = 0
			doneRows = []
			tasks = taskRows.map(function(row) { return row.item })
			return
		}
		progressRows = []
		todoRows = []
		var rows = Tasks.dayTaskRows(items, dayText, today)
		var openRows = rows.filter(function(row) { return !Tasks.isDone(row.item) })
		doneCount = rows.length - openRows.length
		taskRows = openRows
		doneRows = showDone ? rows.filter(function(row) { return Tasks.isDone(row.item) }) : []
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
		function onDayTasksScopeChanged() { dayTasks.deferredRebuild() }
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
		// "+" beside the title: shows "Add a task…" (again: hides it).
		PlasmaComponents3.ToolButton {
			visible: dayTasks.open
			Layout.leftMargin: Kirigami.Units.smallSpacing
			icon.name: "list-add"
			icon.width: Kirigami.Units.iconSizes.small
			icon.height: Kirigami.Units.iconSizes.small
			display: QQC2.AbstractButton.IconOnly
			text: i18n("New Task")
			checked: dayTasks.adding
			onClicked: {
				dayTasks.adding = !dayTasks.adding
				if (dayTasks.adding) {
					Qt.callLater(function() { if (quickAddLoader.item) quickAddLoader.item.focusField() })
				}
			}
			PlasmaComponents3.ToolTip.text: text
			PlasmaComponents3.ToolTip.visible: hovered
		}
		Item {
			Layout.fillWidth: true
		}
		// The list filter: all lists or one (several lists only), on the right.
		PlasmaComponents3.ToolButton {
			id: listFilterButton
			Layout.minimumWidth: 0
			Layout.maximumWidth: Kirigami.Units.gridUnit * 10
			readonly property string label: (dayTasks.filterList ? dayTasks.filterList.name : i18n("All lists"))
				+ (dayTasks.allOpen ? " · " + i18n("All open") : "")
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
					visible: !dayTasks.filterList
					Layout.alignment: Qt.AlignVCenter
					implicitWidth: listFilterButton.icon.width
					implicitHeight: listFilterButton.icon.height
					source: listFilterButton.icon.name
				}
				// The chosen list's mark (its emoji or color dot), as in the menu.
				Item {
					visible: !!dayTasks.filterList
					Layout.alignment: Qt.AlignVCenter
					implicitWidth: listFilterButton.icon.width
					implicitHeight: listFilterButton.icon.height
					ListMark {
						anchors.centerIn: parent
						list: dayTasks.filterList
						size: Math.round(listFilterButton.icon.width * 0.6)
						color: dayTasks.listMarkColor(dayTasks.filterList)
					}
				}
				PlasmaComponents3.Label {
					Layout.fillWidth: true
					Layout.minimumWidth: 0
					text: listFilterButton.label
					textFormat: Text.PlainText // User text (list name)
					elide: Text.ElideRight
				}
			}
			onClicked: dayTasks.filterMenu().popup(listFilterButton, 0, listFilterButton.height)
			PlasmaComponents3.ToolTip.text: i18n("Tasks shown")
			PlasmaComponents3.ToolTip.visible: hovered
		}
		// Made when first opened (three of these panels in the Day view, only one shown).
		Component {
			id: listFilterMenuComponent
			PlasmaComponents3.Menu {
				id: listFilterMenu
				PlasmaComponents3.MenuItem {
					text: i18n("Due this day")
					checkable: true
					checked: !dayTasks.allOpen
					onTriggered: plasmoid.configuration.dayTasksScope = 'day'
				}
				PlasmaComponents3.MenuItem {
					text: i18n("All open tasks")
					checkable: true
					checked: dayTasks.allOpen
					onTriggered: plasmoid.configuration.dayTasksScope = 'all'
				}
				PlasmaComponents3.MenuSeparator {
					visible: dayTasks.lists.length > 1
				}
				PlasmaComponents3.MenuItem {
					visible: dayTasks.lists.length > 1
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
						list: modelData
						markColor: dayTasks.listMarkColor(modelData)
						checkable: true
						checked: dayTasks.filterListId === modelData.id
						onTriggered: plasmoid.configuration.dayTasksListId = modelData.id
					}
					onObjectAdded: function(index, object) { listFilterMenu.insertItem(index + 5, object) }
					onObjectRemoved: function(index, object) { listFilterMenu.removeItem(object) }
				}
			}
		}
	}

	PlasmaComponents3.Label {
		visible: dayTasks.open && dayTasks.taskRows.length === 0
		Layout.fillWidth: true
		Layout.leftMargin: Kirigami.Units.smallSpacing
		// Only done ones left (folded away): all done.
		text: dayTasks.allOpen ? i18n("No open tasks") : dayTasks.doneCount > 0 ? i18n("All done") : i18n("No tasks")
		textFormat: Text.PlainText
		opacity: 0.75
		elide: Text.ElideRight
	}

	PlasmaComponents3.ScrollView {
		id: scrollView
		visible: dayTasks.open && (dayTasks.taskRows.length > 0 || dayTasks.doneCount > 0)
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
				model: dayTasks.visible && !dayTasks.allOpen ? dayTasks.taskRows : [] // Hidden (the Day view keeps three panels): no rows
				DayTaskRow {}
			}
			// "All open tasks": in progress, then the others.
			SectionLabel {
				visible: dayTasks.allOpen && dayTasks.progressRows.length > 0
				text: i18nc("tasks filter", "In progress") + " · " + dayTasks.progressRows.length
			}
			Repeater {
				model: dayTasks.visible ? dayTasks.progressRows : []
				DayTaskRow {}
			}
			SectionLabel {
				visible: dayTasks.allOpen && dayTasks.todoRows.length > 0
				Layout.topMargin: dayTasks.progressRows.length > 0 ? Kirigami.Units.smallSpacing : 0
				text: i18nc("tasks in the Day view, not in progress", "To do") + " · " + dayTasks.todoRows.length
			}
			Repeater {
				model: dayTasks.visible ? dayTasks.todoRows : []
				DayTaskRow {}
			}
			// "2 completed" / "Hide completed": the done tasks folded away or shown. Lined up with the rows
			// (the arrow in the checks' column), smaller than they are.
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
					// Smaller than the checks (a quiet line), centered in their column, at the middle of
					// the lowercase text beside it (lower than its line's middle).
					Item {
						Layout.preferredWidth: doneToggle.checkSize
						Layout.preferredHeight: doneToggle.checkSize
						Kirigami.Icon {
							anchors.centerIn: parent
							anchors.verticalCenterOffset: Math.round((doneMetrics.ascent - doneMetrics.descent - doneMetrics.xHeight) / 2)
							width: Math.round(doneToggle.checkSize * 0.7)
							height: width
						source: dayTasks.showDone ? "arrow-down" : (Qt.application.layoutDirection === Qt.RightToLeft ? "arrow-left" : "arrow-right")
						color: Kirigami.Theme.textColor
						isMask: true
						opacity: 0.7
						}
					}
					FontMetrics {
						id: doneMetrics
						font: doneLabel.font
					}
					PlasmaComponents3.Label {
						id: doneLabel
						Layout.fillWidth: true
						Layout.minimumWidth: 0
						text: doneToggle.text
						textFormat: Text.PlainText
						font.family: appletConfig.eventFont.family
						font.pointSize: appletConfig.eventFont.pointSize * 0.85
						opacity: 0.7
						elide: Text.ElideRight
					}
				}
			}
			// The done ones, under "Hide completed".
			Repeater {
				model: dayTasks.visible ? dayTasks.doneRows : []
				DayTaskRow {}
			}
		}
	}

	// The color of a list's dot (ListMark), as in the Tasks tab.
	function listMarkColor(list) {
		return appletConfig.eventColoredTextColor(appletConfig.eventColor(list && list.color ? list.color : null))
	}

	// "In progress" / "To do" over the rows, quiet like "2 completed", lined up with the titles.
	component SectionLabel: PlasmaComponents3.Label {
		Layout.fillWidth: true
		Layout.leftMargin: Kirigami.Units.smallSpacing * 2
		Layout.rightMargin: Kirigami.Units.smallSpacing * 2
		topPadding: Kirigami.Units.smallSpacing
		bottomPadding: 2
		textFormat: Text.PlainText
		font.family: appletConfig.eventFont.family
		font.pointSize: appletConfig.eventFont.pointSize * 0.85
		font.weight: Font.DemiBold
		opacity: 0.7
		elide: Text.ElideRight
	}

	// A task of the list (open or done), from the Repeater's row.
	component DayTaskRow: TaskRow {
		required property var modelData
		Layout.fillWidth: true
		eventItem: modelData.item
		depth: modelData.depth
		today: dayTasks.today
		compact: true
		compactShowsDay: dayTasks.allOpen
		listMark: dayTasks.mixedLists
		expandedStore: dayTasks.expandedSubtasks
		onCheckToggled: function(item, done) {
			if (done) {
				undoBar.offer(item)
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
	// Made after the title's "+" was first used (then kept: a task may still be saving), shown only
	// while adding.
	property bool addingUsed: false
	onAddingChanged: if (adding) addingUsed = true
	Loader {
		id: quickAddLoader
		active: dayTasks.addingUsed
		visible: dayTasks.open && dayTasks.adding
		Layout.fillWidth: true
		Layout.topMargin: Kirigami.Units.smallSpacing + 3
		Layout.bottomMargin: 3
		sourceComponent: QuickAddTaskRow {
			id: quickAddRow
			onDismissed: dayTasks.adding = false
			// A thin rounded frame: it reads as a field, apart from the tasks (a bit of room above and
			// below the text).
			Rectangle {
				z: -1
				anchors.fill: parent
				anchors.topMargin: -3
				anchors.bottomMargin: -3
				radius: Kirigami.Units.cornerRadius * 2
				color: "transparent"
				border.width: 1
				border.color: quickAddRow.fieldFocused ? Kirigami.Theme.highlightColor
					: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.18)
			}
			eventModel: dayTasks.eventModel
			lists: dayTasks.lists
			// The filtered list, if any: new tasks go there.
			listId: dayTasks.filterListId
			dueDay: dayTasks.allOpen ? "" : dayTasks.dayText // All open: undated unless typed
			compact: true
		}
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
