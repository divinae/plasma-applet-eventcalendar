import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "Shared.js" as Shared
import "Tasks.js" as Tasks
import "QuickParse.js" as QuickParse

// Quick add: one line like "Lunch with Anna tomorrow 13:00". Google Calendar reads the day,
// time and place from the text; for other calendars QuickParse.js finds the day and time in it
// (an hour long event at that time, else all-day) and the rest is the title.
Item {
	id: quickAdd

	property date date: new Date() // The selected day
	signal closeRequested()
	signal moreOptionsRequested(string title, string calendarId, bool isTasklist)
	signal newTaskRequested(string title)

	readonly property string text: textField.text.trim()
	readonly property bool isToday: Shared.isSameDate(date, new Date())
	readonly property bool canAdd: text.length > 0 && !!calendarSelector.selectedCalendarId
	// A task list picked: the text is the title of a task due on the selected day.
	readonly property bool addsTask: calendarSelector.selectedIsTasklist
	property bool hasTaskLists: false
	// The day and time in the text, for a calendar that doesn't read them itself (not Google).
	readonly property var parsedEvent: {
		var id = calendarSelector.selectedCalendarId
		if (!text || !id || addsTask || typeof eventModel.readsQuickAddText !== "function" || eventModel.readsQuickAddText(id)) {
			return null
		}
		var parsed = QuickParse.parse(text, {
			today: Tasks.dayString(new Date()),
			kinds: ['date', 'time'],
			dayFirst: appletConfig.quickParseLocale.dayFirst,
			dayNames: appletConfig.quickParseLocale.dayNames,
			monthNames: appletConfig.quickParseLocale.monthNames,
		})
		return parsed.tokens.length ? parsed : null
	}
	// The day the event goes on: the one in the text, else the selected one.
	readonly property date eventDay: {
		if (parsedEvent && parsedEvent.dueDay) {
			var parts = parsedEvent.dueDay.split('-')
			return new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
		}
		return date
	}

	implicitHeight: actionsRow.implicitHeight + Kirigami.Units.smallSpacing * 2 + 1
		+ fieldsColumn.implicitHeight + Kirigami.Units.largeSpacing * 2

	function add() {
		if (!canAdd) {
			textField.forceActiveFocus()
			return
		}
		if (addsTask) {
			var body = Object.assign({ title: text }, Tasks.editBody({ dueDay: Shared.localeDateString(date) }))
			eventModel.createEventFromData(calendarSelector.selectedCalendarId, body, null)
		} else if (parsedEvent) {
			eventModel.createEvent(calendarSelector.selectedCalendarId, eventDay, parsedEvent.title || text, parsedEvent.dueTime)
		} else {
			// Today: no date, so "tomorrow" or "Friday" in the text count from today.
			// Another selected day: the event goes on that day unless the text says otherwise.
			eventModel.createEvent(calendarSelector.selectedCalendarId, isToday ? null : date, text)
		}
		closeRequested()
	}

	Keys.onEscapePressed: closeRequested()
	Component.onCompleted: {
		// Calendars, then the task lists (named as such).
		var all = eventModel.getCalendarList()
		var calendars = all.filter(function(c) { return !c.isTasklist })
		var taskLists = all.filter(function(c) { return c.isTasklist }).map(function(c) {
			return Object.assign({}, c, { summary: i18nc("%1 = task list name", "%1 (tasks)", c.summary) })
		})
		hasTaskLists = taskLists.length > 0
		// The last calendar used, unless that's a task list: events first.
		var lastId = plasmoid.configuration.agendaNewEventLastCalendarId
		var initialId = calendars.some(function(c) { return c.id === lastId }) ? lastId : ""
		calendarSelector.populate(calendars.concat(taskLists), initialId)
		textField.forceActiveFocus()
	}

	ColumnLayout {
		anchors.fill: parent
		spacing: 0

		// Cancel on the left, title centered, Add on the right.
		CardHeader {
			id: actionsRow
			Layout.fillWidth: true
			Layout.margins: Kirigami.Units.smallSpacing
			title: i18n("Quick Add")
			actionText: i18n("Add")
			actionIcon: "list-add"
			actionEnabled: quickAdd.canAdd
			onCancelClicked: quickAdd.closeRequested()
			onActionClicked: quickAdd.add()
		}

		Kirigami.Separator {
			Layout.fillWidth: true
		}

		ColumnLayout {
			id: fieldsColumn
			Layout.fillWidth: true
			Layout.margins: Kirigami.Units.largeSpacing
			spacing: Kirigami.Units.largeSpacing

			PlasmaComponents3.TextField {
				id: textField
				Layout.fillWidth: true
				placeholderText: i18nc("quick add example", "Lunch with Anna tomorrow 13:00")
				font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.3
				onAccepted: quickAdd.add()
				Keys.onEscapePressed: quickAdd.closeRequested()
			}

			PlasmaComponents3.Label {
				Layout.fillWidth: true
				wrapMode: Text.Wrap
				opacity: 0.6
				font: Kirigami.Theme.smallFont
				textFormat: Text.PlainText
				text: quickAdd.addsTask
					? i18nc("%1 = date", "The task is due on %1.", Qt.formatDate(quickAdd.date, Qt.locale().dateFormat(Locale.LongFormat)))
					: quickAdd.parsedEvent && quickAdd.parsedEvent.dueTime
					? i18nc("%1 = date, %2 = time", "The event is added on %1 at %2.",
						Qt.formatDate(quickAdd.eventDay, Qt.locale().dateFormat(Locale.LongFormat)),
						Qt.formatTime(new Date(2000, 0, 1, Number(quickAdd.parsedEvent.dueTime.substring(0, 2)), Number(quickAdd.parsedEvent.dueTime.substring(3, 5))), appletConfig.timeFormat))
					: quickAdd.parsedEvent
					? i18nc("%1 = date", "The event is added on %1, all day.", Qt.formatDate(quickAdd.eventDay, Qt.locale().dateFormat(Locale.LongFormat)))
					: quickAdd.isToday
					? i18n("Type what, when and where. Without a day, the event is added today.")
					: i18nc("%1 = date", "Type what, when and where. Without a day, the event is added on %1.",
						Qt.formatDate(quickAdd.date, Qt.locale().dateFormat(Locale.LongFormat)))
			}

			CalendarSelector {
				id: calendarSelector
				Layout.fillWidth: true
			}

			RowLayout {
				Layout.fillWidth: true
				Item { Layout.fillWidth: true }
				PlasmaComponents3.ToolButton {
					visible: quickAdd.hasTaskLists && !quickAdd.addsTask
					icon.name: "view-task-add"
					text: i18n("New Task…")
					onClicked: quickAdd.newTaskRequested(quickAdd.text)
				}
				PlasmaComponents3.ToolButton {
					icon.name: "document-edit"
					text: i18n("More options…")
					onClicked: quickAdd.moreOptionsRequested(quickAdd.text, calendarSelector.selectedCalendarId || "", quickAdd.addsTask)
				}
			}
		}
	}
}
