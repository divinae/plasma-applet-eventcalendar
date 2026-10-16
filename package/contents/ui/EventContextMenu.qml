import QtQuick
import org.kde.plasma.components as PlasmaComponents3

import "MeetingLink.js" as MeetingLink
import "Shared.js" as Shared

// Right-click menu for an event, the same in every view: details, join, open in Google Calendar,
// edit, delete (confirmed in a submenu). One instance lives in PopupView (popup.showEventMenu).
PlasmaComponents3.Menu {
	id: menu

	property var eventItem: null
	readonly property var meetingLink: eventItem ? MeetingLink.find(eventItem) : null
	readonly property bool canEdit: !!(eventItem && eventItem.canEdit)
	readonly property bool isRecurring: !!(eventItem && eventItem.recurringEventId)

	signal showDetails(var eventItem)
	signal editEvent(var eventItem)

	function openFor(item, parentItem, x, y) {
		eventItem = item
		popup(parentItem, x, y)
	}

	PlasmaComponents3.MenuItem {
		text: i18n("Show Details")
		icon.name: "view-calendar-day"
		onTriggered: menu.showDetails(menu.eventItem)
	}
	PlasmaComponents3.MenuItem {
		visible: !!menu.meetingLink
		height: visible ? implicitHeight : 0
		text: menu.meetingLink ? i18nc("%1 = Google Meet, Zoom, ...", "Join %1", menu.meetingLink.label) : ""
		icon.name: "call-start"
		onTriggered: Shared.openExternalUrl(menu.meetingLink.url)
	}
	PlasmaComponents3.MenuItem {
		visible: !!(menu.eventItem && menu.eventItem.htmlLink)
		height: visible ? implicitHeight : 0
		text: i18n("Open in Google Calendar")
		icon.name: "globe"
		onTriggered: Shared.openExternalUrl(menu.eventItem.htmlLink)
	}
	PlasmaComponents3.MenuSeparator {
		visible: menu.canEdit
		height: visible ? implicitHeight : 0
	}
	PlasmaComponents3.MenuItem {
		visible: menu.canEdit
		height: visible ? implicitHeight : 0
		text: i18n("Edit…")
		icon.name: "document-edit"
		onTriggered: menu.editEvent(menu.eventItem)
	}
	PlasmaComponents3.Menu {
		id: deleteMenu
		enabled: menu.canEdit
		title: menu.isRecurring ? i18n("Delete This Occurrence") : i18n("Delete")
		icon.name: "edit-delete"
		PlasmaComponents3.MenuItem {
			text: menu.eventItem ? i18nc("%1 = event title", "Delete “%1”", menu.eventItem.summary) : ""
			icon.name: "edit-delete"
			onTriggered: eventModel.deleteEvent(menu.eventItem.calendarId, menu.eventItem.id)
		}
	}
}
