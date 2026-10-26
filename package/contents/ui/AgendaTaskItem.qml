import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "Shared.js" as Shared
import "Tasks.js" as Tasks

// A task in the agenda: a tile like the events (EventStyle: outlined with a bar in the bar look,
// filled in the solid look), with its done check before the title. Click opens it, right click the
// shared event menu; the check marks it done / not done.
LinkRect {
	id: agendaTaskItem
	readonly property int taskItemIndex: index
	Layout.fillWidth: true

	readonly property EventStyle eventStyle: EventStyle {
		eventItem: model
	}
	readonly property color tileTextColor: eventStyle.textColor
	readonly property bool taskIsOverdue: Tasks.isOverdue(model, timeModel.currentTime)
	readonly property string dueDay: Tasks.dueDay(model)
	readonly property string dueText: {
		if (!dueDay) {
			return ""
		}
		var parts = dueDay.split('-')
		var date = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
		return Qt.formatDate(date, i18nc("short month+date format", "MMM d"))
	}
	readonly property string notes: model.notes || model.description || ""

	// Keyboard and screen readers: the tile is a button that opens the task.
	activeFocusOnTab: clickable
	Accessible.role: Accessible.Button
	Accessible.name: model.summary || model.title || i18n("Task")
	Accessible.description: accessibleDescription()
	Accessible.focusable: activeFocusOnTab
	Accessible.focused: activeFocus
	Accessible.onPressAction: activateTask()
	Keys.onReturnPressed: function(event) {
		activateTask()
		event.accepted = true
	}
	Keys.onEnterPressed: function(event) {
		activateTask()
		event.accepted = true
	}
	Keys.onSpacePressed: function(event) {
		taskCheck.toggle()
		event.accepted = true
	}
	function activateTask() {
		if (clickable) {
			popup.activateEvent(tasks.get(taskItemIndex))
		}
	}
	function accessibleDescription() {
		var parts = []
		parts.push(eventStyle.done ? i18n("Done") : i18n("Not done"))
		if (dueText) {
			parts.push(i18nc("%1 = date", "Due %1", dueText))
		}
		if (taskIsOverdue) {
			parts.push(i18n("Overdue"))
		}
		return parts.join(". ")
	}

	radius: 8
	border.width: 1
	border.color: eventStyle.showBar ? "transparent" : eventStyle.outlineColor // ColorBarFill draws it
	backgroundColor: eventStyle.fillColor
	backgroundHoverColor: eventStyle.outlined ? appletConfig.agendaHoverBackground : Qt.darker(eventStyle.fillColor, 1.08)
	opacity: eventStyle.doneOpacity
	// Not LinkRect's childrenRect size: the contents follow the tile's width (binding loop).
	implicitWidth: contents.implicitWidth + Kirigami.Units.largeSpacing + Kirigami.Units.smallSpacing
	implicitHeight: contents.implicitHeight + Kirigami.Units.smallSpacing * 2 + 2

	ColorBarFill {
		visible: agendaTaskItem.eventStyle.showBar
		barColor: agendaTaskItem.eventStyle.barColor
		outlined: agendaTaskItem.eventStyle.outlined
		fillColor: agendaTaskItem.color // With the hover color
		borderColor: agendaTaskItem.eventStyle.outlineColor
		topLeftRadius: agendaTaskItem.radius
		bottomLeftRadius: agendaTaskItem.radius
		topRightRadius: agendaTaskItem.radius
		bottomRightRadius: agendaTaskItem.radius
	}

	RowLayout {
		id: contents
		anchors.left: parent.left
		anchors.right: parent.right
		anchors.top: parent.top
		anchors.leftMargin: Kirigami.Units.largeSpacing + (agendaTaskItem.eventStyle.showBar ? 4 : 0) - 2
		anchors.rightMargin: Kirigami.Units.smallSpacing
		anchors.topMargin: Kirigami.Units.smallSpacing + 1
		spacing: Kirigami.Units.smallSpacing

		TaskCheck {
			id: taskCheck
			Layout.alignment: Qt.AlignTop
			Layout.topMargin: Math.max(0, (taskTitle.implicitHeight - height) / 2)
			size: 2 * Math.round(Math.min(Kirigami.Units.iconSizes.small * 1.1, taskTitle.implicitHeight) / 2)
			eventItem: model
			color: agendaTaskItem.tileTextColor
		}

		ColumnLayout {
			Layout.fillWidth: true
			Layout.alignment: Qt.AlignTop
			spacing: 0

			PlasmaComponents3.Label {
				id: taskTitle
				Layout.fillWidth: true
				text: model.summary || model.title || ""
				textFormat: Text.PlainText // User text: never parsed as HTML
				color: agendaTaskItem.tileTextColor
				font.family: appletConfig.eventFont.family
				font.pointSize: appletConfig.eventFont.pointSize
				font.strikeout: agendaTaskItem.eventStyle.struckThrough
				wrapMode: Text.Wrap
			}

			// Overdue (shown on today): when it was due. On its own day the header says it.
			RowLayout {
				visible: agendaTaskItem.taskIsOverdue
				Layout.fillWidth: true
				spacing: Kirigami.Units.smallSpacing
				PlasmaComponents3.Label {
					Layout.fillWidth: true
					text: i18nc("%1 = short date", "Overdue · due %1", agendaTaskItem.dueText)
					// Red on the background (outlined tiles); on a filled tile in its text color.
					color: agendaTaskItem.eventStyle.outlined ? Kirigami.Theme.negativeTextColor : agendaTaskItem.tileTextColor
					font: appletConfig.eventSmallFont
					elide: Text.ElideRight
				}
			}

			PlasmaComponents3.Label {
				id: taskNotes
				readonly property bool showProperty: plasmoid.configuration.agendaShowEventDescription && !!text
				visible: showProperty
				Layout.topMargin: Kirigami.Units.smallSpacing
				Layout.fillWidth: true
				text: Shared.renderText(agendaTaskItem.notes)
				textFormat: Text.StyledText // renderText: escaped text and links only
				color: agendaTaskItem.tileTextColor
				opacity: 0.8
				font.family: appletConfig.eventFont.family
				font.pointSize: appletConfig.eventFont.pointSize
				wrapMode: Text.Wrap
				maximumLineCount: plasmoid.configuration.agendaMaxDescriptionLines
				elide: Text.ElideRight
				linkColor: agendaTaskItem.tileTextColor
				onLinkActivated: function(link) { Shared.openExternalUrl(link) }
				MouseArea {
					anchors.fill: parent
					acceptedButtons: Qt.NoButton // we don't want to eat clicks on the Text
					cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
				}
			}
		}
	}

	onLeftClicked: activateTask()

	// Right click: the shared event menu (LinkRect's own menu is skipped once the click is accepted).
	onClicked: function(mouse) {
		if (mouse.button === Qt.RightButton) {
			mouse.accepted = true
			popup.showEventMenu(tasks.get(taskItemIndex), agendaTaskItem, mouse.x, mouse.y)
		}
	}
}
