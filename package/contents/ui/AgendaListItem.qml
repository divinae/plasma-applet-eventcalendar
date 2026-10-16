import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "Shared.js" as Shared

// One agenda day: a header (Today / Tomorrow / date, weather, add button), then the event tiles.
ColumnLayout {
	id: agendaListItem
	readonly property int agendaItemIndex: index
	spacing: Kirigami.Units.smallSpacing
	property var agendaItemEvents: model.events
	property var agendaItemTasks: model.tasks
	property var agendaItemDate: model.date // var: model.date is briefly undefined while delegates are removed.
	property bool agendaItemIsToday: false
	// Past days are dimmed (still clickable).
	opacity: agendaItemDate && timeModel.currentTime && Shared.isPastDay(agendaItemDate, timeModel.currentTime) ? appletConfig.pastOpacity : 1
	function checkIfToday() {
		agendaItemIsToday = timeModel.currentTime && model.date ? Shared.isSameDate(timeModel.currentTime, model.date) : false
	}
	Component.onCompleted: agendaListItem.checkIfToday()
	Connections {
		target: timeModel
		function onLoaded() {
			agendaListItem.checkIfToday()
		}
		function onDateChanged() {
			agendaListItem.checkIfToday()
		}
	}
	property alias tasksRepeater: tasksRepeater
	property alias eventsRepeater: eventsRepeater

	Connections {
		target: agendaModel
		function onPopulatingChanged() {
			if (!agendaModel.populating) {
				agendaListItem.reset()
			}
		}
	}
	function reset() {
		newEventForm.active = false
		agendaListItem.checkIfToday()
	}

	readonly property int eventCount: agendaItemEvents ? agendaItemEvents.count : 0
	readonly property int taskCount: agendaItemTasks ? agendaItemTasks.count : 0

	// Today: index of the first event that hasn't started yet; the "now" line goes before it
	// (eventCount: after the last event). -1 on other days.
	readonly property int nowIndex: {
		if (!agendaItemIsToday || eventCount === 0) {
			return -1
		}
		var now = timeModel.currentTime
		for (var i = 0; i < eventCount; i++) {
			var e = agendaItemEvents.get(i)
			if (e.startDateTime > now) {
				return i
			}
		}
		return eventCount
	}

	readonly property string dayTitle: {
		if (!agendaItemDate) {
			return ""
		}
		var date = Qt.formatDate(agendaItemDate, "ddd, d MMM")
		var now = timeModel.currentTime
		var tomorrow = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1)
		if (agendaItemIsToday) {
			return i18nc("agenda day header, %1 = Fri, 16 Oct", "Today · %1", date)
		} else if (Shared.isSameDate(agendaItemDate, tomorrow)) {
			return i18nc("agenda day header, %1 = Sat, 17 Oct", "Tomorrow · %1", date)
		}
		return date
	}

	component NowLine: RowLayout {
		spacing: Kirigami.Units.smallSpacing
		Rectangle {
			Layout.preferredWidth: 8
			Layout.preferredHeight: 8
			radius: 4
			color: Kirigami.Theme.negativeTextColor
		}
		Rectangle {
			Layout.fillWidth: true
			Layout.preferredHeight: 2
			color: Kirigami.Theme.negativeTextColor
		}
		PlasmaComponents3.Label {
			text: Qt.formatTime(timeModel.currentTime, appletConfig.timeFormat)
			color: Kirigami.Theme.negativeTextColor
			font: Kirigami.Theme.smallFont
		}
	}

	//--- Header
	RowLayout {
		id: dayHeader
		Layout.fillWidth: true
		spacing: Kirigami.Units.smallSpacing

		Kirigami.Heading {
			Layout.fillWidth: true
			level: 4
			font.capitalization: Font.Capitalize
			font.weight: agendaListItem.agendaItemIsToday ? Font.Bold : Font.DemiBold
			color: agendaListItem.agendaItemIsToday ? appletConfig.agendaInProgressColor : Kirigami.Theme.textColor
			elide: Text.ElideRight
			text: agendaListItem.dayTitle
		}

		// Weather
		RowLayout {
			visible: showWeather
			spacing: 2
			Kirigami.Icon {
				source: Shared.symbolicIcon(weatherIcon)
				fallback: weatherIcon
				Layout.preferredWidth: Kirigami.Units.iconSizes.small
				Layout.preferredHeight: Layout.preferredWidth
			}
			PlasmaComponents3.Label {
				text: (Shared.formatTemp(tempHigh) || '?') + ' / ' + (Shared.formatTemp(tempLow) || '?')
				opacity: 0.8
			}
		}

		PlasmaComponents3.ToolButton {
			icon.name: "list-add"
			display: QQC2.AbstractButton.IconOnly
			text: i18n("New Event")
			Layout.preferredHeight: Kirigami.Units.iconSizes.medium
			Layout.preferredWidth: Layout.preferredHeight
			onClicked: newEventForm.active = !newEventForm.active
			PlasmaComponents3.ToolTip.text: text
			PlasmaComponents3.ToolTip.visible: hovered
		}
	}

	Kirigami.Separator {
		Layout.fillWidth: true
	}

	//--- Content
	NewEventForm {
		id: newEventForm
		Layout.fillWidth: true
	}

	ColumnLayout {
		id: eventsLayout
		spacing: appletConfig.agendaEventSpacing + Kirigami.Units.smallSpacing
		Layout.fillWidth: true

		Repeater {
			id: eventsRepeater
			model: agendaItemEvents

			delegate: ColumnLayout {
				Layout.fillWidth: true
				spacing: eventsLayout.spacing
				NowLine {
					visible: index === agendaListItem.nowIndex
					Layout.fillWidth: true
				}
				AgendaEventItem {
					Layout.fillWidth: true
				}
			}
		}
		NowLine {
			visible: agendaListItem.nowIndex === agendaListItem.eventCount && agendaListItem.eventCount > 0
			Layout.fillWidth: true
		}

		Repeater {
			id: tasksRepeater
			model: agendaItemTasks

			delegate: AgendaTaskItem {
				id: agendaTaskItem
				width: parent.width
			}
		}

		PlasmaComponents3.Label {
			visible: agendaListItem.eventCount + agendaListItem.taskCount === 0 && !newEventForm.active
			text: i18n("No events")
			opacity: 0.6
		}
	}

	// Space before the next day
	Item {
		Layout.preferredHeight: Kirigami.Units.largeSpacing
	}

	// Y of the event / task at index, relative to this day item.
	function getEventOffset(index) {
		if (index < eventCount) {
			var item = eventsRepeater.itemAt(index)
			return item ? item.mapToItem(agendaListItem, 0, 0).y : eventsLayout.y
		}
		var task = tasksRepeater.itemAt(index - eventCount)
		return task ? task.mapToItem(agendaListItem, 0, 0).y : eventsLayout.y
	}
}
