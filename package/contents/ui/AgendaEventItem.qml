import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "LocaleFuncs.js" as LocaleFuncs
import "MeetingLink.js" as MeetingLink
import "Shared.js" as Shared

LinkRect {
	id: agendaEventItem
	readonly property int eventItemIndex: index
	Layout.fillWidth: true

	property bool eventItemInProgress: false
	function checkIfInProgress() {
		if (model.startDateTime && timeModel.currentTime && model.endDateTime) {
			eventItemInProgress = model.startDateTime <= timeModel.currentTime && timeModel.currentTime <= model.endDateTime
		} else {
			eventItemInProgress = false
		}
	}
	Connections {
		target: timeModel
		function onLoaded() {
			agendaEventItem.checkIfInProgress()
		}
		function onMinuteChanged() {
			agendaEventItem.checkIfInProgress()
		}
	}
	Component.onCompleted: agendaEventItem.checkIfInProgress()

	property alias isEditing: editEventForm.active
	clickable: !isEditing

	// Keyboard and screen readers: the tile is a button that opens the event details.
	activeFocusOnTab: clickable
	Accessible.role: Accessible.Button
	Accessible.name: model.summary || i18n("Calendar event")
	Accessible.description: accessibleDescription()
	Accessible.focusable: activeFocusOnTab
	Accessible.focused: activeFocus
	Accessible.onPressAction: activateEvent()
	Keys.onReturnPressed: function(event) {
		activateEvent()
		event.accepted = true
	}
	Keys.onEnterPressed: function(event) {
		activateEvent()
		event.accepted = true
	}
	Keys.onSpacePressed: function(event) {
		activateEvent()
		event.accepted = true
	}
	function activateEvent() {
		if (clickable) {
			popup.activateEvent(events.get(eventItemIndex))
		}
	}
	function accessibleDescription() {
		var parts = []
		if (eventTimestamp) {
			parts.push(eventTimestamp)
		}
		if (model.location) {
			parts.push(model.location)
		}
		if (eventItemInProgress) {
			parts.push(i18n("In progress"))
		}
		return parts.join(". ")
	}

	readonly property string eventTimestamp: LocaleFuncs.formatEventDuration(model, {
		relativeDate: agendaItemDate,
		clock24h: appletConfig.clock24h,
	})
	readonly property bool isAllDay: !!model.start && !!model.start.date && !model.start.dateTime
	readonly property bool isCondensed: plasmoid.configuration.agendaCondensedAllDayEvent && isAllDay

	// Tile in the event color, like the day list and the week view.
	readonly property color tileColor: appletConfig.eventColor(model.backgroundColor)
	readonly property color tileTextColor: editEventForm.visible ? Kirigami.Theme.textColor : Shared.contrastTextColor(tileColor)
	readonly property bool ended: !!model.endDateTime && !!timeModel.currentTime && model.endDateTime <= timeModel.currentTime
	readonly property var meetingLink: MeetingLink.find(model)
	radius: 8
	border.width: 1
	border.color: appletConfig.eventBorderColor
	backgroundColor: editEventForm.visible ? Kirigami.Theme.backgroundColor : tileColor
	backgroundHoverColor: editEventForm.visible ? backgroundColor : Qt.darker(tileColor, 1.08)
	// Events that already ended today are dimmed (whole past days are dimmed by the day item).
	opacity: ended && agendaItemIsToday ? appletConfig.pastOpacity : 1
	// Not LinkRect's childrenRect size: the contents follow the tile's width (binding loop).
	implicitWidth: contents.implicitWidth + Kirigami.Units.largeSpacing + Kirigami.Units.smallSpacing
	implicitHeight: contents.implicitHeight + Kirigami.Units.smallSpacing * 2 + 2

	ColumnLayout {
		id: contents
		anchors.left: parent.left
		anchors.right: parent.right
		anchors.top: parent.top
		anchors.leftMargin: Kirigami.Units.largeSpacing
		anchors.rightMargin: Kirigami.Units.smallSpacing
		anchors.topMargin: Kirigami.Units.smallSpacing + 1
		spacing: 0

		RowLayout {
			Layout.fillWidth: true
			spacing: Kirigami.Units.smallSpacing

			ColumnLayout {
				id: eventColumn
				Layout.fillWidth: true
				spacing: 0

				PlasmaComponents3.Label {
					id: eventSummary
					text: {
						if (isCondensed && model.location) {
							return model.summary + " · " + model.location
						}
						return model.summary
					}
					color: agendaEventItem.tileTextColor
					font.pointSize: -1
					font.pixelSize: appletConfig.agendaFontSize
					font.weight: eventItemInProgress ? Font.Bold : Font.Normal
					visible: !editEventForm.visible
					Layout.fillWidth: true
					wrapMode: Text.Wrap
				}

				PlasmaComponents3.Label {
					id: eventDateTime
					// The location opens in Google Maps.
					text: model.location ? Shared.escapeHtml(eventTimestamp) + " · " + Shared.locationLink(model.location) : Shared.escapeHtml(eventTimestamp)
					textFormat: Text.StyledText
					linkColor: agendaEventItem.tileTextColor
					onLinkActivated: function(link) { Shared.openExternalUrl(link) }
					color: agendaEventItem.tileTextColor
					opacity: 0.85
					font: Kirigami.Theme.smallFont
					visible: !editEventForm.visible && !isCondensed
					Layout.fillWidth: true
					elide: Text.ElideRight
				}
			}

			JoinPill {
				visible: plasmoid.configuration.agendaShowEventHangoutLink && !!agendaEventItem.meetingLink && !editEventForm.visible && !agendaEventItem.ended
				Layout.alignment: Qt.AlignVCenter
				meetingLink: agendaEventItem.meetingLink
				textColor: agendaEventItem.tileTextColor
			}
		}

		PlasmaComponents3.Label {
			id: eventDescription
			readonly property bool showProperty: plasmoid.configuration.agendaShowEventDescription && text
			visible: showProperty && !editEventForm.visible
			Layout.topMargin: Kirigami.Units.smallSpacing
			text: Shared.renderText(model.description)
			color: agendaEventItem.tileTextColor
			opacity: 0.8
			font.pointSize: -1
			font.pixelSize: appletConfig.agendaFontSize
			Layout.fillWidth: true
			wrapMode: Text.Wrap
			maximumLineCount: plasmoid.configuration.agendaMaxDescriptionLines
			elide: Text.ElideRight
			linkColor: agendaEventItem.tileTextColor
			onLinkActivated: function(link) {
				Shared.openExternalUrl(link)
			}
			MouseArea {
				anchors.fill: parent
				acceptedButtons: Qt.NoButton // we don't want to eat clicks on the Text
				cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
			}
		}

		Item {
			visible: editEventForm.visible
			implicitHeight: 4 * Screen.devicePixelRatio
		}

		EditEventForm {
			id: editEventForm
		}

		Item {
			visible: editEventForm.visible
			implicitHeight: 4 * Screen.devicePixelRatio
		}
	}

	onLeftClicked: activateEvent()

	onLoadContextMenu: function(contextMenu) {
		var menuItem
		var event = events.get(eventItemIndex)

		menuItem = contextMenu.newMenuItem()
		menuItem.text = i18n("Edit")
		menuItem.icon.name = "edit-rename"
		menuItem.enabled = event.canEdit
		menuItem.clicked.connect(function() {
			editEventForm.active = !editEventForm.active
			agendaScrollView.positionViewAtEvent(agendaItemIndex, eventItemIndex)
		})
		contextMenu.addMenuItem(menuItem)

		var deleteMenu = contextMenu.newSubMenu()
		deleteMenu.title = i18n("Delete Event")
		deleteMenu.icon.name = "delete"
		menuItem = deleteMenu.newMenuItem()
		menuItem.text = i18n("Confirm Deletion")
		menuItem.icon.name = "delete"
		menuItem.enabled = event.canEdit
		menuItem.clicked.connect(function() {
			logger.debug('eventModel.deleteEvent', event.calendarId, event.id)
			eventModel.deleteEvent(event.calendarId, event.id)
		})
		deleteMenu.enabled = event.canEdit
		deleteMenu.addMenuItem(menuItem)

		menuItem = contextMenu.newMenuItem()
		menuItem.text = i18n("Edit in browser")
		menuItem.icon.name = "internet-web-browser"
		menuItem.enabled = !!event.htmlLink
		menuItem.clicked.connect(function() {
			Shared.openExternalUrl(event.htmlLink)
		})
		contextMenu.addMenuItem(menuItem)
	}
}
