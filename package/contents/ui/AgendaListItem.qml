import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "Shared.js" as Shared
import "Tasks.js" as Tasks

// One agenda day: a header (Today / Tomorrow / date, weather, add button), then the event tiles.
// Islands style: the day is a card (today's with a border in the accent color).
IslandCard {
	id: agendaListItem
	readonly property int agendaItemIndex: index
	property var agendaItemEvents: model.events
	property var agendaItemTasks: model.tasks
	property var agendaItemDate: model.date // var: model.date is briefly undefined while delegates are removed.
	readonly property bool agendaItemIsToday: !!agendaItemDate && !!timeModel.currentTime && Shared.isSameDate(timeModel.currentTime, agendaItemDate)
	borderColor: agendaItemIsToday ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.6) : appletConfig.cardBorderColor
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
	}

	readonly property int eventCount: agendaItemEvents ? agendaItemEvents.count : 0
	readonly property int taskCount: agendaItemTasks ? agendaItemTasks.count : 0

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

	ColumnLayout {
		id: dayColumn
		spacing: Kirigami.Units.smallSpacing
		// Past days are dimmed (still clickable); in the islands style the card's content.
		opacity: agendaListItem.agendaItemDate && timeModel.currentTime && Shared.isPastDay(agendaListItem.agendaItemDate, timeModel.currentTime) ? appletConfig.pastOpacity : 1

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

			// Google working location ("Home", "Office", ...)
			WorkingLocationLabel {
				date: agendaListItem.agendaItemDate
				maxWidth: Kirigami.Units.gridUnit * 8
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

			// New event (the inline form), or with task lists, a choice of event or task.
			PlasmaComponents3.ToolButton {
				id: addButton
				icon.name: "list-add"
				display: QQC2.AbstractButton.IconOnly
				text: i18n("New Event")
				Layout.preferredHeight: Kirigami.Units.iconSizes.medium
				Layout.preferredWidth: Layout.preferredHeight
				onClicked: {
					if (!newEventForm.active && popup.hasTaskLists()) {
						addMenu.popup(addButton, 0, addButton.height)
					} else {
						newEventForm.active = !newEventForm.active
					}
				}
				PlasmaComponents3.ToolTip.text: text
				PlasmaComponents3.ToolTip.visible: hovered && !addMenu.visible
			}
			PlasmaComponents3.Menu {
				id: addMenu
				PlasmaComponents3.MenuItem {
					text: i18n("New Event")
					icon.name: "view-calendar-day"
					onTriggered: newEventForm.active = true
				}
				PlasmaComponents3.MenuItem {
					text: i18n("New Task…")
					icon.name: "view-task-add"
					onTriggered: popup.newTask(agendaListItem.agendaItemDate, "")
				}
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

				delegate: AgendaEventItem {
					Layout.fillWidth: true
				}
			}

			Repeater {
				id: tasksRepeater
				model: agendaItemTasks

				// The same row as the Tasks tab and the Day view.
				delegate: TaskRow {
					required property int index
					Layout.fillWidth: true
					eventItem: agendaItemTasks.get(index)
					today: Tasks.dayString(timeModel.currentTime)
					// One line: the day heading already says when; only an overdue date is shown.
					compact: true
				}
			}

			PlasmaComponents3.Label {
				visible: agendaListItem.eventCount + agendaListItem.taskCount === 0 && !newEventForm.active
				text: i18n("No events")
				opacity: 0.6
			}
		}

		// Space before the next day (islands: the card's padding)
		Item {
			visible: !agendaListItem.shown
			Layout.preferredHeight: Kirigami.Units.largeSpacing
		}
	}

	// Y of the event / task at index, relative to this day item.
	function getEventOffset(index) {
		if (index < eventCount) {
			var item = eventsRepeater.itemAt(index)
			return item ? item.mapToItem(agendaListItem, 0, 0).y : eventsLayout.mapToItem(agendaListItem, 0, 0).y
		}
		var task = tasksRepeater.itemAt(index - eventCount)
		return task ? task.mapToItem(agendaListItem, 0, 0).y : eventsLayout.mapToItem(agendaListItem, 0, 0).y
	}
}
