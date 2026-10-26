import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "Tasks.js" as Tasks

// The Tasks tab: every selected task list as a section (grouped by account when there are
// several), open tasks by due day (Tasks.taskRows), then the done ones with "Show completed".
// Each list's "+" opens the task editor on that list, without a due date.
Item {
	id: tasksView

	property var eventModel: null
	readonly property bool showCompleted: !!plasmoid.configuration.tasksShowCompleted
	readonly property string today: Tasks.dayString(timeModel.currentTime)

	property var rows: []
	property int openCount: 0

	function rebuild() {
		if (!eventModel) {
			rows = []
			openCount = 0
			return
		}
		var lists = eventModel.getSelectedTaskLists()
		var itemsByList = {}
		for (var i = 0; i < lists.length; i++) {
			var calendar = eventModel.eventsByCalendar[lists[i].id]
			itemsByList[lists[i].id] = calendar && calendar.items ? calendar.items : []
		}
		var flick = scrollView.contentItem
		var y = flick ? flick.contentY : 0
		var newRows = Tasks.taskRows(lists, itemsByList, showCompleted)
		var count = 0
		for (var j = 0; j < newRows.length; j++) {
			if (newRows[j].type === 'list') {
				count += newRows[j].openCount
			}
		}
		openCount = count
		rows = newRows
		// Toggling a task rebuilds the rows: stay where the list was.
		if (flick) {
			flick.contentY = Math.max(0, Math.min(y, flick.contentHeight - flick.height))
		}
	}
	function deferredRebuild() {
		Qt.callLater(rebuild)
	}
	Component.onCompleted: rebuild()
	onShowCompletedChanged: rebuild()
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

	ColumnLayout {
		anchors.fill: parent
		spacing: Kirigami.Units.smallSpacing

		RowLayout {
			Layout.fillWidth: true
			Layout.leftMargin: Kirigami.Units.smallSpacing
			Layout.rightMargin: Kirigami.Units.smallSpacing
			spacing: Kirigami.Units.smallSpacing

			PlasmaComponents3.Label {
				Layout.fillWidth: true
				Layout.minimumWidth: 0
				text: tasksView.openCount > 0 ? i18np("%1 open task", "%1 open tasks", tasksView.openCount) : i18n("No open tasks")
				textFormat: Text.PlainText
				opacity: 0.7
				elide: Text.ElideRight
			}
			PlasmaComponents3.Switch {
				text: i18n("Show completed")
				checked: tasksView.showCompleted
				onToggled: plasmoid.configuration.tasksShowCompleted = checked
			}
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
				spacing: 2

				Repeater {
					model: tasksView.rows
					Loader {
						readonly property var row: modelData
						Layout.fillWidth: true
						sourceComponent: row.type === 'group' ? groupComponent
							: row.type === 'list' ? listComponent
							: row.type === 'empty' ? emptyComponent
							: taskComponent
					}
				}
				Item {
					implicitHeight: Kirigami.Units.smallSpacing
				}
			}
		}
	}

	// An account's heading (several accounts only).
	Component {
		id: groupComponent
		Kirigami.Heading {
			readonly property var row: parent ? parent.row : null
			topPadding: Kirigami.Units.largeSpacing
			leftPadding: Kirigami.Units.smallSpacing
			level: 5
			text: row ? row.text : ""
			textFormat: Text.PlainText // User text (account label)
			opacity: 0.7
			elide: Text.ElideRight
		}
	}

	// A list: its color, name, open count and "+".
	Component {
		id: listComponent
		RowLayout {
			readonly property var row: parent ? parent.row : null
			spacing: Kirigami.Units.smallSpacing
			Item {
				implicitWidth: Kirigami.Units.smallSpacing
			}
			Rectangle {
				implicitWidth: Math.round(Kirigami.Units.gridUnit * 0.6)
				implicitHeight: implicitWidth
				radius: width / 2
				color: appletConfig.eventColor(row && row.list.color ? row.list.color : null)
			}
			PlasmaComponents3.Label {
				Layout.fillWidth: true
				Layout.minimumWidth: 0
				Layout.topMargin: Kirigami.Units.smallSpacing
				text: row ? row.list.name : ""
				textFormat: Text.PlainText // User text (list name)
				font.weight: Font.DemiBold
				elide: Text.ElideRight
			}
			PlasmaComponents3.Label {
				Layout.topMargin: Kirigami.Units.smallSpacing
				visible: !!row && row.openCount > 0
				text: row ? String(row.openCount) : ""
				textFormat: Text.PlainText
				opacity: 0.6
			}
			PlasmaComponents3.ToolButton {
				icon.name: "list-add"
				display: QQC2.AbstractButton.IconOnly
				text: row ? i18nc("%1 = task list name", "New task in %1", row.list.name) : ""
				onClicked: popup.newTask(null, "", row.list.id)
				PlasmaComponents3.ToolTip.text: text
				PlasmaComponents3.ToolTip.visible: hovered
			}
		}
	}

	Component {
		id: emptyComponent
		PlasmaComponents3.Label {
			readonly property var row: parent ? parent.row : null
			leftPadding: Kirigami.Units.largeSpacing
			bottomPadding: Kirigami.Units.smallSpacing
			text: i18n("No open tasks")
			textFormat: Text.PlainText
			opacity: 0.6
			font.italic: true
		}
	}

	Component {
		id: taskComponent
		TaskRow {
			readonly property var row: parent ? parent.row : null
			eventItem: row ? row.item : null
			today: tasksView.today
		}
	}
}
