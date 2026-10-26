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
// picked list). A task can be dragged onto a list (same account: moved; another: copied there and
// deleted here) or onto Today, Tomorrow
// or No date (its due day changes).
// By list, the lists can be managed (TaskLists.js): a list header's "⋯" menu (or right click) has
// Rename (inline), Color (TickTick), Clear completed (Google) and Delete (confirmed inline), and
// "New list" at the end makes one. "Manage lists" (the header's "⋯" menu) switches to by list.
// Not grouped (tasksGroupBy 'none'): one run of tasks (Tasks.flatRows). The header's "⋯" menu also
// has the sort (tasksSortBy: due date, title, list order), "Show details" (notes, list) and
// "Show / Hide completed".
// Smart filters (like TickTick's): All, Today, Tomorrow, Next 7 days, Overdue, No date and each
// list (tasksFilter), in a side bar when the view is wide enough (also drop targets), else in a
// menu on the header's title; the header shows the filter's name and open count, "Add a task…"
// adds to its list / on its day.
// Header, sections, rows and "Add a task…" are one column, centered, at most maxColumnWidth wide,
// all with the same side margins (sideMargin, like TaskRow's).
// Subtasks (Google: tasks with a parent) are indented under their parent; checking a task offers
// "Completed · Undo" for a few seconds. Google lists: a task dragged between the rows of its list
// (by list; by date within its section) is put there (a line shows where; EventModel.reorderTask).
// Keyboard (PopupView, KeyNav.js): Up / Down highlight a task, Space checks it, Enter opens it,
// E edits it, Delete deletes it (with undo); N goes to "Add a task…".
Item {
	id: tasksView

	property var eventModel: null
	readonly property bool showCompleted: !!plasmoid.configuration.tasksShowCompleted
	// 'date', 'list' or 'none' (one run of tasks, sorted by sortBy).
	readonly property string groupBy: {
		var setting = plasmoid.configuration.tasksGroupBy
		return setting === 'list' || setting === 'none' ? setting : 'date'
	}
	readonly property bool byList: groupBy === 'list'
	readonly property bool byDate: groupBy === 'date'
	// The order within a section: 'due', 'title', 'list' or 'priority' (Tasks.compareOpen).
	readonly property string sortBy: {
		var setting = plasmoid.configuration.tasksSortBy
		return setting === 'title' || setting === 'list' || setting === 'priority' ? setting : 'due'
	}
	// The tasks whose checklist is open (TaskRow.expandedStore), for the session.
	property var expandedSubtasks: ({})
	// The notes line and each task's list (name, islands: stripe).
	readonly property bool showDetails: plasmoid.configuration.tasksShowDetails !== false
	readonly property string today: Tasks.dayString(timeModel.currentTime)
	readonly property int firstDayOfWeek: {
		var setting = plasmoid.configuration.firstDayOfWeek
		return setting >= 0 ? setting : Qt.locale().firstDayOfWeek % 7
	}

	property var rows: []
	property var lists: [] // The lists shown (the filter's list only, for a list filter)
	property var allLists: [] // Every selected list

	//--- Smart filters (Tasks.js): All, Today, Tomorrow, Next 7 days, Overdue, No date, each list.
	// A side bar when there's room, else a menu on the header's title.
	readonly property string configFilter: String(plasmoid.configuration.tasksFilter || 'all')
	// Lists left out of the smart filters ({ id: true }), Settings key tasksSmartHiddenLists.
	readonly property var smartHidden: {
		var map = {}
		Array.prototype.slice.call(plasmoid.configuration.tasksSmartHiddenLists || []).forEach(function(id) { map[id] = true })
		return map
	}
	onSmartHiddenChanged: deferredRebuild()
	function setShownInSmartLists(list, shown) {
		var ids = Array.prototype.slice.call(plasmoid.configuration.tasksSmartHiddenLists || []).filter(function(id) {
			return id !== list.id
		})
		if (!shown) {
			ids.push(list.id)
		}
		plasmoid.configuration.tasksSmartHiddenLists = ids
	}
	// The filter shown: configFilter, 'all' while its list is missing (Tasks.validFilter).
	property string currentFilter: 'all'
	property var filterCounts: ({}) // Open tasks by filter (Tasks.filterCounts)
	property var filterEntries: [] // Tasks.filterEntries
	readonly property int currentCount: filterCounts[currentFilter] || 0
	readonly property string currentListId: Tasks.filterListId(currentFilter)
	// Where "Add a task…" adds without a list of its own: the filter's list and due day.
	readonly property var quickAddTarget: Tasks.filterQuickAdd(currentFilter, today)
	// Room for the filters' side bar; folded away with the header's button (tasksSidebarCollapsed).
	readonly property bool sidebarFits: width >= Kirigami.Units.gridUnit * 34
	readonly property bool showSidebar: sidebarFits && !plasmoid.configuration.tasksSidebarCollapsed
	readonly property real sidebarWidth: Kirigami.Units.gridUnit * 10.5
	onConfigFilterChanged: rebuild()

	function setFilter(key) {
		plasmoid.configuration.tasksFilter = key
	}
	function findList(id) {
		for (var i = 0; i < allLists.length; i++) {
			if (allLists[i].id === id) {
				return allLists[i]
			}
		}
		return null
	}
	function filterName(key) {
		switch (key) {
			case 'all': return i18nc("tasks filter", "All")
			case 'today': return i18nc("tasks filter", "Today")
			case 'tomorrow': return i18nc("tasks filter", "Tomorrow")
			case 'next7': return i18nc("tasks filter", "Next 7 days")
			case 'overdue': return i18nc("tasks filter", "Overdue")
			case 'nodate': return i18nc("tasks filter", "No date")
		}
		var list = findList(Tasks.filterListId(key))
		return list ? list.name : ""
	}
	function filterIcon(key) {
		switch (key) {
			case 'all': return "view-list-text"
			case 'today': return "view-calendar-day"
			case 'tomorrow': return "view-calendar-upcoming-events"
			case 'next7': return "view-calendar-week"
			case 'overdue': return "flag"
		}
		return ""
	}
	// A list's dot color, readable on the popup's background.
	function listDotColor(list) {
		return appletConfig.eventColoredTextColor(appletConfig.eventColor(list && list.color ? list.color : null))
	}

	//--- Islands style: each section (by date) or list (by list) is a card that folds to its header,
	// the done tasks of all lists in a "Completed" card at the end, folded at first.
	readonly property bool islands: appletConfig.islands
	property var cards: [] // Tasks.cardRows of rows
	property var collapsed: ({}) // { cardKey: bool }, for the session
	readonly property real cardEndPadding: Kirigami.Units.smallSpacing * 2 + 2
	readonly property real cardTitlePointSize: appletConfig.fontPoints(Kirigami.Theme.defaultFont) * 1.15
	// The header's title (the filter's name): above the cards' titles.
	readonly property real titlePointSize: appletConfig.fontPoints(Kirigami.Theme.defaultFont) * 1.45
	function isCollapsed(key) {
		return Object.prototype.hasOwnProperty.call(collapsed, key) ? collapsed[key] : key === 'section:done'
	}
	function toggleCollapsed(key) {
		var next = {}
		for (var k in collapsed) {
			next[k] = collapsed[k]
		}
		next[key] = !isCollapsed(key)
		collapsed = next
		rebuild()
	}
	onIslandsChanged: rebuild()

	//--- The column
	readonly property real maxColumnWidth: Kirigami.Units.gridUnit * 28
	// The room left and right of everything in the column (TaskRow's own side margin).
	readonly property real sideMargin: Kirigami.Units.largeSpacing
	// TaskRow's check, and where its title starts: list dots and the empty note line up with them.
	readonly property real checkSize: 2 * Math.round(Kirigami.Units.iconSizes.small * 1.1 / 2)
	readonly property real titleX: sideMargin + checkSize + Kirigami.Units.largeSpacing
	// Secondary text (counts, account names): dimmed, still clear on a translucent background.
	readonly property real dimOpacity: 0.75

	// "Add a task…" text and focus by row key, across rebuilds (they make the rows again).
	property var addDrafts: ({})

	function rebuild() {
		if (!eventModel) {
			rows = []
			lists = []
			allLists = []
			filterCounts = {}
			filterEntries = []
			currentFilter = 'all'
			return
		}
		taskAccounts = typeof eventModel.getTaskAccounts === 'function' ? eventModel.getTaskAccounts() : []
		var selected = eventModel.getSelectedTaskLists()
		var itemsByList = {}
		for (var i = 0; i < selected.length; i++) {
			var calendar = eventModel.eventsByCalendar[selected[i].id]
			itemsByList[selected[i].id] = calendar && calendar.items ? calendar.items : []
		}
		var counts = Tasks.filterCounts(selected, itemsByList, today, smartHidden)
		var filter = Tasks.validFilter(configFilter, selected)
		var shown = Tasks.filterLists(selected, itemsByList, filter, today, smartHidden)
		var flick = scrollView.contentItem
		var y = flick ? flick.contentY : 0
		// Islands: the done ones in the "Completed" card instead of with the open ones.
		var withDone = showCompleted && !islands
		var newRows = byList ? Tasks.taskRows(shown.lists, shown.itemsByList, withDone, sortBy)
			: groupBy === 'none' ? Tasks.flatRows(shown.lists, shown.itemsByList, sortBy, withDone)
			: Tasks.dateRows(shown.lists, shown.itemsByList, today, firstDayOfWeek, withDone, sortBy)
		// One "Add a task…" for the whole view, at the top (not one per list): on the filter's list, or
		// a picked one.
		newRows = [{ type: 'add', key: 'add' }].concat(newRows.filter(function(row) { return row.type !== 'add' }))
		// By list: a list with nothing to show (no open tasks; no done ones shown with them) is left out.
		newRows = newRows.filter(function(row) {
			return row.type !== 'list' || row.openCount > 0 || (withDone && row.doneCount > 0)
		})
		// …and an account's heading with none of its lists left.
		newRows = newRows.filter(function(row, i, all) {
			return row.type !== 'group' || (i + 1 < all.length && all[i + 1].type === 'list')
		})
		var newCards = []
		if (islands) {
			// Not grouped: the tasks and the quick add are one card, as a list's (byList).
			var joinAdd = !byDate
			if (showCompleted) {
				newRows = newRows.concat(Tasks.completedRows(shown.lists, shown.itemsByList))
			}
			var folded = {}
			Tasks.cardRows(newRows, joinAdd).forEach(function(card) {
				if (card.start) {
					folded[card.key] = isCollapsed(card.key)
				}
			})
			newRows = Tasks.collapseRows(newRows, joinAdd, folded)
			newCards = Tasks.cardRows(newRows, joinAdd)
		}
		rememberAddFocus()
		allLists = selected
		filterCounts = counts
		filterEntries = Tasks.filterEntries(selected, counts)
		currentFilter = filter
		lists = shown.lists
		cards = newCards // Before the rows: their delegates read it
		rows = newRows
		keepKeyRow()
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
	onGroupByChanged: rebuild()
	onSortByChanged: rebuild()
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

	// The list a task row shows (by date, not grouped): none without details or on a list's filter.
	function taskRowList(row) {
		return showDetails && !currentListId ? row.list : null
	}

	function openListMenu(list, parentItem, x, y) {
		listMenu.list = list
		listMenu.caps = listCaps(list.id)
		listMenu.showColorMenu(listMenu.caps.color)
		listMenu.popup(parentItem, x, y)
	}

	//--- Keyboard: the highlighted task (keyRowKey), see KeyNav.js
	property string keyRowKey: ""
	property int keyRowIndex: -1 // Among the task rows: where to go on when the task leaves the view
	function taskRowKeys() {
		return rows.filter(function(row) { return row.type === 'task' }).map(function(row) { return row.key })
	}
	function keepKeyRow() {
		if (!keyRowKey) {
			return
		}
		var keys = taskRowKeys()
		if (keys.indexOf(keyRowKey) >= 0) {
			keyRowIndex = keys.indexOf(keyRowKey)
		} else {
			keyRowKey = keys.length ? keys[Math.max(0, Math.min(keyRowIndex, keys.length - 1))] : ""
		}
	}
	function moveKeyRow(delta) {
		var keys = taskRowKeys()
		if (!keys.length) {
			return
		}
		var i = keys.indexOf(keyRowKey)
		i = i < 0 ? (delta > 0 ? 0 : keys.length - 1) : Math.max(0, Math.min(keys.length - 1, i + delta))
		keyRowKey = keys[i]
		keyRowIndex = i
		Qt.callLater(scrollToKeyRow)
	}
	// The delegate of the row with key (a TaskRow, "Add a task…", …), or null.
	function rowItem(key) {
		for (var i = 0; i < rowsColumn.children.length; i++) {
			var loader = rowsColumn.children[i]
			if (loader.row && loader.row.key === key) {
				return loader
			}
		}
		return null
	}
	function scrollToKeyRow() {
		var loader = rowItem(keyRowKey)
		var flick = scrollView.contentItem
		if (!loader || !flick) {
			return
		}
		var y = loader.mapToItem(rowsColumn, 0, 0).y + rowsColumn.y
		if (y < flick.contentY) {
			flick.contentY = Math.max(0, y - Kirigami.Units.smallSpacing)
		} else if (y + loader.height > flick.contentY + flick.height) {
			flick.contentY = Math.min(Math.max(0, flick.contentHeight - flick.height), y + loader.height - flick.height + Kirigami.Units.smallSpacing)
		}
	}
	// The highlighted task's row data and delegate (TaskRow), or null.
	function keyRow() {
		for (var i = 0; i < rows.length; i++) {
			if (rows[i].key === keyRowKey) {
				return rows[i]
			}
		}
		return null
	}
	// action: 'open', 'toggle', 'edit', 'delete'. True when there was a task for it.
	function keyAction(action) {
		var row = keyRow()
		if (!row) {
			moveKeyRow(1) // First press: highlight the first task
			return taskRowKeys().length > 0
		}
		var loader = rowItem(row.key)
		var taskRow = loader ? loader.item : null
		switch (action) {
			case 'open':
				popup.activateEvent(row.item)
				break
			case 'toggle':
				if (taskRow && typeof taskRow.toggleDone === 'function') {
					taskRow.toggleDone()
				}
				break
			case 'edit':
				if (row.item.canEdit !== false) {
					popup.editEvent(row.item)
				}
				break
			case 'delete':
				if (row.item.canEdit !== false) {
					popup.deleteWithUndo(row.item, false)
				}
				break
		}
		return true
	}
	// "N": the "Add a task…" field.
	function focusQuickAdd() {
		var loader = rowItem('add')
		if (loader && loader.item && typeof loader.item.focusField === 'function') {
			var flick = scrollView.contentItem
			if (flick) {
				flick.contentY = 0
			}
			loader.item.focusField()
			return true
		}
		return false
	}

	//--- "Completed · Undo" after a task was checked
	function offerCompletedUndo(item, done) {
		if (done) {
			undoBar.offer(item)
		}
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
	property var dropAction: null // { kind: 'move', listId } | { kind: 'due', day } | { kind: 'reorder', previous }
	property bool reorderAbove: false // A reorder: the line above the row under the pointer (else below)
	// A task can be put between the rows of its list: Google lists, in the list's order (by due date
	// only among tasks due the same day).
	function canReorder(target) {
		if (!eventModel || typeof eventModel.supportsReorder !== 'function' || !dragRow || !target || target.type !== 'task'
			|| !eventModel.supportsReorder(dragRow.list.id)) {
			return false
		}
		return sortBy === 'list' || (sortBy === 'due' && Tasks.dueDay(target.item) === Tasks.dueDay(dragRow.item))
	}
	function rowIndex(key) {
		for (var i = 0; i < rows.length; i++) {
			if (rows[i].key === key) {
				return i
			}
		}
		return -1
	}
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
		var key = ""
		var refused = false
		var action = null
		// The side bar: a list (moved) or Today, Tomorrow, No date (its due day changes).
		var sp = sidebarColumn.mapFromItem(null, at.x, at.y)
		if (showSidebar && sp.x >= 0 && sp.x < sidebarColumn.width && sp.y >= 0 && sp.y < sidebarColumn.height) {
			var entryItem = sidebarColumn.childAt(sp.x, sp.y)
			var entry = entryItem ? entryItem.entry : null
			if (entry && dragRow && entry.type === 'list') {
				var listDrop = Tasks.listDrop(dragRow.list.id, entry.list.id)
				if (listDrop !== 'none') {
					key = 'side:' + entry.key
					refused = listDrop === 'refuse'
					action = refused ? null : { kind: listDrop, listId: entry.list.id }
				}
			} else if (entry && dragRow && entry.type === 'filter') {
				var dueDay = Tasks.sectionDueDay(entry.key, today)
				if (dueDay !== null && dueDay !== Tasks.dueDay(dragRow.item)) {
					key = 'side:' + entry.key
					action = { kind: 'due', day: dueDay }
				}
			}
			dropKey = key
			dropRefused = refused
			dropAction = action
			return
		}
		var p = rowsColumn.mapFromItem(null, at.x, at.y)
		var loader = rowsColumn.childAt(Math.max(0, Math.min(p.x, rowsColumn.width - 1)), p.y)
		var target = loader ? loader.row : null
		// Between the rows of its own list: a reorder (the line above or below the row).
		if (target && dragRow && canReorder(target)) {
			var above = loader.mapFromItem(null, at.x, at.y).y < loader.height / 2
			var previous = Tasks.reorderPrevious(rows, rowIndex(dragRow.key), rowIndex(target.key), above)
			if (previous !== null) {
				dropKey = 'reorder:' + target.key
				dropRefused = false
				reorderAbove = above
				dropAction = { kind: 'reorder', previous: previous }
				return
			}
		}
		if (target && dragRow) {
			if (byList && target.list) {
				var drop = Tasks.listDrop(dragRow.list.id, target.list.id)
				if (drop !== 'none') {
					key = 'list:' + target.list.id
					refused = drop === 'refuse'
					action = refused ? null : { kind: drop, listId: target.list.id }
				}
			} else if (byDate && target.section) {
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
		} else if (action.kind === 'reorder') {
			var reorderView = tasksView
			eventModel.reorderTask(item, action.previous, function(err) {
				if (err) {
					reorderView.showNotice(i18n("Couldn't move the task"))
				}
			})
		} else if (action.kind === 'transfer') {
			// Another account: the task is made there (title, notes, due day / time, priority,
			// repeat, reminders, subtasks as far as that list takes them), then deleted here.
			var transferView = tasksView
			var fromList = row.list.id
			eventModel.createEventFromData(action.listId, Tasks.restoreBody(item), function(err) {
				if (err) {
					transferView.showNotice(i18n("Couldn't move the task"))
					return
				}
				eventModel.deleteEvent(fromList, item.id, function(delErr) {
					if (delErr) {
						transferView.showNotice(i18n("The task was copied but couldn't be removed from its old list"))
					}
					logic.update()
				})
			})
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

	// The side bar and the task column as one block, centered: on a very wide popup the column
	// stays next to the side bar instead of far to its right.
	RowLayout {
		id: mainRow
		anchors.top: parent.top
		anchors.bottom: parent.bottom
		anchors.margins: Kirigami.Units.smallSpacing
		anchors.horizontalCenter: parent.horizontalCenter
		width: Math.min(parent.width - Kirigami.Units.smallSpacing * 2, tasksView.showSidebar
			? tasksView.sidebarWidth + spacing + tasksView.maxColumnWidth + Kirigami.Units.gridUnit
			: parent.width)
		spacing: tasksView.islands ? appletConfig.cardGap : Kirigami.Units.smallSpacing

		// The filters, when there's room: a side bar (islands: a card as tall as its entries).
		Item {
			id: sidebar
			visible: tasksView.showSidebar
			Layout.preferredWidth: tasksView.sidebarWidth
			Layout.fillHeight: true
			IslandCard {
				width: parent.width
				height: Math.min(parent.height, implicitHeight)
				padding: shown ? Kirigami.Units.smallSpacing * 2 : 0
				Flickable {
					id: sidebarFlick
					implicitHeight: contentHeight
					contentHeight: sidebarColumn.implicitHeight
					clip: contentHeight > height
					boundsBehavior: Flickable.StopAtBounds
					QQC2.ScrollBar.vertical: PlasmaComponents3.ScrollBar {
						policy: sidebarFlick.contentHeight > sidebarFlick.height ? QQC2.ScrollBar.AsNeeded : QQC2.ScrollBar.AlwaysOff
					}
					ColumnLayout {
						id: sidebarColumn
						width: sidebarFlick.width
						spacing: 1
						Repeater {
							model: tasksView.filterEntries
							Loader {
								readonly property var entry: modelData
								Layout.fillWidth: true
								sourceComponent: entry.type === 'separator' ? sidebarSeparatorComponent
									: entry.type === 'group' ? sidebarGroupComponent
									: sidebarEntryComponent
							}
						}
						// "New list": an entry, then the field (Enter makes the list).
						Loader {
							readonly property var entry: ({ type: 'new', key: 'new' })
							Layout.fillWidth: true
							Layout.topMargin: Kirigami.Units.smallSpacing
							active: tasksView.taskAccounts.length > 0 && !tasksView.addingList
							visible: active
							sourceComponent: sidebarEntryComponent
						}
						Loader {
							readonly property bool stacked: true
							Layout.fillWidth: true
							active: tasksView.taskAccounts.length > 0 && tasksView.addingList && tasksView.showSidebar
							visible: active
							sourceComponent: newListComponent
						}
					}
				}
			}
		}
		Kirigami.Separator {
			visible: tasksView.showSidebar && !tasksView.islands
			Layout.fillHeight: true
		}

		ColumnLayout {
			Layout.fillWidth: true
			Layout.fillHeight: true
			spacing: Kirigami.Units.smallSpacing

			// The filter's name and its open count (narrow: a button opening the filters' menu); by date /
			// by list when there's room; "⋯": the view's options.
			Item {
				Layout.fillWidth: true
				implicitHeight: headerRow.implicitHeight
				RowLayout {
					id: headerRow
					x: rowsColumn.x
					width: rowsColumn.width
					spacing: Kirigami.Units.smallSpacing
					readonly property real titleWidth: (tasksView.showSidebar ? titleRow.implicitWidth : filterButton.implicitWidth)
						+ (sidebarToggle.visible ? sidebarToggle.implicitWidth + spacing : 0)
					// By date / by list: only with room for it (else in the "⋯" menu only).
					readonly property bool groupingFits: width - tasksView.sideMargin * 2 - titleWidth - moreButton.implicitWidth
						- spacing * 3 >= groupingControl.implicitWidth

					// Fold / unfold the filters' side bar (only with room for it).
					PlasmaComponents3.ToolButton {
						id: sidebarToggle
						visible: tasksView.sidebarFits
						Layout.leftMargin: tasksView.sideMargin - Kirigami.Units.smallSpacing
						icon.name: tasksView.showSidebar ? "sidebar-collapse-left" : "sidebar-expand-left"
						display: QQC2.AbstractButton.IconOnly
						text: tasksView.showSidebar ? i18n("Hide filters") : i18n("Show filters")
						onClicked: plasmoid.configuration.tasksSidebarCollapsed = tasksView.showSidebar
						PlasmaComponents3.ToolTip.text: text
						PlasmaComponents3.ToolTip.visible: hovered
					}
					RowLayout {
						id: titleRow
						visible: tasksView.showSidebar
						Layout.leftMargin: sidebarToggle.visible ? 0 : tasksView.sideMargin
						Layout.minimumWidth: 0
						Layout.maximumWidth: implicitWidth
						Layout.fillWidth: true
						spacing: Kirigami.Units.smallSpacing
						Kirigami.Heading {
							Layout.alignment: Qt.AlignBaseline
							Layout.minimumWidth: 0
							Layout.maximumWidth: implicitWidth
							Layout.fillWidth: true
							level: 2
							font.weight: Font.Bold
							font.pointSize: tasksView.titlePointSize
							text: tasksView.filterName(tasksView.currentFilter)
							textFormat: Text.PlainText // User text (list name)
							elide: Text.ElideRight
						}
						PlasmaComponents3.Label {
							Layout.alignment: Qt.AlignBaseline
							text: tasksView.currentCount > 0 ? String(tasksView.currentCount) : ""
							textFormat: Text.PlainText
							opacity: tasksView.dimOpacity
							Accessible.name: i18np("%1 open task", "%1 open tasks", tasksView.currentCount)
						}
					}
					PlasmaComponents3.ToolButton {
						id: filterButton
						visible: !tasksView.showSidebar
						Layout.leftMargin: sidebarToggle.visible ? 0 : Math.max(0, tasksView.sideMargin - leftPadding)
						Layout.minimumWidth: 0
						Layout.maximumWidth: implicitWidth
						Layout.fillWidth: true
						text: tasksView.filterName(tasksView.currentFilter)
						Accessible.name: i18nc("%1 = tasks filter or list name", "Show: %1", text)
						Accessible.description: i18np("%1 open task", "%1 open tasks", tasksView.currentCount)
						contentItem: RowLayout {
							spacing: Kirigami.Units.smallSpacing
							Kirigami.Heading {
								Layout.alignment: Qt.AlignBaseline
								Layout.minimumWidth: 0
								Layout.maximumWidth: implicitWidth
								Layout.fillWidth: true
								level: 2
								font.weight: Font.Bold
								font.pointSize: tasksView.titlePointSize
								text: filterButton.text
								textFormat: Text.PlainText // User text (list name)
								elide: Text.ElideRight
							}
							PlasmaComponents3.Label {
								Layout.alignment: Qt.AlignBaseline
								visible: tasksView.currentCount > 0
								text: String(tasksView.currentCount)
								textFormat: Text.PlainText
								opacity: tasksView.dimOpacity
							}
							Kirigami.Icon {
								Layout.alignment: Qt.AlignVCenter
								implicitWidth: Kirigami.Units.iconSizes.small
								implicitHeight: implicitWidth
								source: "arrow-down"
								opacity: tasksView.dimOpacity
							}
						}
						onClicked: filterMenu.popup(filterButton, 0, filterButton.height)
					}
					Item {
						Layout.fillWidth: true
					}
					// By date / by list: a segmented control, the current one on a soft tint (like the
					// popup's view switcher).
					Rectangle {
						id: groupingControl
						visible: headerRow.groupingFits
						implicitWidth: groupingRow.implicitWidth + 4
						implicitHeight: groupingRow.implicitHeight + 4
						radius: Kirigami.Units.cornerRadius + 2
						color: "transparent"
						border.width: 1
						border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.2)
						Row {
							id: groupingRow
							anchors.centerIn: parent
							spacing: 0
							Repeater {
								model: [
									{ key: 'date', icon: "view-calendar-day", text: i18n("By date") },
									{ key: 'list', icon: "view-list-tree", text: i18n("By list") },
								]
								Item {
									readonly property bool current: modelData.key === tasksView.groupBy
									implicitWidth: groupingButton.implicitWidth
									implicitHeight: groupingButton.implicitHeight
									Rectangle {
										anchors.fill: parent
										radius: Kirigami.Units.cornerRadius
										color: Kirigami.Theme.highlightColor
										opacity: parent.current ? 0.18 : 0
									}
									PlasmaComponents3.ToolButton {
										id: groupingButton
										anchors.fill: parent
										icon.name: modelData.icon
										text: modelData.text
										display: QQC2.AbstractButton.TextBesideIcon
										// Not checkable: the style's checked look changes the size.
										onClicked: plasmoid.configuration.tasksGroupBy = modelData.key
										Accessible.role: Accessible.RadioButton
										Accessible.checkable: true
										Accessible.checked: parent.current
										Accessible.name: modelData.text
									}
								}
							}
						}
					}
					// The view's options: group, sort, details, completed, manage lists.
					PlasmaComponents3.ToolButton {
						id: moreButton
						Layout.rightMargin: Math.max(0, tasksView.sideMargin - Kirigami.Units.smallSpacing)
						icon.name: "overflow-menu"
						display: QQC2.AbstractButton.IconOnly
						text: i18n("View options")
						down: pressed || viewMenu.opened
						onClicked: viewMenu.popup(moreButton, moreButton.width - viewMenu.implicitWidth, moreButton.height)
						PlasmaComponents3.ToolTip.text: text
						PlasmaComponents3.ToolTip.visible: hovered && !viewMenu.opened
					}
				}
			}

			PlasmaComponents3.Label {
				visible: !!tasksView.notice
				Layout.fillWidth: true
				Layout.minimumWidth: 0
				Layout.leftMargin: rowsColumn.x + tasksView.sideMargin
				Layout.rightMargin: rowsColumn.x + tasksView.sideMargin
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

				// The column, centered (the scroll bar stays at the view's edge).
				ColumnLayout {
					id: rowsColumn
					x: Math.round((scrollView.availableWidth - width) / 2)
					width: Math.min(scrollView.availableWidth, tasksView.maxColumnWidth)
					spacing: 0

					Repeater {
						model: tasksView.rows
						Loader {
							id: rowLoader
							readonly property var row: modelData
							// Islands: this row's part of its card (Tasks.cardRows), null outside one.
							readonly property var card: tasksView.islands && tasksView.cards[index] && tasksView.cards[index].card ? tasksView.cards[index] : null
							// A heading after rows: a thin line above it (not right after an account's; not
							// in the islands style, the cards are apart).
							readonly property bool separated: !tasksView.islands && index > 0 && tasksView.rows[index - 1].type !== 'group'
							Layout.fillWidth: true
							// A card gap above a card (less right below an account's heading), room below its last row.
							// A card that is only "Add a task…" (no heading above it): the same room above as below,
							// so the row sits centered.
							readonly property real cardTopPadding: card && card.start && card.end && row.type === 'add' ? tasksView.cardEndPadding : 0
							Layout.topMargin: (card && card.start && index > 0 ? (tasksView.rows[index - 1].type === 'group' ? Kirigami.Units.smallSpacing : appletConfig.cardGap) : 0) + cardTopPadding
							// Room below a card's last row; none under a lone heading (a folded card, eg: Completed),
							// which has its own padding around it.
							readonly property real cardBottomPadding: card && card.end && !(card.start && row.type !== 'add') ? tasksView.cardEndPadding : 0
							Layout.bottomMargin: cardBottomPadding
							sourceComponent: row.type === 'group' ? groupComponent
								: row.type === 'list' ? listComponent
								: row.type === 'section' ? sectionComponent
								: row.type === 'empty' ? emptyComponent
								: row.type === 'add' ? addComponent
								: taskComponent
							CardSlice {
								visible: !!rowLoader.card
								y: -rowLoader.cardTopPadding
								height: parent.height + rowLoader.cardTopPadding + rowLoader.cardBottomPadding
								joinTop: !!rowLoader.card && !rowLoader.card.start
								joinBottom: !!rowLoader.card && !rowLoader.card.end
								key: rowLoader.card ? rowLoader.card.key : ""
							}
							// A reorder: a line where the task goes, a dot at its start (like TickTick).
							Item {
								visible: tasksView.dragActive && tasksView.dropKey === 'reorder:' + (rowLoader.row ? rowLoader.row.key : "")
								z: 5
								x: tasksView.sideMargin + (rowLoader.row && rowLoader.row.depth ? rowLoader.row.depth * (tasksView.checkSize + Kirigami.Units.largeSpacing) : 0)
								width: parent.width - x - tasksView.sideMargin
								height: 6
								y: (tasksView.reorderAbove ? 0 : parent.height) - height / 2
								Rectangle {
									anchors.left: parent.left
									anchors.right: parent.right
									anchors.verticalCenter: parent.verticalCenter
									height: 2
									radius: 1
									color: Kirigami.Theme.highlightColor
								}
								Rectangle {
									anchors.verticalCenter: parent.verticalCenter
									width: parent.height
									height: width
									radius: width / 2
									color: Kirigami.Theme.backgroundColor
									border.width: 2
									border.color: Kirigami.Theme.highlightColor
								}
							}
						}
					}
					// By list: "New list" after the lists (islands: in a small card). With the side bar:
					// there instead.
					Loader {
						id: newListLoader
						Layout.fillWidth: true
						Layout.topMargin: tasksView.islands ? appletConfig.cardGap : 0
						Layout.bottomMargin: tasksView.islands ? tasksView.cardEndPadding : 0
						active: tasksView.byList && tasksView.taskAccounts.length > 0 && !tasksView.showSidebar
						visible: active
						sourceComponent: newListComponent
						CardSlice {
							visible: tasksView.islands
							height: parent.height + tasksView.cardEndPadding
						}
					}
					Item {
						implicitHeight: Kirigami.Units.largeSpacing
					}
				}
			}
		}
	}

	// Islands: a row's part of its card, behind the row. A drop going to the card (its header's
	// key): tinted, with a border in the accent color (red when it can't).
	component CardSlice: IslandCard {
		property string key: ""
		readonly property bool targeted: !!key && tasksView.dragActive && tasksView.dropKey === key
		readonly property color dropColor: tasksView.dropRefused ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.highlightColor
		z: -1
		width: parent.width
		padding: 0
		tint: targeted ? Qt.rgba(dropColor.r, dropColor.g, dropColor.b, 0.15) : "transparent"
		borderColor: targeted ? dropColor : appletConfig.cardBorderColor
	}

	// Islands: a card header's fold arrow (the header folds the card).
	component FoldArrow: Kirigami.Icon {
		property bool folded: false
		visible: tasksView.islands
		Layout.alignment: Qt.AlignVCenter
		implicitWidth: Kirigami.Units.iconSizes.small
		implicitHeight: implicitWidth
		source: folded ? (Qt.application.layoutDirection === Qt.RightToLeft ? "arrow-left" : "arrow-right") : "arrow-down"
		opacity: tasksView.dimOpacity
	}

	// A heading's thin line above it, apart from the rows before.
	component SectionSeparator: Kirigami.Separator {
		Layout.fillWidth: true
		Layout.leftMargin: tasksView.sideMargin
		Layout.rightMargin: tasksView.sideMargin
		Layout.topMargin: Kirigami.Units.largeSpacing
		opacity: 0.6
	}

	//--- The side bar's entries (Tasks.filterEntries)
	// A filter or a list: its icon (a list: its color as a dot), name and open count; the current one
	// on the soft tint. A drop target too: a list (moved), Today, Tomorrow, No date (due day).
	// "New list" ({ type: 'new' }) opens the new list field.
	Component {
		id: sidebarEntryComponent
		QQC2.AbstractButton {
			id: sideEntry
			readonly property var entry: parent ? parent.entry : null
			readonly property string key: entry ? entry.key : ""
			readonly property bool isList: !!entry && entry.type === 'list'
			readonly property bool isNew: !!entry && entry.type === 'new'
			readonly property bool current: !isNew && key === tasksView.currentFilter
			readonly property int count: entry && entry.count ? entry.count : 0
			readonly property bool targeted: tasksView.dragActive && tasksView.dropKey === 'side:' + key
			readonly property color dropColor: tasksView.dropRefused ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.highlightColor
			hoverEnabled: true
			leftPadding: Kirigami.Units.smallSpacing * 2
			rightPadding: Kirigami.Units.smallSpacing * 2
			topPadding: Kirigami.Units.smallSpacing + 2
			bottomPadding: Kirigami.Units.smallSpacing + 2
			implicitWidth: implicitContentWidth + leftPadding + rightPadding
			implicitHeight: implicitContentHeight + topPadding + bottomPadding
			text: isNew ? i18n("New list") : isList ? entry.list.name : tasksView.filterName(key)
			Accessible.role: isNew ? Accessible.Button : Accessible.RadioButton
			Accessible.checkable: !isNew
			Accessible.checked: current
			Accessible.name: text
			Accessible.description: isNew ? "" : i18np("%1 open task", "%1 open tasks", count)
			background: Rectangle {
				radius: Kirigami.Units.cornerRadius
				readonly property color tint: sideEntry.targeted ? sideEntry.dropColor : sideEntry.current ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
				color: Qt.rgba(tint.r, tint.g, tint.b, sideEntry.targeted ? 0.2 : sideEntry.current ? 0.18
					: sideEntry.hovered || sideEntry.visualFocus ? 0.07 : 0)
				border.width: sideEntry.targeted ? 1 : 0
				border.color: sideEntry.dropColor
			}
			contentItem: RowLayout {
				spacing: Kirigami.Units.largeSpacing
				Item {
					implicitWidth: Kirigami.Units.iconSizes.small
					implicitHeight: implicitWidth
					Kirigami.Icon {
						anchors.fill: parent
						visible: !sideEntry.isList && !!source
						source: sideEntry.isNew ? "list-add" : tasksView.filterIcon(sideEntry.key)
						color: Kirigami.Theme.textColor
						isMask: true
						opacity: sideEntry.current ? 1 : 0.8
					}
					Rectangle {
						visible: sideEntry.isList
						anchors.centerIn: parent
						width: Math.round(Kirigami.Units.gridUnit * 0.6)
						height: width
						radius: width / 2
						color: sideEntry.isList ? tasksView.listDotColor(sideEntry.entry.list) : "transparent"
					}
				}
				PlasmaComponents3.Label {
					Layout.fillWidth: true
					Layout.minimumWidth: 0
					text: sideEntry.text
					textFormat: Text.PlainText // User text (list name)
					font.weight: sideEntry.current ? Font.DemiBold : Font.Normal
					opacity: sideEntry.isNew && !sideEntry.hovered ? 0.8 : 1
					elide: Text.ElideRight
				}
				PlasmaComponents3.Label {
					visible: sideEntry.count > 0
					text: String(sideEntry.count)
					textFormat: Text.PlainText
					opacity: tasksView.dimOpacity
				}
			}
			onClicked: {
				if (isNew) {
					tasksView.cancelRename()
					tasksView.addingList = true
				} else {
					tasksView.setFilter(key)
				}
			}
		}
	}
	Component {
		id: sidebarSeparatorComponent
		Item {
			readonly property var entry: parent ? parent.entry : null
			implicitHeight: Kirigami.Units.smallSpacing * 2 + 1
			Kirigami.Separator {
				anchors.left: parent.left
				anchors.right: parent.right
				anchors.verticalCenter: parent.verticalCenter
				anchors.leftMargin: Kirigami.Units.smallSpacing * 2
				anchors.rightMargin: Kirigami.Units.smallSpacing * 2
				opacity: 0.6
			}
		}
	}
	// An account's heading (several accounts only).
	Component {
		id: sidebarGroupComponent
		Item {
			readonly property var entry: parent ? parent.entry : null
			implicitHeight: groupLabel.implicitHeight + Kirigami.Units.smallSpacing * 3
			Kirigami.Heading {
				id: groupLabel
				anchors.left: parent.left
				anchors.right: parent.right
				anchors.bottom: parent.bottom
				anchors.bottomMargin: Kirigami.Units.smallSpacing
				anchors.leftMargin: Kirigami.Units.smallSpacing * 2
				anchors.rightMargin: Kirigami.Units.smallSpacing * 2
				level: 5
				text: parent.entry ? parent.entry.text : ""
				textFormat: Text.PlainText // User text (account label)
				opacity: tasksView.dimOpacity
				elide: Text.ElideRight
			}
		}
	}

	// The filters' menu (narrow: on the header's title): the side bar's entries.
	PlasmaComponents3.Menu {
		id: filterMenu
		Instantiator {
			model: tasksView.filterEntries
			delegate: PlasmaComponents3.MenuItem {
				id: filterItem
				readonly property var entry: modelData
				readonly property bool isList: entry.type === 'list'
				readonly property bool isEntry: entry.type === 'filter' || isList
				readonly property bool current: isEntry && entry.key === tasksView.currentFilter
				enabled: isEntry
				text: isList ? entry.list.name : entry.type === 'group' ? entry.text : isEntry ? tasksView.filterName(entry.key) : ""
				leftPadding: Kirigami.Units.smallSpacing * 2
				rightPadding: Kirigami.Units.smallSpacing * 2
				topPadding: entry.type === 'separator' ? 0 : entry.type === 'group' ? Kirigami.Units.smallSpacing * 2 : Kirigami.Units.smallSpacing + 2
				bottomPadding: entry.type === 'separator' ? 0 : Kirigami.Units.smallSpacing + 2
				implicitWidth: implicitContentWidth + leftPadding + rightPadding
				implicitHeight: entry.type === 'separator' ? Kirigami.Units.smallSpacing * 2 + 1 : implicitContentHeight + topPadding + bottomPadding
				contentItem: Item {
					implicitWidth: entry.type === 'separator' ? 0 : itemRow.implicitWidth
					implicitHeight: entry.type === 'separator' ? 1 : itemRow.implicitHeight
					Kirigami.Separator {
						visible: filterItem.entry.type === 'separator'
						anchors.left: parent.left
						anchors.right: parent.right
						anchors.verticalCenter: parent.verticalCenter
					}
					RowLayout {
						id: itemRow
						visible: filterItem.entry.type !== 'separator'
						anchors.fill: parent
						spacing: Kirigami.Units.largeSpacing
						Item {
							visible: filterItem.isEntry
							implicitWidth: Kirigami.Units.iconSizes.small
							implicitHeight: implicitWidth
							Kirigami.Icon {
								anchors.fill: parent
								visible: !filterItem.isList && !!source
								source: filterItem.isList ? "" : tasksView.filterIcon(filterItem.entry.key)
								color: Kirigami.Theme.textColor
								isMask: true
							}
							Rectangle {
								visible: filterItem.isList
								anchors.centerIn: parent
								width: Math.round(Kirigami.Units.gridUnit * 0.6)
								height: width
								radius: width / 2
								color: filterItem.isList ? tasksView.listDotColor(filterItem.entry.list) : "transparent"
							}
						}
						PlasmaComponents3.Label {
							Layout.fillWidth: true
							Layout.minimumWidth: 0
							text: filterItem.text
							textFormat: Text.PlainText // User text (list name, account label)
							font.weight: filterItem.current ? Font.DemiBold : Font.Normal
							opacity: filterItem.entry.type === 'group' ? tasksView.dimOpacity : 1
							elide: Text.ElideRight
						}
						PlasmaComponents3.Label {
							visible: filterItem.isEntry && filterItem.entry.count > 0
							Layout.leftMargin: Kirigami.Units.largeSpacing
							text: String(filterItem.entry.count || 0)
							textFormat: Text.PlainText
							opacity: tasksView.dimOpacity
						}
					}
				}
				background: Rectangle {
					radius: Kirigami.Units.cornerRadius
					readonly property color tint: filterItem.current ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
					color: Qt.rgba(tint.r, tint.g, tint.b, filterItem.current ? 0.18 : filterItem.highlighted ? 0.1 : 0)
				}
				onTriggered: tasksView.setFilter(entry.key)
			}
			onObjectAdded: function(index, object) { filterMenu.insertItem(index, object) }
			onObjectRemoved: function(index, object) { filterMenu.removeItem(object) }
		}
		PlasmaComponents3.MenuSeparator {
			visible: tasksView.taskAccounts.length > 0
			height: visible ? implicitHeight : 0
		}
		PlasmaComponents3.MenuItem {
			visible: tasksView.taskAccounts.length > 0
			height: visible ? implicitHeight : 0
			text: i18n("New list")
			icon.name: "list-add"
			onTriggered: tasksView.startNewList()
		}
	}

	// A choice in the view's menu, checked while current (the binding kept when clicked); one of
	// several (a radio button) unless a toggle.
	component ChoiceItem: PlasmaComponents3.MenuItem {
		id: choice
		property bool current: false
		property bool toggle: false
		checkable: true
		autoExclusive: !toggle
		checked: current
		onToggled: checked = Qt.binding(function() { return choice.current })
	}

	// The view's options ("⋯" in the header).
	PlasmaComponents3.Menu {
		id: viewMenu
		PlasmaComponents3.Menu {
			title: i18n("Group by")
			icon.name: "view-list-tree"
			ChoiceItem {
				text: i18nc("group tasks by", "Date")
				current: tasksView.groupBy === 'date'
				onTriggered: plasmoid.configuration.tasksGroupBy = 'date'
			}
			ChoiceItem {
				text: i18nc("group tasks by", "List")
				current: tasksView.groupBy === 'list'
				onTriggered: plasmoid.configuration.tasksGroupBy = 'list'
			}
			ChoiceItem {
				text: i18nc("group tasks by", "None")
				current: tasksView.groupBy === 'none'
				onTriggered: plasmoid.configuration.tasksGroupBy = 'none'
			}
		}
		PlasmaComponents3.Menu {
			title: i18n("Sort by")
			icon.name: "view-sort"
			ChoiceItem {
				text: i18nc("sort tasks by", "Due date")
				current: tasksView.sortBy === 'due'
				onTriggered: plasmoid.configuration.tasksSortBy = 'due'
			}
			ChoiceItem {
				text: i18nc("sort tasks by", "Title")
				current: tasksView.sortBy === 'title'
				onTriggered: plasmoid.configuration.tasksSortBy = 'title'
			}
			ChoiceItem {
				text: i18nc("sort tasks by", "List order")
				current: tasksView.sortBy === 'list'
				onTriggered: plasmoid.configuration.tasksSortBy = 'list'
			}
			ChoiceItem {
				text: i18nc("sort tasks by", "Priority")
				current: tasksView.sortBy === 'priority'
				onTriggered: plasmoid.configuration.tasksSortBy = 'priority'
			}
		}
		PlasmaComponents3.MenuSeparator {}
		ChoiceItem {
			text: i18n("Show details")
			toggle: true
			icon.name: "view-list-details"
			current: tasksView.showDetails
			onTriggered: plasmoid.configuration.tasksShowDetails = !tasksView.showDetails
		}
		PlasmaComponents3.MenuItem {
			text: tasksView.showCompleted ? i18n("Hide completed") : i18n("Show completed")
			icon.name: "task-complete"
			onTriggered: plasmoid.configuration.tasksShowCompleted = !tasksView.showCompleted
		}
		PlasmaComponents3.MenuSeparator {
			visible: tasksView.taskAccounts.length > 0
			height: visible ? implicitHeight : 0
		}
		// By list, with all the lists: where the list menus are. Again: back to by date.
		ChoiceItem {
			visible: tasksView.taskAccounts.length > 0
			height: visible ? implicitHeight : 0
			text: i18n("Manage lists")
			toggle: true
			icon.name: "configure"
			current: tasksView.byList
			onTriggered: {
				if (tasksView.byList) {
					plasmoid.configuration.tasksGroupBy = 'date'
				} else {
					plasmoid.configuration.tasksGroupBy = 'list'
					tasksView.setFilter('all')
				}
			}
		}
	}

	// "New list" from the filters' menu: by list, all the lists, the field at the end.
	function startNewList() {
		cancelRename()
		if (!showSidebar) {
			plasmoid.configuration.tasksGroupBy = 'list'
			setFilter('all')
		}
		addingList = true
		if (!showSidebar) {
			Qt.callLater(function() {
				var flick = scrollView.contentItem
				if (flick) {
					flick.contentY = Math.max(0, flick.contentHeight - flick.height)
				}
			})
		}
	}

	// "Completed · Undo", at the bottom of the tasks' column.
	TaskUndoBar {
		id: undoBar
		z: 9
		eventModel: tasksView.eventModel
		anchors.horizontalCenter: parent.horizontalCenter
		anchors.horizontalCenterOffset: tasksView.showSidebar ? tasksView.sidebarWidth / 2 : 0
		anchors.bottom: parent.bottom
		anchors.bottomMargin: Kirigami.Units.largeSpacing
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
			showList: tasksView.byList || !tasksView.dragRow ? null : tasksView.taskRowList(tasksView.dragRow)
			showNotes: tasksView.showDetails
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
		ColumnLayout {
			readonly property var row: parent ? parent.row : null
			readonly property bool separated: !!parent && parent.separated
			spacing: 0
			SectionSeparator {
				visible: parent.separated
			}
			Kirigami.Heading {
				Layout.fillWidth: true
				Layout.minimumWidth: 0
				Layout.leftMargin: tasksView.sideMargin
				Layout.rightMargin: tasksView.sideMargin
				Layout.topMargin: Kirigami.Units.largeSpacing
				level: 5
				text: parent.row ? parent.row.text : ""
				textFormat: Text.PlainText // User text (account label)
				opacity: tasksView.dimOpacity
				elide: Text.ElideRight
			}
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
			readonly property bool separated: !!parent && parent.separated
			readonly property real dotSize: Math.round(Kirigami.Units.gridUnit * 0.6)
			implicitHeight: headerColumn.implicitHeight
			// Islands: the header of its card, folds it.
			readonly property bool folded: tasksView.islands && !!row && tasksView.isCollapsed(row.key)
			DropHighlight {
				visible: !tasksView.islands
				x: 0
				y: listRow.y - Kirigami.Units.smallSpacing
				width: parent.width
				height: listRow.height + Kirigami.Units.smallSpacing * 2
				key: row ? row.key : ""
			}
			MouseArea {
				visible: tasksView.islands && !listHeader.renaming
				x: 0
				y: listRow.y
				width: parent.width
				height: listRow.height
				cursorShape: Qt.PointingHandCursor
				onClicked: tasksView.toggleCollapsed(listHeader.row.key)
			}
			// Right click: the list's menu.
			MouseArea {
				id: listRightClick
				x: 0
				y: listRow.y
				width: parent.width
				height: listRow.height
				acceptedButtons: Qt.RightButton
				enabled: !listHeader.renaming && !tasksView.busyListId
				onClicked: function(mouse) { tasksView.openListMenu(listHeader.list, listRightClick, mouse.x, mouse.y) }
			}
			ColumnLayout {
				id: headerColumn
				anchors.left: parent.left
				anchors.right: parent.right
				spacing: 0
				SectionSeparator {
					visible: listHeader.separated
				}
				RowLayout {
					id: listRow
					Layout.fillWidth: true
					Layout.topMargin: Kirigami.Units.largeSpacing
					Layout.bottomMargin: 2
					Layout.rightMargin: Kirigami.Units.smallSpacing
					spacing: 0
					// The dot lined up with the task checks, the name with their titles.
					Rectangle {
						Layout.leftMargin: tasksView.sideMargin + (tasksView.checkSize - listHeader.dotSize) / 2
						Layout.rightMargin: tasksView.titleX - tasksView.sideMargin - (tasksView.checkSize + listHeader.dotSize) / 2
						implicitWidth: listHeader.dotSize
						implicitHeight: implicitWidth
						radius: width / 2
						color: appletConfig.eventColoredTextColor(appletConfig.eventColor(row && row.list.color ? row.list.color : null))
					}
					PlasmaComponents3.Label {
						visible: !listHeader.renaming
						Layout.minimumWidth: 0
						Layout.maximumWidth: Math.ceil(implicitWidth)
						Layout.fillWidth: true
						text: row ? row.list.name : ""
						textFormat: Text.PlainText // User text (list name)
						font.weight: tasksView.islands ? Font.Bold : Font.DemiBold
						font.pointSize: tasksView.islands ? tasksView.cardTitlePointSize : Kirigami.Theme.defaultFont.pointSize
						elide: Text.ElideRight
					}
					PlasmaComponents3.Label {
						visible: !listHeader.renaming && !!row && row.openCount > 0
						Layout.leftMargin: Kirigami.Units.smallSpacing
						text: row ? String(row.openCount) : ""
						textFormat: Text.PlainText
						opacity: tasksView.dimOpacity
					}
					Item {
						visible: !listHeader.renaming
						Layout.fillWidth: true
						Layout.minimumWidth: Kirigami.Units.smallSpacing
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
					// Leaves the rename unsaved (like Esc).
					PlasmaComponents3.ToolButton {
						visible: listHeader.renaming && !listHeader.busy
						icon.name: "dialog-cancel"
						display: QQC2.AbstractButton.IconOnly
						text: i18n("Cancel")
						onClicked: tasksView.cancelRename()
						PlasmaComponents3.ToolTip.text: text
						PlasmaComponents3.ToolTip.visible: hovered
					}
					PlasmaComponents3.BusyIndicator {
						visible: listHeader.busy
						running: visible
						Layout.preferredWidth: Kirigami.Units.iconSizes.small
						Layout.preferredHeight: Kirigami.Units.iconSizes.small
					}
					PlasmaComponents3.ToolButton {
						id: listMenuButton
						// Every list: "Show in smart lists"; rename / color / delete when it can be changed.
						visible: !listHeader.renaming
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
					FoldArrow {
						visible: tasksView.islands && !listHeader.renaming
						Layout.leftMargin: Kirigami.Units.smallSpacing
						Layout.rightMargin: tasksView.sideMargin - Kirigami.Units.smallSpacing
						folded: listHeader.folded
					}
				}
				// Delete: confirmed here first.
				ColumnLayout {
					visible: listHeader.confirming
					Layout.fillWidth: true
					Layout.leftMargin: tasksView.titleX
					Layout.rightMargin: tasksView.sideMargin
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
					Layout.leftMargin: tasksView.titleX
					Layout.rightMargin: tasksView.sideMargin
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
			// In the side bar: narrower margins, the account below the field.
			readonly property bool stacked: !!parent && !!parent.stacked
			readonly property real margin: stacked ? Kirigami.Units.smallSpacing : tasksView.sideMargin
			spacing: 0
			PlasmaComponents3.ToolButton {
				visible: !tasksView.addingList && !newList.stacked
				Layout.topMargin: Kirigami.Units.largeSpacing
				// Its "+" where the checks are.
				Layout.leftMargin: Math.max(0, tasksView.sideMargin + (tasksView.checkSize - icon.width) / 2 - leftPadding)
				icon.name: "list-add"
				icon.width: Kirigami.Units.iconSizes.small
				icon.height: Kirigami.Units.iconSizes.small
				text: i18n("New list")
				opacity: hovered ? 1 : 0.8
				onClicked: {
					tasksView.cancelRename()
					tasksView.addingList = true
				}
			}
			GridLayout {
				visible: tasksView.addingList
				Layout.fillWidth: true
				Layout.topMargin: newList.stacked ? Kirigami.Units.smallSpacing : Kirigami.Units.largeSpacing
				Layout.leftMargin: newList.margin
				Layout.rightMargin: newList.margin
				rowSpacing: Kirigami.Units.smallSpacing
				columnSpacing: Kirigami.Units.smallSpacing
				PlasmaComponents3.TextField {
					id: newListField
					Layout.row: 0
					Layout.column: 0
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
					// Side bar: below the field.
					Layout.row: newList.stacked ? 1 : 0
					Layout.column: newList.stacked ? 0 : 1
					Layout.columnSpan: newList.stacked ? 3 : 1
					Layout.maximumWidth: newList.stacked ? -1 : Kirigami.Units.gridUnit * 9
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
					Layout.row: 0
					Layout.column: newList.stacked ? 1 : 2
					Layout.preferredWidth: Kirigami.Units.iconSizes.small
					Layout.preferredHeight: Kirigami.Units.iconSizes.small
				}
				// Closes the field unsaved (like Esc).
				PlasmaComponents3.ToolButton {
					visible: !newList.busy
					Layout.row: 0
					Layout.column: newList.stacked ? 2 : 3
					icon.name: "dialog-cancel"
					display: QQC2.AbstractButton.IconOnly
					text: i18n("Cancel")
					onClicked: {
						tasksView.addingList = false
						tasksView.newListDraft = ""
					}
					PlasmaComponents3.ToolTip.text: text
					PlasmaComponents3.ToolTip.visible: hovered
				}
			}
			PlasmaComponents3.Label {
				visible: !!newList.errorText
				Layout.fillWidth: true
				Layout.minimumWidth: 0
				Layout.leftMargin: newList.margin
				Layout.rightMargin: newList.margin
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
		// Like TickTick's Someday: the list's tasks only on its own filter, not in All, Today, …
		PlasmaComponents3.MenuItem {
			text: i18n("Show in smart lists")
			icon.name: "view-filter"
			checkable: true
			checked: !!listMenu.list && !tasksView.smartHidden[listMenu.list.id]
			onTriggered: tasksView.setShownInSmartLists(listMenu.list, checked)
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

	// A date section (by date): a thin line above (not the first), its name and count.
	Component {
		id: sectionComponent
		Item {
			id: sectionHeader
			readonly property var row: parent ? parent.row : null
			readonly property string section: row ? row.section : ""
			readonly property bool separated: !!parent && parent.separated
			// Islands: the header of its card, folds it; "Completed" in dim text.
			readonly property bool done: section === 'done'
			readonly property bool folded: tasksView.islands && !!row && tasksView.isCollapsed(row.key)
			implicitHeight: sectionColumn.implicitHeight
			MouseArea {
				visible: tasksView.islands
				anchors.fill: parent
				cursorShape: Qt.PointingHandCursor
				onClicked: tasksView.toggleCollapsed(sectionHeader.row.key)
			}
			DropHighlight {
				visible: !tasksView.islands
				x: 0
				y: sectionRow.y - Kirigami.Units.smallSpacing
				width: parent.width
				height: sectionRow.height + Kirigami.Units.smallSpacing * 2
				key: row ? row.key : ""
			}
			ColumnLayout {
				id: sectionColumn
				anchors.left: parent.left
				anchors.right: parent.right
				spacing: 0
				SectionSeparator {
					visible: sectionHeader.separated
				}
				RowLayout {
					id: sectionRow
					Layout.fillWidth: true
					Layout.leftMargin: tasksView.sideMargin
					Layout.rightMargin: tasksView.sideMargin
					Layout.topMargin: Kirigami.Units.largeSpacing
					Layout.bottomMargin: Kirigami.Units.smallSpacing
					spacing: Kirigami.Units.smallSpacing
					PlasmaComponents3.Label {
						Layout.minimumWidth: 0
						Layout.maximumWidth: Math.ceil(implicitWidth)
						Layout.fillWidth: true
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
						font.weight: tasksView.islands && sectionHeader.done ? Font.Normal : tasksView.islands ? Font.Bold : Font.DemiBold
						font.pointSize: tasksView.islands && !sectionHeader.done ? tasksView.cardTitlePointSize : Kirigami.Theme.defaultFont.pointSize
						color: sectionHeader.section === 'overdue' ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
						opacity: tasksView.islands && sectionHeader.done ? tasksView.dimOpacity : 1
						elide: Text.ElideRight
					}
					PlasmaComponents3.Label {
						visible: !tasksView.islands
						text: sectionHeader.row ? String(sectionHeader.row.count) : ""
						textFormat: Text.PlainText
						color: sectionHeader.section === 'overdue' ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
						opacity: tasksView.dimOpacity
					}
					Item {
						Layout.fillWidth: true
					}
					// Islands: the count and the fold arrow on the right.
					PlasmaComponents3.Label {
						visible: tasksView.islands
						text: sectionHeader.row ? String(sectionHeader.row.count) : ""
						textFormat: Text.PlainText
						color: sectionHeader.section === 'overdue' ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
						opacity: tasksView.dimOpacity
					}
					FoldArrow {
						folded: sectionHeader.folded
					}
				}
			}
		}
	}

	// A list without open tasks: a note lined up with the titles.
	Component {
		id: emptyComponent
		Item {
			readonly property var row: parent ? parent.row : null
			implicitHeight: emptyLabel.implicitHeight + Kirigami.Units.smallSpacing * 2
			PlasmaComponents3.Label {
				id: emptyLabel
				anchors.left: parent.left
				anchors.right: parent.right
				anchors.leftMargin: tasksView.titleX
				anchors.rightMargin: tasksView.sideMargin
				anchors.verticalCenter: parent.verticalCenter
				text: i18n("No open tasks")
				textFormat: Text.PlainText
				opacity: tasksView.dimOpacity
				font.italic: true
				elide: Text.ElideRight
			}
		}
	}

	// "Add a task…" (one, at the top): on the filter's list and due day, else on a picked list.
	Component {
		id: addComponent
		QuickAddTaskRow {
			readonly property var row: parent ? parent.row : null
			eventModel: tasksView.eventModel
			// Without a list of its own: the filter's list and due day (Today, Tomorrow, Next 7 days).
			listId: row && row.list ? row.list.id : tasksView.quickAddTarget.listId
			lists: row && row.list ? [row.list] : tasksView.lists
			dueDay: tasksView.quickAddTarget.dueDay
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
			showList: row && (!tasksView.byList || row.section === 'done') ? tasksView.taskRowList(row) : null
			showNotes: tasksView.showDetails
			sectionDueKind: tasksView.byDate && row && (row.section === 'today' || row.section === 'tomorrow') ? row.section : ""
			depth: row && row.depth ? row.depth : 0
			expandedStore: tasksView.expandedSubtasks
			highlighted: !!row && tasksView.keyRowKey === row.key
			onCheckToggled: function(item, done) { tasksView.offerCompletedUndo(item, done) }
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
