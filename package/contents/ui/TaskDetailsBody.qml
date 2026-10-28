import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "LocaleFuncs.js" as LocaleFuncs
import "Shared.js" as Shared
import "TaskLists.js" as TaskLists
import "Tasks.js" as Tasks

// A task's details (EventDetailsView with a task), like TickTick's: the title, a large Mark as done
// button, then
// one row per property with its icon (due, list, priority, in progress with a switch, repeat,
// reminders), the notes in a soft box. The subtasks and Edit / Delete come after it (the card's).
ColumnLayout {
	id: body

	property Item details: null
	readonly property var item: details ? details.eventItem : null
	readonly property bool done: !!details && details.isDone
	readonly property bool canEdit: !!(item && item.canEdit !== false)
	readonly property var caps: item && typeof eventModel !== "undefined" ? eventModel.taskCapabilities(item.calendarId) : ({})

	//--- Changed here, without the editor: the due day, the priority, the list.
	// A change saved, or "Couldn't save the task" in the popup's banner.
	function save(changes) {
		var shownPopup = popup
		eventModel.setEventProperties(item.calendarId, item.id, Tasks.editBody(changes), {
			done: function(err) {
				if (err && shownPopup) {
					shownPopup.showError(i18n("Couldn't save the task"))
				}
			},
		})
	}
	// The other lists of the task's account: [{ id, summary }] (EventModel.getTaskLists).
	readonly property var otherLists: {
		var id = item ? String(item.calendarId || "") : ""
		var i = id.indexOf('::')
		if (i <= 0 || typeof eventModel === "undefined" || !eventModel.supportsMove(id)) {
			return []
		}
		return eventModel.getTaskLists(id.slice(0, i)).filter(function(list) { return list.id !== id })
	}
	function moveTo(listId) {
		var shownDetails = details
		var appLogic = logic
		eventModel.moveEvent(item.calendarId, item.id, listId, function(err) {
			if (err) {
				popup.showError(i18n("Couldn't move the task"))
				return
			}
			appLogic.update()
			shownDetails.closeRequested() // Its copy in the new list has the details now
		})
	}
	readonly property string today: Tasks.dayString(timeModel.currentTime)
	readonly property string nextWeekDay: {
		var setting = plasmoid.configuration.firstDayOfWeek
		var first = setting >= 0 ? setting : Qt.locale().firstDayOfWeek % 7
		var day = Tasks.nextWeekStart(today, first)
		return day === Tasks.addDays(today, 1) ? Tasks.addDays(day, 7) : day
	}

	PlasmaComponents3.Menu {
		id: dueMenu
		Repeater {
			model: [
				{ day: body.today, text: i18nc("tasks filter", "Today"), icon: "go-jump-today" },
				{ day: Tasks.addDays(body.today, 1), text: i18nc("tasks filter", "Tomorrow"), icon: "go-next" },
				{ day: body.nextWeekDay, text: i18n("Next week"), icon: "go-next-skip" },
				{ day: '', text: i18nc("tasks filter", "No date"), icon: "edit-clear" },
			]
			ChoiceItem {
				text: modelData.text
				iconName: modelData.icon
				current: !!body.item && Tasks.dueDay(body.item) === modelData.day
				onTriggered: body.save({ dueDay: modelData.day })
			}
		}
	}
	PlasmaComponents3.Menu {
		id: priorityMenu
		Repeater {
			model: [
				{ value: Tasks.PRIORITY_HIGH, text: i18n("High priority"), key: 'high' },
				{ value: Tasks.PRIORITY_MEDIUM, text: i18n("Medium priority"), key: 'medium' },
				{ value: Tasks.PRIORITY_LOW, text: i18n("Low priority"), key: 'low' },
				{ value: Tasks.PRIORITY_NONE, text: i18nc("task priority", "No priority"), key: 'none' },
			]
			ChoiceItem {
				text: modelData.text
				iconName: "flag"
				iconColor: Tasks.priorityColor(modelData.key) || Kirigami.Theme.disabledTextColor
				current: !!body.item && Tasks.priorityOf(body.item) === modelData.value
				onTriggered: body.save({ priority: modelData.value })
			}
		}
	}
	PlasmaComponents3.Menu {
		id: listMenu
		Instantiator {
			model: body.otherLists
			delegate: ChoiceItem {
				required property var modelData
				// "TickTick - 🏠 Home": the list's part, its emoji as its icon.
				readonly property var split: {
					var parts = String(modelData.summary || "").split(" - ")
					return TaskLists.splitIcon(parts.length > 1 ? parts.slice(1).join(" - ") : String(modelData.summary || ""))
				}
				text: split.name
				emoji: split.icon
				dotColor: appletConfig.eventColoredTextColor(appletConfig.eventColor(modelData.backgroundColor || null))
				onTriggered: body.moveTo(modelData.id)
			}
			onObjectAdded: function(index, object) { listMenu.insertItem(index, object) }
			onObjectRemoved: function(index, object) { listMenu.removeItem(object) }
		}
	}

	// A menu choice like the task menu's: an icon (or an emoji, or a dot), its text (never parsed as
	// HTML), a check after the current one.
	component ChoiceItem: PlasmaComponents3.MenuItem {
		id: choice
		property string iconName: ""
		property color iconColor: Kirigami.Theme.textColor
		property string emoji: ""
		property color dotColor: "transparent"
		property bool current: false
		readonly property color fg: highlighted ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
		Accessible.role: Accessible.RadioButton
		Accessible.checkable: true
		Accessible.checked: current
		contentItem: RowLayout {
			spacing: Kirigami.Units.smallSpacing
			Item {
				Layout.alignment: Qt.AlignVCenter
				implicitWidth: Kirigami.Units.iconSizes.small
				implicitHeight: implicitWidth
				Kirigami.Icon {
					anchors.fill: parent
					visible: !!choice.iconName
					source: choice.iconName
					isMask: true
					color: choice.iconColor === Kirigami.Theme.textColor ? choice.fg : choice.iconColor
				}
				ListMark {
					visible: !choice.iconName
					anchors.centerIn: parent
					list: ({ icon: choice.emoji })
					size: Math.round(Kirigami.Units.gridUnit * 0.5)
					color: choice.dotColor
				}
			}
			PlasmaComponents3.Label {
				Layout.fillWidth: true
				text: choice.text
				textFormat: Text.PlainText
				font: choice.font
				color: choice.fg
			}
			Kirigami.Icon {
				Layout.alignment: Qt.AlignVCenter
				implicitWidth: Kirigami.Units.iconSizes.small
				implicitHeight: implicitWidth
				source: "checkmark"
				isMask: true
				color: choice.fg
				opacity: choice.current ? 1 : 0
			}
		}
	}

	// "Every week", "Every Monday", … (the repeat of TickTick tasks, an RRULE).
	function repeatLabel(rule) {
		var freq = (/FREQ=([A-Z]+)/.exec(rule) || [])[1] || ''
		var interval = Number((/INTERVAL=(\d+)/.exec(rule) || [])[1] || 1)
		var byDay = (/BYDAY=([A-Z,]+)/.exec(rule) || [])[1] || ''
		if (byDay === 'MO,TU,WE,TH,FR') {
			return i18n("Every weekday")
		}
		if (byDay && byDay.indexOf(',') < 0) {
			var codes = ['SU', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA']
			return i18nc("%1 = weekday", "Every %1", Qt.locale().standaloneDayName(codes.indexOf(byDay), Locale.LongFormat))
		}
		switch (freq) {
		case 'DAILY': return interval > 1 ? i18np("Every day", "Every %1 days", interval) : i18n("Daily")
		case 'WEEKLY': return interval > 1 ? i18np("Every week", "Every %1 weeks", interval) : i18n("Weekly")
		case 'MONTHLY': return interval > 1 ? i18np("Every month", "Every %1 months", interval) : i18n("Monthly")
		case 'YEARLY': return interval > 1 ? i18np("Every year", "Every %1 years", interval) : i18n("Yearly")
		}
		return i18n("Repeats")
	}
	// The task's reminders (minutes before it's due), "15 min, 1 h before".
	readonly property string remindersText: {
		var list = item ? Shared.toArray(item.reminders).filter(function(m) { return typeof m === 'number' }) : []
		if (!list.length) {
			return ""
		}
		var parts = list.slice().sort(function(a, b) { return b - a }).map(function(m) {
			return m > 0 ? LocaleFuncs.durationShortFormat(m * 60) : i18nc("reminder at event start", "at start")
		})
		return i18nc("%1 = 10m, 2m", "Reminders: %1 before", parts.join(", "))
	}
	// The list's name without the account ("TickTick - Work" is "Work"), its emoji apart (its icon).
	readonly property var listSplit: {
		var name = details && details.calendar ? String(details.calendar.summary || "") : ""
		var parts = name.split(" - ")
		return TaskLists.splitIcon(parts.length > 1 ? parts.slice(1).join(" - ") : name)
	}
	readonly property string listName: listSplit.name

	spacing: Kirigami.Units.smallSpacing * 1.5

	// The title, like the side cards' titles.
	Kirigami.Heading {
		Layout.fillWidth: true
		Layout.leftMargin: Kirigami.Units.largeSpacing
		Layout.rightMargin: Kirigami.Units.largeSpacing
		level: 1
		font.weight: Font.Bold
		font.pointSize: appletConfig.fontPoints(Kirigami.Theme.defaultFont) * 1.35
		wrapMode: Text.Wrap
		text: body.item ? body.item.summary || "" : ""
		textFormat: Text.PlainText // User text: never parsed as HTML
		font.strikeout: body.done
		opacity: body.done ? 0.7 : 1
	}
	// Done / not done: a large solid button in the accent color, easy to hit (done: a quiet one, to
	// undo).
	QQC2.AbstractButton {
		id: doneButton
		visible: !!(body.item && body.item.canEdit !== false)
		Layout.fillWidth: true
		Layout.leftMargin: Kirigami.Units.largeSpacing
		Layout.rightMargin: Kirigami.Units.largeSpacing
		Layout.topMargin: Kirigami.Units.smallSpacing
		Layout.bottomMargin: Kirigami.Units.largeSpacing
		implicitHeight: Math.round(Kirigami.Units.gridUnit * 2)
		hoverEnabled: true
		activeFocusOnTab: true
		text: body.done ? i18n("Mark as not done") : i18n("Mark as done")
		Accessible.name: text
		onClicked: body.details.toggleDone()
		Keys.onSpacePressed: clicked()
		readonly property color fg: body.done ? Kirigami.Theme.textColor : Kirigami.Theme.highlightedTextColor
		background: Rectangle {
			radius: Kirigami.Units.cornerRadius * 2
			readonly property color base: body.done
				? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08)
				: Kirigami.Theme.highlightColor
			color: doneButton.pressed ? Qt.darker(base, 1.15) : doneButton.hovered ? Qt.lighter(base, 1.08) : base
			border.width: doneButton.visualFocus ? 2 : 0
			border.color: Kirigami.Theme.focusColor
		}
		contentItem: Item {
			Row {
				anchors.centerIn: parent
				spacing: Kirigami.Units.smallSpacing
				Kirigami.Icon {
					anchors.verticalCenter: parent.verticalCenter
					width: Kirigami.Units.iconSizes.small
					height: width
					source: body.done ? "edit-undo" : "checkmark"
					isMask: true
					color: doneButton.fg
				}
				PlasmaComponents3.Label {
					anchors.verticalCenter: parent.verticalCenter
					text: doneButton.text
					textFormat: Text.PlainText
					font.weight: Font.DemiBold
					color: doneButton.fg
				}
			}
		}
	}

	// When it's due (red when overdue); a click: today, tomorrow, next week, none.
	PropertyRow {
		id: dueRow
		icon: "view-calendar-day"
		text: body.details ? body.details.dueText : ""
		textColor: body.details && body.details.isOverdue ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
		editable: body.canEdit && !body.done
		onActivated: dueMenu.popup(dueRow, 0, dueRow.height)
	}
	// Its list, with its color; a click: another list of the account to move it to.
	PropertyRow {
		id: listRow
		visible: !!body.listName
		dotColor: body.details ? body.details.eventColor : "transparent"
		emoji: body.listSplit.icon
		text: body.listName
		editable: body.canEdit && body.otherLists.length > 0
		onActivated: listMenu.popup(listRow, 0, listRow.height)
	}
	// The priority (TickTick; also "No priority", to set one); a click: high, medium, low, none.
	PropertyRow {
		id: priorityRow
		readonly property string key: body.details ? body.details.taskPriority : 'none'
		visible: key !== 'none' || (body.canEdit && !body.done && body.caps.priority)
		icon: "flag"
		iconColor: key === 'none' ? Kirigami.Theme.textColor : Tasks.priorityColor(key)
		text: key === 'high' ? i18n("High priority") : key === 'medium' ? i18n("Medium priority")
			: key === 'low' ? i18n("Low priority") : i18nc("task priority", "No priority")
		textColor: key === 'none' ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.7) : Kirigami.Theme.textColor
		editable: body.canEdit && !body.done && !!body.caps.priority
		onActivated: priorityMenu.popup(priorityRow, 0, priorityRow.height)
	}
	// In progress (the widget's own mark): a switch.
	PropertyRow {
		visible: !body.done
		icon: "media-playback-start"
		text: i18nc("tasks filter", "In progress")
		PlasmaComponents3.Switch {
			checked: !!body.details && body.details.taskInProgress
			onToggled: {
				eventModel.setTaskInProgress(body.item, checked)
				checked = Qt.binding(function() { return !!body.details && body.details.taskInProgress })
			}
			Accessible.name: i18nc("tasks filter", "In progress")
		}
	}
	PropertyRow {
		visible: !!(body.item && body.item.repeatRule)
		icon: "media-playlist-repeat"
		text: body.item && body.item.repeatRule ? body.repeatLabel(body.item.repeatRule) : ""
	}
	PropertyRow {
		visible: !!body.remindersText
		icon: "notifications"
		text: body.remindersText
	}

	// The notes, in a soft box (links open in the browser).
	Rectangle {
		readonly property string notes: body.item && body.item.notes ? String(body.item.notes) : ""
		visible: !!notes
		Layout.fillWidth: true
		Layout.leftMargin: Kirigami.Units.largeSpacing
		Layout.rightMargin: Kirigami.Units.largeSpacing
		Layout.topMargin: Kirigami.Units.smallSpacing
		implicitHeight: notesLabel.implicitHeight + Kirigami.Units.largeSpacing * 2
		radius: Kirigami.Units.cornerRadius * 2
		color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.05)
		PlasmaComponents3.Label {
			id: notesLabel
			anchors.left: parent.left
			anchors.right: parent.right
			anchors.verticalCenter: parent.verticalCenter
			anchors.margins: Kirigami.Units.largeSpacing
			wrapMode: Text.Wrap
			textFormat: Text.RichText
			// Plain-text notes: their line breaks kept (rich text ignores \n).
			text: {
				var notes = parent.notes
				var html = Shared.renderText(notes)
				return /<(br|p|div|li)\b/i.test(notes) ? html : html.replace(/\n/g, '<br>')
			}
			linkColor: Kirigami.Theme.linkColor
			onLinkActivated: function(link) { Shared.openExternalUrl(link) }
		}
	}

	// An icon (or a dot in a color) and a text; a control after it (eg: a switch) goes on the right.
	component PropertyRow: RowLayout {
		id: row
		property string icon: ""
		property color iconColor: Kirigami.Theme.textColor
		property color dotColor: "transparent"
		property string emoji: "" // In place of the dot (a list's emoji)
		property alias text: rowLabel.text
		property color textColor: Kirigami.Theme.textColor
		default property alias trailing: trailingArea.data
		// A click changes it (a menu): a small arrow after the value, a hover background up to it.
		property bool editable: false
		signal activated()

		Layout.fillWidth: true
		Layout.leftMargin: Kirigami.Units.largeSpacing
		Layout.rightMargin: Kirigami.Units.largeSpacing
		Layout.minimumHeight: Kirigami.Units.iconSizes.smallMedium + Kirigami.Units.smallSpacing
		spacing: Kirigami.Units.largeSpacing
		Item {
			Layout.alignment: Qt.AlignVCenter
			implicitWidth: Kirigami.Units.iconSizes.small
			implicitHeight: implicitWidth
			// (Not layout cells: inside the icon's item, spread over the whole row.)
			Rectangle {
				visible: row.editable
				z: -1
				x: -parent.x - Kirigami.Units.smallSpacing
				y: -parent.y
				// Up to the arrow after the value (a dropdown-like chip), not the whole row.
				width: rowArrow.x + rowArrow.width + Kirigami.Units.smallSpacing * 2
				height: row.height
				radius: Kirigami.Units.cornerRadius
				color: rowMouse.containsMouse ? appletConfig.agendaHoverBackground : "transparent"
			}
			MouseArea {
				id: rowMouse
				enabled: row.editable
				x: -parent.x - Kirigami.Units.smallSpacing
				y: -parent.y
				width: rowArrow.x + rowArrow.width + Kirigami.Units.smallSpacing * 2
				height: row.height
				hoverEnabled: true
				cursorShape: Qt.PointingHandCursor
				onClicked: row.activated()
			}
			Kirigami.Icon {
				anchors.fill: parent
				visible: !!row.icon
				source: row.icon
				isMask: true
				color: row.iconColor
				opacity: row.iconColor === Kirigami.Theme.textColor ? 0.75 : 1
			}
			PlasmaComponents3.Label {
				visible: !row.icon && !!row.emoji
				anchors.centerIn: parent
				text: row.emoji
				textFormat: Text.PlainText
			}
			Rectangle {
				visible: !row.icon && !row.emoji
				anchors.centerIn: parent
				width: Math.round(parent.width * 0.7)
				height: width
				radius: width / 2
				color: row.dotColor
			}
		}
		PlasmaComponents3.Label {
			id: rowLabel
			Layout.fillWidth: true
			// Editable: as wide as its text, the arrow right after it.
			Layout.maximumWidth: row.editable ? implicitWidth : -1
			Layout.alignment: Qt.AlignVCenter
			wrapMode: Text.Wrap
			textFormat: Text.PlainText
			color: row.textColor
		}
		Kirigami.Icon {
			id: rowArrow
			visible: row.editable
			Layout.alignment: Qt.AlignVCenter
			Layout.leftMargin: -Kirigami.Units.smallSpacing
			implicitWidth: Math.round(Kirigami.Units.iconSizes.small * 0.75)
			implicitHeight: implicitWidth
			source: "arrow-down"
			isMask: true
			color: Kirigami.Theme.textColor
			opacity: rowMouse.containsMouse ? 0.9 : 0.55
		}
		Item {
			visible: row.editable
			Layout.fillWidth: true
		}
		Item {
			id: trailingArea
			Layout.alignment: Qt.AlignVCenter
			implicitWidth: childrenRect.width
			implicitHeight: childrenRect.height
		}
	}
}
