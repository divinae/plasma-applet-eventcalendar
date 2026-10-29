import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "Guests.js" as Guests
import "Responses.js" as Responses
import "MeetingLink.js" as MeetingLink
import "Shared.js" as Shared
import "Tasks.js" as Tasks

// Right-click menu for an event, the same in every view: details, join, open in Google Calendar,
// respond (RSVP, when invited), email the guests, edit, delete (confirmed in a submenu). One instance lives in
// PopupView (popup.showEventMenu). Tasks: mark as done / not done, in progress, details, edit,
// priority (TickTick), due date, move to another list of the account, delete.
PlasmaComponents3.Menu {
	id: eventMenu

	property var eventItem: null
	readonly property bool isTask: Tasks.isTask(eventItem)
	readonly property bool isDone: isTask && Tasks.isDone(eventItem)
	readonly property var meetingLink: eventItem && !isTask ? MeetingLink.find(eventItem) : null
	readonly property bool canEdit: !!(eventItem && eventItem.canEdit)
	readonly property bool isRecurring: !!(eventItem && eventItem.recurringEventId)
	readonly property var selfAttendee: eventItem ? eventModel.selfAttendee(eventItem) : null
	readonly property bool canRespond: !!eventItem && eventModel.canRespond(eventItem)
	readonly property string response: selfAttendee ? selfAttendee.responseStatus || "" : ""
	readonly property string mailtoUrl: Guests.eventMailtoUrl(eventItem)

	signal showDetails(var eventItem)
	signal editEvent(var eventItem)
	signal duplicateEvent(var eventItem)
	// Delete (wholeSeries: every occurrence). Not popup.deleteWithUndo(): in this Menu, "popup" is
	// its own popup() function, and Delete did nothing.
	signal deleteRequested(var eventItem, bool wholeSeries)

	function openFor(item, parentItem, x, y) {
		eventItem = item
		showRespondMenu(canRespond && !isTask)
		taskLists = isTask && canEdit ? otherTaskLists(item) : []
		var openTask = isTask && canEdit && !isDone
		var caps = isTask ? eventModel.taskCapabilities(item.calendarId) : {}
		// Before Delete, in this order: Priority, Due Date, Move to List.
		showSubMenu(priorityMenu, openTask && !!caps.priority)
		showSubMenu(dueMenu, openTask)
		showSubMenu(moveMenu, taskLists.length > 0)
		showDeleteMenu(canEdit && isRecurring)
		popup(parentItem, x, y)
	}

	//--- Tasks
	function toggleDone() {
		eventModel.toggleTask(eventItem, !isDone)
	}
	// The other task lists of the task's account: [{ id, summary }].
	property var taskLists: []
	function otherTaskLists(item) {
		var id = String(item.calendarId || "")
		var i = id.indexOf('::')
		if (i <= 0 || !eventModel.supportsMove(id)) {
			return []
		}
		return eventModel.getTaskLists(id.slice(0, i)).filter(function(list) { return list.id !== id })
	}
	function moveTask(listId) {
		var appLogic = logic
		eventModel.moveEvent(eventItem.calendarId, eventItem.id, listId, function(err) {
			if (!err) {
				appLogic.update()
			}
		})
	}
	property PlasmaComponents3.Menu moveMenu: PlasmaComponents3.Menu {
		title: i18n("Move to List")
		icon.name: "go-jump"
		Repeater {
			model: eventMenu.taskLists
			PlainMenuItem {
				label: modelData.summary
				onTriggered: eventMenu.moveTask(modelData.id)
			}
		}
	}
	// A task submenu (a submenu can't be hidden): inserted right before Delete when shown, taken out
	// otherwise. Called in their order, so they stay in it.
	function showSubMenu(menu, show) {
		var deleteIndex = -1
		var shownIndex = -1
		for (var i = 0; i < eventMenu.count; i++) {
			var menuItem = eventMenu.itemAt(i)
			if (menuItem === deleteItem) {
				deleteIndex = i
			} else if (menuItem && menuItem.subMenu === menu) {
				shownIndex = i
			}
		}
		if (shownIndex >= 0) {
			eventMenu.takeMenu(shownIndex)
			if (deleteIndex > shownIndex) {
				deleteIndex--
			}
		}
		if (show && deleteIndex >= 0) {
			eventMenu.insertMenu(deleteIndex, menu)
		}
	}

	// The Delete submenu of a repeating event, last in the menu; taken out for other events.
	function showDeleteMenu(show) {
		for (var i = 0; i < eventMenu.count; i++) {
			var menuItem = eventMenu.itemAt(i)
			if (menuItem && menuItem.subMenu === deleteMenu) {
				eventMenu.takeMenu(i)
				break
			}
		}
		if (show) {
			eventMenu.addMenu(deleteMenu)
		}
	}

	// A change of the task (priority, due date): saved, or an error in the popup's banner.
	function saveTask(changes) {
		var shownPopup = popup
		eventModel.setEventProperties(eventItem.calendarId, eventItem.id, Tasks.editBody(changes), {
			done: function(err) {
				if (err && shownPopup) {
					shownPopup.showError(i18n("Couldn't save the task"))
				}
			},
		})
	}

	// Priority (TickTick): high, medium, low, none; the current one checked.
	function setPriority(value) {
		saveTask({ priority: value })
	}
	property PlasmaComponents3.Menu priorityMenu: PlasmaComponents3.Menu {
		title: i18n("Priority")
		icon.name: "flag"
		Repeater {
			model: [
				{ value: Tasks.PRIORITY_HIGH, text: i18n("High priority"), color: Tasks.priorityColor('high') },
				{ value: Tasks.PRIORITY_MEDIUM, text: i18n("Medium priority"), color: Tasks.priorityColor('medium') },
				{ value: Tasks.PRIORITY_LOW, text: i18n("Low priority"), color: Tasks.priorityColor('low') },
				{ value: Tasks.PRIORITY_NONE, text: i18nc("task priority", "No priority"), color: "" },
			]
			PlasmaComponents3.MenuItem {
				id: priorityItem
				readonly property bool current: !!eventMenu.eventItem && Tasks.priorityOf(eventMenu.eventItem) === modelData.value
				text: modelData.text
				Accessible.role: Accessible.RadioButton
				Accessible.checkable: true
				Accessible.checked: current
				// A flag in the priority's color (grey: none), a check after the current one.
				contentItem: RowLayout {
					spacing: Kirigami.Units.smallSpacing
					Kirigami.Icon {
						implicitWidth: Kirigami.Units.iconSizes.small
						implicitHeight: implicitWidth
						source: "flag"
						isMask: true
						color: modelData.color || Kirigami.Theme.disabledTextColor
					}
					PlasmaComponents3.Label {
						Layout.fillWidth: true
						text: priorityItem.text
						textFormat: Text.PlainText
						font: priorityItem.font
						color: priorityItem.highlighted ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
					}
					Kirigami.Icon {
						implicitWidth: Kirigami.Units.iconSizes.small
						implicitHeight: implicitWidth
						source: "checkmark"
						color: priorityItem.highlighted ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
						opacity: priorityItem.current ? 1 : 0
					}
				}
				onTriggered: eventMenu.setPriority(modelData.value)
			}
		}
	}

	// Due date: today, tomorrow, the start of next week, none (the time, if any, is kept).
	function setDue(day) {
		saveTask({ dueDay: day })
	}
	// The start of next week, a week later when that's tomorrow (eg: Sunday, the week from Monday).
	readonly property string nextWeekDay: {
		var day = Tasks.nextWeekStart(today, firstDayOfWeek)
		return day === Tasks.addDays(today, 1) ? Tasks.addDays(day, 7) : day
	}
	readonly property string today: Tasks.dayString(timeModel.currentTime)
	readonly property int firstDayOfWeek: {
		var setting = plasmoid.configuration.firstDayOfWeek
		return setting >= 0 ? setting : Qt.locale().firstDayOfWeek % 7
	}
	property PlasmaComponents3.Menu dueMenu: PlasmaComponents3.Menu {
		title: i18n("Due date")
		icon.name: "view-calendar-upcoming-events"
		Repeater {
			model: [
				{ day: eventMenu.today, text: i18nc("tasks filter", "Today"), icon: "go-jump-today" },
				{ day: Tasks.addDays(eventMenu.today, 1), text: i18nc("tasks filter", "Tomorrow"), icon: "go-next" },
				{ day: eventMenu.nextWeekDay, text: i18n("Next week"), icon: "go-next-skip" },
				{ day: '', text: i18nc("tasks filter", "No date"), icon: "edit-clear" },
			]
			PlasmaComponents3.MenuItem {
				text: modelData.text
				icon.name: modelData.icon
				checkable: true
				checked: !!eventMenu.eventItem && Tasks.dueDay(eventMenu.eventItem) === modelData.day
				onTriggered: {
					checked = Qt.binding(function() { return !!eventMenu.eventItem && Tasks.dueDay(eventMenu.eventItem) === modelData.day })
					eventMenu.setDue(modelData.day)
				}
			}
		}
	}

	// A submenu can't be hidden, so the Respond submenu is only inserted for invitations.
	readonly property int respondMenuIndex: 4 // After "Open in Google Calendar"
	function showRespondMenu(show) {
		var shown = eventMenu.itemAt(respondMenuIndex) && eventMenu.itemAt(respondMenuIndex).subMenu === respondMenu
		if (show && !shown) {
			eventMenu.insertMenu(respondMenuIndex, respondMenu)
		} else if (!show && shown) {
			eventMenu.takeMenu(respondMenuIndex)
		}
	}
	function respond(status, series) {
		eventModel.respondToEvent(eventItem, status, series)
	}

	property PlasmaComponents3.Menu respondMenu: PlasmaComponents3.Menu {
		title: i18nc("RSVP to an invitation", "Respond")
		icon.name: "mail-meeting-request-reply"
		Repeater {
			model: Responses.choices()
			PlasmaComponents3.MenuItem {
				text: modelData.text
				icon.name: modelData.icon
				checkable: true
				checked: eventMenu.response === modelData.status
				onTriggered: {
					checked = Qt.binding(function() { return eventMenu.response === modelData.status }) // Undo the toggle
					eventMenu.respond(modelData.status, false)
				}
			}
		}
		PlasmaComponents3.MenuSeparator {
			visible: eventMenu.isRecurring
			height: visible ? implicitHeight : 0
		}
		Repeater {
			model: Responses.choices()
			PlasmaComponents3.MenuItem {
				visible: eventMenu.isRecurring
				height: visible ? implicitHeight : 0
				text: modelData.seriesText
				icon.name: modelData.icon
				onTriggered: eventMenu.respond(modelData.status, true)
			}
		}
	}
	PlasmaComponents3.MenuItem {
		visible: eventMenu.isTask && eventMenu.canEdit
		height: visible ? implicitHeight : 0
		text: eventMenu.isDone ? i18n("Mark as Not Done") : i18n("Mark as Done")
		icon.name: eventMenu.isDone ? "edit-undo" : "checkmark"
		onTriggered: eventMenu.toggleDone()
	}
	// Kept by the widget only (Google Tasks and TickTick have no such state).
	PlasmaComponents3.MenuItem {
		readonly property bool inProgress: eventMenu.isTask && Tasks.isInProgress(eventMenu.eventItem, plasmoid.configuration.tasksInProgress)
		visible: eventMenu.isTask && !eventMenu.isDone
		height: visible ? implicitHeight : 0
		text: inProgress ? i18n("Mark as Not in Progress") : i18n("Mark as in Progress")
		icon.name: inProgress ? "media-playback-pause" : "media-playback-start"
		onTriggered: eventModel.setTaskInProgress(eventMenu.eventItem, !inProgress)
	}
	PlasmaComponents3.MenuItem {
		text: i18n("Show Details")
		icon.name: "view-calendar-day"
		onTriggered: eventMenu.showDetails(eventMenu.eventItem)
	}
	PlasmaComponents3.MenuItem {
		visible: !!eventMenu.meetingLink
		height: visible ? implicitHeight : 0
		text: eventMenu.meetingLink ? i18nc("%1 = Google Meet, Zoom, ...", "Join %1", eventMenu.meetingLink.label) : ""
		icon.name: "call-start"
		onTriggered: meetingOpener.open(eventMenu.meetingLink.url)
	}
	// The event as text (title, day and time, place, link), like Dato's Copy.
	PlasmaComponents3.MenuItem {
		visible: !!eventMenu.eventItem && !eventMenu.isTask
		height: visible ? implicitHeight : 0
		text: i18n("Copy Event Details")
		icon.name: "edit-copy"
		onTriggered: eventMenu.copyText(eventMenu.detailsText(eventMenu.eventItem))
	}
	PlasmaComponents3.MenuItem {
		visible: !!eventMenu.meetingLink
		height: visible ? implicitHeight : 0
		text: i18n("Copy Meeting Link")
		icon.name: "edit-copy"
		onTriggered: eventMenu.copyText(eventMenu.meetingLink.url)
	}
	// No notifications, clock chip, auto-join or full-screen alert for this one; still in the views.
	PlasmaComponents3.MenuItem {
		readonly property bool muted: !!eventMenu.eventItem && !eventMenu.isTask && upcomingEvents.isMuted(eventMenu.eventItem)
		visible: !!eventMenu.eventItem && !eventMenu.isTask && !!eventMenu.eventItem.startDateTime && !(eventMenu.eventItem.start && eventMenu.eventItem.start.date)
		height: visible ? implicitHeight : 0
		text: muted ? i18n("Unmute Notifications") : i18n("Mute Notifications")
		icon.name: muted ? "notifications" : "notifications-disabled"
		onTriggered: upcomingEvents.setMuted(eventMenu.eventItem, !muted)
	}
	PlasmaComponents3.MenuItem {
		visible: !eventMenu.isTask && !!(eventMenu.eventItem && eventMenu.eventItem.htmlLink)
		height: visible ? implicitHeight : 0
		text: i18n("Open in Google Calendar")
		icon.name: "globe"
		onTriggered: Shared.openExternalUrl(eventMenu.eventItem.htmlLink)
	}
	// A meeting that ended early: no progress in the panel for it.
	PlasmaComponents3.MenuItem {
		visible: !!eventMenu.eventItem && !eventMenu.isTask && upcomingEvents.isOngoing(eventMenu.eventItem)
		height: visible ? implicitHeight : 0
		text: i18n("Mark as Ended")
		icon.name: "dialog-ok"
		onTriggered: upcomingEvents.markEnded(eventMenu.eventItem)
	}
	// Everyone invited except you and rooms, in the mail app.
	PlasmaComponents3.MenuItem {
		visible: !!eventMenu.mailtoUrl
		height: visible ? implicitHeight : 0
		text: i18n("Email Guests…")
		icon.name: "mail-message-new"
		onTriggered: Shared.openMailtoUrl(eventMenu.mailtoUrl)
	}
	PlasmaComponents3.MenuSeparator {} // Edit, Duplicate, Delete
	PlasmaComponents3.MenuItem {
		visible: eventMenu.canEdit
		height: visible ? implicitHeight : 0
		text: i18n("Edit…")
		icon.name: "document-edit"
		onTriggered: eventMenu.editEvent(eventMenu.eventItem)
	}
	// A new event as a copy (also of events you can't edit, eg: on a shared calendar).
	PlasmaComponents3.MenuItem {
		visible: !eventMenu.isTask
		height: visible ? implicitHeight : 0
		text: i18n("Duplicate…")
		icon.name: "edit-copy"
		onTriggered: eventMenu.duplicateEvent(eventMenu.eventItem)
	}
	// Delete: right away (with Undo); a repeating event: a submenu, this one or all of them
	// (deleteMenu, added at the end when it's one).
	PlasmaComponents3.MenuItem {
		id: deleteItem
		visible: eventMenu.canEdit && !eventMenu.isRecurring
		height: visible ? implicitHeight : 0
		text: i18n("Delete")
		icon.name: "edit-delete"
		onTriggered: eventMenu.deleteRequested(eventMenu.eventItem, false)
	}
	property PlasmaComponents3.Menu deleteMenu: PlasmaComponents3.Menu {
		title: i18n("Delete")
		icon.name: "edit-delete"
		PlainMenuItem {
			label: eventMenu.eventItem ? i18nc("%1 = event title", "Delete Only This Occurrence of “%1”", eventMenu.eventItem.summary) : ""
			icon.name: "edit-delete"
			onTriggered: eventMenu.deleteRequested(eventMenu.eventItem, false)
		}
		// Repeating events: the whole series, by its id.
		PlainMenuItem {
			label: eventMenu.eventItem ? i18nc("%1 = event title", "Delete All Events of “%1”", eventMenu.eventItem.summary) : ""
			icon.name: "edit-delete"
			onTriggered: eventMenu.deleteRequested(eventMenu.eventItem, true)
		}
	}
	// "Design review\nThursday, 29 October 2026, 14:00 – 15:00\nRoom 4.12\nhttps://meet…": the event as
	// plain text (all-day: the day, or the days).
	function detailsText(item) {
		var lines = [String(item.summary || '')]
		var allDay = !!(item.start && item.start.date)
		if (allDay) {
			var lastDay = new Date(item.endDateTime.getTime() - 1)
			lines.push(Shared.isSameDate(item.startDateTime, lastDay)
				? Shared.formatDate(item.startDateTime, Locale.LongFormat)
				: Shared.formatDate(item.startDateTime, Locale.LongFormat) + ' – ' + Shared.formatDate(lastDay, Locale.LongFormat))
		} else {
			lines.push(Shared.formatDate(item.startDateTime, Locale.LongFormat) + ', '
				+ Shared.formatTimeRange(item.startDateTime, item.endDateTime, appletConfig.timeFormat))
		}
		if (item.location) {
			lines.push(String(item.location))
		}
		if (meetingLink) {
			lines.push(meetingLink.url)
		}
		return lines.join('\n')
	}
	// Copies text to the clipboard (QML has no clipboard API of its own): a TextEdit made for it,
	// not a child item (a Menu's items are its entries).
	function copyText(text) {
		var edit = Qt.createQmlObject('import QtQuick; TextEdit { visible: false }', eventMenu)
		edit.text = text
		edit.selectAll()
		edit.copy()
		edit.destroy()
	}
}
