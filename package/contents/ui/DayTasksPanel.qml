import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "Tasks.js" as Tasks

// The Day view's tasks (Tasks.dayTasks): due on the shown day, and on today the open overdue and
// undated ones too, as compact TaskRows under a "Tasks" heading with a "+" for a task due that
// day. Hidden without task lists. Collapsible: a strip that folds to its heading (above the
// hour grid); otherwise always open (beside the grid, over the weather).
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
	property var tasks: []
	readonly property int openCount: tasks.filter(function(t) { return !Tasks.isDone(t) }).length

	visible: hasLists
	spacing: 2

	function rebuild() {
		var lists = eventModel ? eventModel.getSelectedTaskLists() : []
		var items = []
		for (var i = 0; i < lists.length; i++) {
			var calendar = eventModel.eventsByCalendar[lists[i].id]
			if (calendar && calendar.items) {
				items = items.concat(calendar.items)
			}
		}
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
		target: dayTasks.eventModel
		function onCalendarFetched(calendarId, data) { dayTasks.deferredRebuild() }
		function onAllDataFetched() { dayTasks.deferredRebuild() }
		function onDataCleared() { dayTasks.deferredRebuild() }
		function onEventAdded(calendarId, data) { dayTasks.deferredRebuild() }
		function onEventRemoved(calendarId, eventId, data) { dayTasks.deferredRebuild() }
		function onEventUpdated(calendarId, eventId, data) { dayTasks.deferredRebuild() }
	}

	// Heading: (fold arrow) "Tasks", the open count, "+".
	RowLayout {
		Layout.fillWidth: true
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
		// Like the weather panel's section titles.
		PlasmaComponents3.Label {
			Layout.leftMargin: dayTasks.collapsible ? 0 : Kirigami.Units.smallSpacing
			text: i18n("Tasks")
			textFormat: Text.PlainText
			font.weight: Font.DemiBold
			opacity: 0.7
			MouseArea {
				anchors.fill: parent
				enabled: dayTasks.collapsible
				onClicked: dayTasks.expanded = !dayTasks.expanded
			}
		}
		PlasmaComponents3.Label {
			Layout.leftMargin: Kirigami.Units.smallSpacing
			visible: dayTasks.openCount > 0
			text: String(dayTasks.openCount)
			textFormat: Text.PlainText
			font.weight: Font.DemiBold
			opacity: 0.45
		}
		Item {
			Layout.fillWidth: true
		}
		PlasmaComponents3.ToolButton {
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
		opacity: 0.6
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
			spacing: 0
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

	// Apart from what follows (the weather beside the grid, the hours below the strip).
	Kirigami.Separator {
		Layout.fillWidth: true
		Layout.topMargin: Kirigami.Units.smallSpacing
		Layout.bottomMargin: Kirigami.Units.smallSpacing
	}
}
