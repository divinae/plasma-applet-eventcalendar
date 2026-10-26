import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "Tasks.js" as Tasks

// A task as a list row (Tasks view, Day view), like a to-do app rather than an event tile: its done
// check in the list's color, the title in the theme's text color, when it's due (red when overdue)
// and the first line of its notes. Click opens it, right click the shared event menu; the check
// marks it done / not done. Done ones are dimmed and struck through.
LinkRect {
	id: taskRow

	property var eventItem: null
	// Today, 'YYYY-MM-DD': for "Today", "Tomorrow" and "Overdue".
	property string today: Tasks.dayString(new Date())
	// One line: the due date after the title (only when overdue), no notes (Day view).
	property bool compact: false

	readonly property EventStyle eventStyle: EventStyle {
		eventItem: taskRow.eventItem
	}
	// The list's color, made darker when pale (light theme) so the check stands out.
	readonly property color listColor: appletConfig.eventBarColor(eventStyle.color)
	readonly property bool overdue: due.kind === 'overdue' && !eventStyle.done
	readonly property var due: {
		var parts = today.split('-')
		return Tasks.dueInfo(eventItem, new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]), 12))
	}
	readonly property string dueDateText: {
		if (!due.day) {
			return ""
		}
		var parts = due.day.split('-')
		var date = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
		return Qt.formatDate(date, i18nc("short month+date format", "MMM d"))
	}
	readonly property string dueText: {
		switch (due.kind) {
			case 'today': return i18n("Today")
			case 'tomorrow': return i18n("Tomorrow")
			case 'overdue': return i18nc("%1 = short date", "Overdue · due %1", dueDateText)
			case 'date': return dueDateText
		}
		return ""
	}
	readonly property string notesLine: compact || !eventItem ? "" : Tasks.firstLine(eventItem.notes || eventItem.description || "")
	readonly property string title: eventItem ? (eventItem.summary || eventItem.title || "") : ""

	activeFocusOnTab: true
	Accessible.role: Accessible.Button
	Accessible.name: title || i18n("Task")
	Accessible.description: [eventStyle.done ? i18n("Done") : i18n("Not done"), dueText].filter(function(t) { return !!t }).join(". ")
	Accessible.onPressAction: open()
	Keys.onReturnPressed: open()
	Keys.onEnterPressed: open()
	Keys.onSpacePressed: taskCheck.toggle()
	function open() {
		popup.activateEvent(eventItem)
	}

	radius: 6
	backgroundColor: "transparent"
	backgroundHoverColor: appletConfig.agendaHoverBackground
	implicitWidth: contents.implicitWidth + Kirigami.Units.smallSpacing * 2
	implicitHeight: contents.implicitHeight + (compact ? Kirigami.Units.smallSpacing : Kirigami.Units.smallSpacing * 2)

	RowLayout {
		id: contents
		anchors.left: parent.left
		anchors.right: parent.right
		anchors.verticalCenter: parent.verticalCenter
		anchors.leftMargin: Kirigami.Units.smallSpacing
		anchors.rightMargin: Kirigami.Units.smallSpacing
		spacing: Kirigami.Units.smallSpacing + 2
		opacity: taskRow.eventStyle.doneOpacity

		TaskCheck {
			id: taskCheck
			Layout.alignment: Qt.AlignTop
			Layout.topMargin: Math.max(0, (titleLabel.implicitHeight - height) / 2)
			size: 2 * Math.round(Math.min(Kirigami.Units.iconSizes.small * 1.1, titleLabel.implicitHeight) / 2)
			eventItem: taskRow.eventItem
			color: taskRow.listColor
		}

		ColumnLayout {
			Layout.fillWidth: true
			Layout.minimumWidth: 0
			spacing: 1

			RowLayout {
				Layout.fillWidth: true
				spacing: Kirigami.Units.smallSpacing
				PlasmaComponents3.Label {
					id: titleLabel
					Layout.fillWidth: true
					Layout.minimumWidth: 0
					text: taskRow.title
					textFormat: Text.PlainText // User text: never parsed as HTML
					color: Kirigami.Theme.textColor
					font.family: appletConfig.eventFont.family
					font.pointSize: appletConfig.eventFont.pointSize
					font.strikeout: taskRow.eventStyle.struckThrough
					elide: Text.ElideRight
					maximumLineCount: taskRow.compact ? 1 : 2
					wrapMode: taskRow.compact ? Text.NoWrap : Text.Wrap
				}
				// Compact: the date after the title when it's overdue (the rest are due on this day).
				PlasmaComponents3.Label {
					visible: taskRow.compact && taskRow.overdue
					text: taskRow.dueDateText
					textFormat: Text.PlainText
					color: Kirigami.Theme.negativeTextColor
					font: appletConfig.eventSmallFont
				}
			}

			RowLayout {
				visible: !taskRow.compact && (!!taskRow.dueText || !!taskRow.notesLine)
				Layout.fillWidth: true
				spacing: Kirigami.Units.smallSpacing
				PlasmaComponents3.Label {
					visible: !!text
					text: taskRow.dueText
					textFormat: Text.PlainText
					color: taskRow.overdue ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
					opacity: taskRow.overdue ? 1 : 0.7
					font: appletConfig.eventSmallFont
				}
				PlasmaComponents3.Label {
					visible: !!text
					Layout.fillWidth: true
					Layout.minimumWidth: 0
					text: taskRow.notesLine
					textFormat: Text.PlainText // User text: never parsed as HTML
					color: Kirigami.Theme.textColor
					opacity: 0.6
					font: appletConfig.eventSmallFont
					elide: Text.ElideRight
					wrapMode: Text.NoWrap
					maximumLineCount: 1
				}
			}
		}
	}

	onLeftClicked: open()

	// Right click: the shared event menu (LinkRect's own menu is skipped once the click is accepted).
	onClicked: function(mouse) {
		if (mouse.button === Qt.RightButton) {
			mouse.accepted = true
			popup.showEventMenu(eventItem, taskRow, mouse.x, mouse.y)
		}
	}
}
