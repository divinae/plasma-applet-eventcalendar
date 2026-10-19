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

	// Tile in the event color, like the month and week views.
	readonly property color tileColor: appletConfig.eventColor(model.backgroundColor)
	readonly property string response: Shared.myResponse(model)
	readonly property color tileFillColor: appletConfig.eventFillColor(tileColor, response)
	readonly property color tileTextColor: appletConfig.eventTextColor(tileColor, response)
	readonly property bool ended: !!model.endDateTime && !!timeModel.currentTime && model.endDateTime <= timeModel.currentTime
	readonly property var meetingLink: MeetingLink.find(model)
	radius: 8
	border.width: 1
	border.color: appletConfig.eventOutlineColor(tileColor, response)
	backgroundColor: tileFillColor
	backgroundHoverColor: Shared.isUnconfirmedResponse(response) ? appletConfig.agendaHoverBackground : Qt.darker(tileColor, 1.08)
	// Events that already ended today are dimmed (whole past days are dimmed by the day item).
	opacity: ended && agendaItemIsToday ? appletConfig.pastOpacity : 1
	// Not LinkRect's childrenRect size: the contents follow the tile's width (binding loop).
	implicitWidth: contents.implicitWidth + Kirigami.Units.largeSpacing + Kirigami.Units.smallSpacing
	implicitHeight: contents.implicitHeight + Kirigami.Units.smallSpacing * 2 + 2

	StripeFill {
		visible: (agendaEventItem.response === 'tentative' || model.eventType === 'outOfOffice')
		anchors.fill: parent
		anchors.margins: 1
		radius: agendaEventItem.radius - 1
		stripeColor: agendaEventItem.response === 'tentative' ? agendaEventItem.tileColor : agendaEventItem.tileTextColor
	}

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
					font.family: appletConfig.eventFont.family
					font.pointSize: appletConfig.eventFont.pointSize
					font.weight: eventItemInProgress ? Font.Bold : Font.Normal
					font.strikeout: agendaEventItem.response === 'declined'
					Layout.fillWidth: true
					wrapMode: Text.Wrap
				}

				RowLayout {
					Layout.fillWidth: true
					spacing: Kirigami.Units.smallSpacing
					visible: !isCondensed
					PlasmaComponents3.Label {
						id: eventDateTime
						// The location opens in Google Maps.
						text: model.location ? Shared.escapeHtml(eventTimestamp) + " · " + Shared.locationLink(model.location) : Shared.escapeHtml(eventTimestamp)
						textFormat: Text.StyledText
						linkColor: agendaEventItem.tileTextColor
						onLinkActivated: function(link) { Shared.openExternalUrl(link) }
						color: agendaEventItem.tileTextColor
						opacity: 0.85
						font: appletConfig.eventSmallFont
						Layout.fillWidth: true
						Layout.maximumWidth: implicitWidth
						elide: Text.ElideRight
					}
					// What else is set; the location, Join button and description are shown already.
					EventIndicators {
						Layout.alignment: Qt.AlignVCenter
						eventItem: model
						color: agendaEventItem.tileTextColor
						// Even pixel sizes keep scaled icons crisp.
						iconSize: 2 * Math.round(Math.min(Kirigami.Units.iconSizes.small * appletConfig.eventFontScale, eventDateTime.implicitHeight) / 2)
						opacity: 0.85
						showLocation: false
						showMeeting: !(plasmoid.configuration.agendaShowEventHangoutLink && !agendaEventItem.ended)
						showDescription: !eventDescription.showProperty
					}
					Item { Layout.fillWidth: true }
				}
			}

			JoinPill {
				visible: plasmoid.configuration.agendaShowEventHangoutLink && !!agendaEventItem.meetingLink && !agendaEventItem.ended
				Layout.alignment: Qt.AlignVCenter
				meetingLink: agendaEventItem.meetingLink
				textColor: agendaEventItem.tileTextColor
			}
		}

		PlasmaComponents3.Label {
			id: eventDescription
			readonly property bool showProperty: plasmoid.configuration.agendaShowEventDescription && text
			visible: showProperty
			Layout.topMargin: Kirigami.Units.smallSpacing
			text: Shared.renderText(model.description)
			color: agendaEventItem.tileTextColor
			opacity: 0.8
			font.family: appletConfig.eventFont.family
			font.pointSize: appletConfig.eventFont.pointSize
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
	}

	onLeftClicked: activateEvent()

	// Right click: the shared event menu (LinkRect's own menu is skipped once the click is accepted).
	onClicked: function(mouse) {
		if (mouse.button === Qt.RightButton) {
			mouse.accepted = true
			popup.showEventMenu(events.get(eventItemIndex), agendaEventItem, mouse.x, mouse.y)
		}
	}
}
