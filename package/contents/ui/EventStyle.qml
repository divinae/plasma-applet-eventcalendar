import QtQuick
import org.kde.kirigami as Kirigami

import "Shared.js" as Shared

// How an event looks in the views: its color (AppletConfig.eventColor) and the user's answer to
// it, like Google Calendar: not (yet) a yes is outlined in the event color on the background,
// maybe and out of office are striped (StripeFill), declined is struck through. With the "bar"
// event look (AppletConfig.barEventLook) timed events are a light tint with a bar in their color.
QtObject {
	property var eventItem: null

	readonly property color color: appletConfig.eventColor(eventItem ? eventItem.backgroundColor : null)
	readonly property string response: Shared.myResponse(eventItem)
	readonly property bool unconfirmed: Shared.isUnconfirmedResponse(response)
	readonly property bool tentative: response === 'tentative'
	readonly property bool declined: response === 'declined'
	readonly property bool outOfOffice: !!eventItem && eventItem.eventType === 'outOfOffice'
	readonly property bool striped: tentative || outOfOffice

	readonly property bool allDay: !!eventItem && !!eventItem.start && !!eventItem.start.date && !eventItem.start.dateTime
	// The bar in the event color (the view draws it on the start side).
	readonly property bool showBar: appletConfig.barEventLook && !!eventItem && !allDay
	readonly property bool tinted: showBar && !unconfirmed

	// The bar, and the base of the tint and the outline (pale colors darker, AppletConfig.eventBarColor).
	readonly property color barColor: showBar ? appletConfig.eventBarColor(color) : color

	// Bar look, not yet answered: no fill, the cell shows through (outline and bar only).
	readonly property color fillColor: tinted ? appletConfig.eventTintColor(barColor)
		: showBar && unconfirmed ? "transparent" : appletConfig.eventFillColor(color, response)
	// Bar look: not yet answered (not maybe) has its title in the event color (on the background, outlined), so
	// it stands apart from the tinted events.
	readonly property color textColor: showBar ? (unconfirmed && !tentative ? appletConfig.eventColoredTextColor(barColor) : Kirigami.Theme.textColor) : appletConfig.eventTextColor(color, response)
	readonly property color outlineColor: tinted && !declined ? appletConfig.eventTintOutlineColor(barColor) : appletConfig.eventOutlineColor(barColor, response)
	// Maybe: stripes in the event color; out of office: in the text color.
	readonly property color stripeColor: tentative ? barColor : textColor
}
