import QtQuick
import org.kde.plasma.components as PlasmaComponents3

import "Guests.js" as Guests
import "Responses.js" as Responses
import "MeetingLink.js" as MeetingLink
import "Shared.js" as Shared

// Right-click menu for an event, the same in every view: details, join, open in Google Calendar,
// respond (RSVP, when invited), email the guests, edit, delete (confirmed in a submenu). One instance lives in
// PopupView (popup.showEventMenu).
PlasmaComponents3.Menu {
	id: eventMenu

	property var eventItem: null
	readonly property var meetingLink: eventItem ? MeetingLink.find(eventItem) : null
	readonly property bool canEdit: !!(eventItem && eventItem.canEdit)
	readonly property bool isRecurring: !!(eventItem && eventItem.recurringEventId)
	readonly property var selfAttendee: eventItem ? eventModel.selfAttendee(eventItem) : null
	readonly property bool canRespond: !!eventItem && eventModel.canRespond(eventItem)
	readonly property string response: selfAttendee ? selfAttendee.responseStatus || "" : ""
	readonly property string mailtoUrl: Guests.eventMailtoUrl(eventItem)

	signal showDetails(var eventItem)
	signal editEvent(var eventItem)
	signal duplicateEvent(var eventItem)

	function openFor(item, parentItem, x, y) {
		eventItem = item
		showRespondMenu(canRespond)
		popup(parentItem, x, y)
	}

	// A submenu can't be hidden, so the Respond submenu is only inserted for invitations.
	readonly property int respondMenuIndex: 3 // After "Open in Google Calendar"
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
	PlasmaComponents3.MenuItem {
		visible: !!(eventMenu.eventItem && eventMenu.eventItem.htmlLink)
		height: visible ? implicitHeight : 0
		text: i18n("Open in Google Calendar")
		icon.name: "globe"
		onTriggered: Shared.openExternalUrl(eventMenu.eventItem.htmlLink)
	}
	// A meeting that ended early: no progress in the panel for it.
	PlasmaComponents3.MenuItem {
		visible: !!eventMenu.eventItem && upcomingEvents.isOngoing(eventMenu.eventItem)
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
		text: i18n("Duplicate…")
		icon.name: "edit-copy"
		onTriggered: eventMenu.duplicateEvent(eventMenu.eventItem)
	}
	PlasmaComponents3.Menu {
		id: deleteMenu
		enabled: eventMenu.canEdit
		title: i18n("Delete")
		icon.name: "edit-delete"
		PlasmaComponents3.MenuItem {
			text: !eventMenu.eventItem ? ""
				: eventMenu.isRecurring ? i18nc("%1 = event title", "Delete Only This Occurrence of “%1”", eventMenu.eventItem.summary)
				: i18nc("%1 = event title", "Delete “%1”", eventMenu.eventItem.summary)
			icon.name: "edit-delete"
			onTriggered: popup.deleteWithUndo(eventMenu.eventItem, false)
		}
		// Repeating events: the whole series, by its id.
		PlasmaComponents3.MenuItem {
			visible: eventMenu.isRecurring
			height: visible ? implicitHeight : 0
			text: eventMenu.eventItem ? i18nc("%1 = event title", "Delete All Events of “%1”", eventMenu.eventItem.summary) : ""
			icon.name: "edit-delete"
			onTriggered: popup.deleteWithUndo(eventMenu.eventItem, true)
		}
	}
}
