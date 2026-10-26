import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "Tasks.js" as Tasks

// A task as a row (Tasks view, Day view): a tile in its list's color like the agenda's (EventStyle,
// both event looks), its done check, title, when it's due and the first line of its notes. Click
// opens it, right click the shared event menu; the check marks it done / not done.
LinkRect {
	id: taskRow

	property var eventItem: null
	// Today, 'YYYY-MM-DD': for "Today", "Tomorrow" and "Overdue".
	property string today: Tasks.dayString(new Date())
	// Smaller: no notes line (Day view).
	property bool compact: false

	readonly property EventStyle eventStyle: EventStyle {
		eventItem: taskRow.eventItem
	}
	readonly property color tileTextColor: eventStyle.textColor
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

	radius: 8
	border.width: 1
	border.color: eventStyle.showBar ? "transparent" : eventStyle.outlineColor // ColorBarFill draws it
	backgroundColor: eventStyle.fillColor
	backgroundHoverColor: eventStyle.outlined ? appletConfig.agendaHoverBackground : Qt.darker(eventStyle.fillColor, 1.08)
	opacity: eventStyle.doneOpacity
	implicitWidth: contents.implicitWidth + Kirigami.Units.largeSpacing + Kirigami.Units.smallSpacing
	implicitHeight: contents.implicitHeight + (compact ? 4 : Kirigami.Units.smallSpacing * 2) + 2

	ColorBarFill {
		visible: taskRow.eventStyle.showBar
		barColor: taskRow.eventStyle.barColor
		outlined: taskRow.eventStyle.outlined
		fillColor: taskRow.color // With the hover color
		borderColor: taskRow.eventStyle.outlineColor
		topLeftRadius: taskRow.radius
		bottomLeftRadius: taskRow.radius
		topRightRadius: taskRow.radius
		bottomRightRadius: taskRow.radius
	}

	RowLayout {
		id: contents
		anchors.left: parent.left
		anchors.right: parent.right
		anchors.verticalCenter: parent.verticalCenter
		anchors.leftMargin: Kirigami.Units.largeSpacing + (taskRow.eventStyle.showBar ? 4 : 0) - 2
		anchors.rightMargin: Kirigami.Units.smallSpacing
		spacing: Kirigami.Units.smallSpacing

		TaskCheck {
			id: taskCheck
			Layout.alignment: Qt.AlignTop
			Layout.topMargin: Math.max(0, (titleLabel.implicitHeight - height) / 2)
			size: 2 * Math.round(Math.min(Kirigami.Units.iconSizes.small * 1.1, titleLabel.implicitHeight) / 2)
			eventItem: taskRow.eventItem
			color: taskRow.tileTextColor
		}

		ColumnLayout {
			Layout.fillWidth: true
			Layout.minimumWidth: 0
			spacing: 0

			RowLayout {
				Layout.fillWidth: true
				spacing: Kirigami.Units.smallSpacing
				PlasmaComponents3.Label {
					id: titleLabel
					Layout.fillWidth: true
					Layout.minimumWidth: 0
					text: taskRow.title
					textFormat: Text.PlainText // User text: never parsed as HTML
					color: taskRow.tileTextColor
					font.family: appletConfig.eventFont.family
					font.pointSize: appletConfig.eventFont.pointSize
					font.strikeout: taskRow.eventStyle.struckThrough
					elide: Text.ElideRight
					maximumLineCount: taskRow.compact ? 1 : 2
					wrapMode: taskRow.compact ? Text.NoWrap : Text.Wrap
				}
				// Compact: when it's due after the title (overdue ones only, the rest are on this day).
				PlasmaComponents3.Label {
					visible: taskRow.compact && taskRow.due.kind === 'overdue'
					text: taskRow.dueDateText
					textFormat: Text.PlainText
					color: taskRow.eventStyle.outlined ? Kirigami.Theme.negativeTextColor : taskRow.tileTextColor
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
					// Overdue in red on the background (outlined tiles); on a filled tile in its text color.
					color: taskRow.due.kind === 'overdue' && taskRow.eventStyle.outlined ? Kirigami.Theme.negativeTextColor : taskRow.tileTextColor
					opacity: taskRow.due.kind === 'overdue' ? 1 : 0.8
					font: appletConfig.eventSmallFont
				}
				PlasmaComponents3.Label {
					visible: !!text
					Layout.fillWidth: true
					Layout.minimumWidth: 0
					text: taskRow.notesLine
					textFormat: Text.PlainText // User text: never parsed as HTML
					color: taskRow.tileTextColor
					opacity: 0.65
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
