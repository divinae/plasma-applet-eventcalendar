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
	// Done / not done: a large button in the accent color, easy to hit.
	QQC2.AbstractButton {
		id: doneButton
		visible: !!(body.item && body.item.canEdit !== false)
		Layout.fillWidth: true
		Layout.leftMargin: Kirigami.Units.largeSpacing
		Layout.rightMargin: Kirigami.Units.largeSpacing
		Layout.topMargin: Kirigami.Units.smallSpacing
		Layout.bottomMargin: Kirigami.Units.largeSpacing
		implicitHeight: Math.round(Kirigami.Units.gridUnit * 2.2)
		hoverEnabled: true
		activeFocusOnTab: true
		text: body.done ? i18n("Mark as not done") : i18n("Mark as done")
		Accessible.name: text
		onClicked: body.details.toggleDone()
		Keys.onSpacePressed: clicked()
		readonly property color accent: body.done ? Kirigami.Theme.textColor : Kirigami.Theme.highlightColor
		background: Rectangle {
			radius: Kirigami.Units.cornerRadius * 2
			color: Qt.rgba(doneButton.accent.r, doneButton.accent.g, doneButton.accent.b,
				doneButton.pressed ? 0.3 : doneButton.hovered ? 0.22 : 0.14)
			border.width: doneButton.visualFocus ? 2 : 1
			border.color: doneButton.visualFocus ? Kirigami.Theme.focusColor : Qt.rgba(doneButton.accent.r, doneButton.accent.g, doneButton.accent.b, 0.45)
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
					color: body.done ? Kirigami.Theme.textColor : Kirigami.Theme.highlightColor
				}
				PlasmaComponents3.Label {
					anchors.verticalCenter: parent.verticalCenter
					text: doneButton.text
					textFormat: Text.PlainText
					font.weight: Font.DemiBold
				}
			}
		}
	}

	// When it's due (red when overdue).
	PropertyRow {
		icon: "view-calendar-day"
		text: body.details ? body.details.dueText : ""
		textColor: body.details && body.details.isOverdue ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
	}
	// Its list, with its color.
	PropertyRow {
		visible: !!body.listName
		dotColor: body.details ? body.details.eventColor : "transparent"
		emoji: body.listSplit.icon
		text: body.listName
	}
	PropertyRow {
		readonly property string key: body.details ? body.details.taskPriority : 'none'
		visible: key !== 'none'
		icon: "flag"
		iconColor: Tasks.priorityColor(key)
		text: key === 'high' ? i18n("High priority") : key === 'medium' ? i18n("Medium priority") : i18n("Low priority")
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
		Layout.fillWidth: true
		Layout.leftMargin: Kirigami.Units.largeSpacing
		Layout.rightMargin: Kirigami.Units.largeSpacing
		Layout.minimumHeight: Kirigami.Units.iconSizes.smallMedium + Kirigami.Units.smallSpacing
		spacing: Kirigami.Units.largeSpacing
		Item {
			Layout.alignment: Qt.AlignVCenter
			implicitWidth: Kirigami.Units.iconSizes.small
			implicitHeight: implicitWidth
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
			Layout.alignment: Qt.AlignVCenter
			wrapMode: Text.Wrap
			textFormat: Text.PlainText
			color: row.textColor
		}
		Item {
			id: trailingArea
			Layout.alignment: Qt.AlignVCenter
			implicitWidth: childrenRect.width
			implicitHeight: childrenRect.height
		}
	}
}
