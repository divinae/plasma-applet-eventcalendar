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
// (beside the grid, right of it).
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
			var calendar = eventModel.eventsByCalendar[lists[i].id]
			if (calendar && calendar.items) {
				items = items.concat(calendar.items)
			}
		}
		dayTasks.lists = lists
		hasLists = lists.length > 0
		tasks = Tasks.dayTasks(items, dayText, today)
	}
	function deferredRebuild() {
		Qt.callLater(rebuild)
	}
	Component.onCompleted: rebuild()
	onDayTextChanged: deferredRebuild()
	onTodayChanged: deferredRebuild()
	onEventModelChanged: deferredRebuild()
	Connections {
		target: plasmoid.configuration
		function onDayTasksListIdChanged() { dayTasks.deferredRebuild() }
	}

	Connections {
		target: dayTasks.eventModel
		function onCalendarFetched(calendarId, data) { dayTasks.deferredRebuild() }
		function onAllDataFetched() { dayTasks.deferredRebuild() }
		function onDataCleared() { dayTasks.deferredRebuild() }
		function onEventAdded(calendarId, data) { dayTasks.deferredRebuild() }
		function onEventRemoved(calendarId, eventId, data) { dayTasks.deferredRebuild() }
		function onEventUpdated(calendarId, eventId, data) { dayTasks.deferredRebuild() }
	}

	// Heading: (fold arrow) "Tasks", the list filter, the open count, "+".
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
		// Islands: like the Tasks tab's card titles (bold, a bit larger, the count on the right).
		// Flat: like the weather panel's section titles.
		PlasmaComponents3.Label {
			Layout.leftMargin: dayTasks.collapsible || appletConfig.islands ? 0 : Kirigami.Units.smallSpacing
			text: i18n("Tasks")
			textFormat: Text.PlainText
			font.weight: Font.DemiBold
			font.pointSize: appletConfig.islands ? appletConfig.fontPoints(Kirigami.Theme.defaultFont) * 1.05 : Kirigami.Theme.defaultFont.pointSize
			opacity: appletConfig.islands ? 1 : 0.85
			MouseArea {
				anchors.fill: parent
				enabled: dayTasks.collapsible
				onClicked: dayTasks.expanded = !dayTasks.expanded
			}
		}
		PlasmaComponents3.Label {
			visible: !appletConfig.islands && dayTasks.openCount > 0
			Layout.leftMargin: Kirigami.Units.smallSpacing
			text: String(dayTasks.openCount)
			textFormat: Text.PlainText
			font.weight: Font.DemiBold
			opacity: 0.65
		}
		Item {
			Layout.fillWidth: true
		}
		// The list filter: all lists or one (several lists only), on the right before the count.
		PlasmaComponents3.ToolButton {
			id: listFilterButton
			visible: dayTasks.lists.length > 1
			Layout.minimumWidth: 0
			Layout.maximumWidth: Kirigami.Units.gridUnit * 9
			text: dayTasks.filterList ? dayTasks.filterList.name : i18n("All lists")
			icon.name: "view-filter"
			icon.width: Kirigami.Units.iconSizes.small
			icon.height: Kirigami.Units.iconSizes.small
			display: QQC2.AbstractButton.TextBesideIcon
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
				delegate: PlasmaComponents3.MenuItem {
					required property var modelData
					text: modelData.name
					checkable: true
					checked: dayTasks.filterListId === modelData.id
					onTriggered: plasmoid.configuration.dayTasksListId = modelData.id
				}
				onObjectAdded: function(index, object) { listFilterMenu.insertItem(index + 2, object) }
				onObjectRemoved: function(index, object) { listFilterMenu.removeItem(object) }
			}
		}
		PlasmaComponents3.Label {
			visible: appletConfig.islands && dayTasks.openCount > 0
			// Lined up with the rows' dates.
			Layout.rightMargin: Kirigami.Units.smallSpacing * 2
			text: String(dayTasks.openCount)
			textFormat: Text.PlainText
			opacity: 0.65
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
		visible: dayTasks.open && dayTasks.tasks.length === 0
		Layout.fillWidth: true
		Layout.leftMargin: Kirigami.Units.smallSpacing
		text: i18n("No tasks")
		textFormat: Text.PlainText
		opacity: 0.75
		elide: Text.ElideRight
	}

	PlasmaComponents3.ScrollView {
		id: scrollView
		visible: dayTasks.open && dayTasks.tasks.length > 0
		Layout.fillWidth: true
		Layout.preferredHeight: Math.min(taskColumn.implicitHeight, dayTasks.maxListHeight)
		contentWidth: availableWidth
		QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

		ColumnLayout {
			id: taskColumn
			width: scrollView.availableWidth
			spacing: 1
			Repeater {
				model: dayTasks.tasks
				TaskRow {
					Layout.fillWidth: true
					eventItem: modelData
					today: dayTasks.today
					compact: true
				}
			}
		}
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

	// Apart from what follows (the hours below the strip). Not in the islands style: the card's edge is.
	property bool showSeparator: true
	Kirigami.Separator {
		visible: dayTasks.showSeparator && !appletConfig.islands
		Layout.fillWidth: true
		Layout.topMargin: Kirigami.Units.smallSpacing
		Layout.bottomMargin: Kirigami.Units.smallSpacing
	}
}
