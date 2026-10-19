import QtQuick

import "Shared.js" as Shared

// How an event looks in the views: its color (AppletConfig.eventColor) and the user's answer to
// it, like Google Calendar: not (yet) a yes is outlined in the event color on the background,
// maybe and out of office are striped (StripeFill), declined is struck through.
QtObject {
	property var eventItem: null

	readonly property color color: appletConfig.eventColor(eventItem ? eventItem.backgroundColor : null)
	readonly property string response: Shared.myResponse(eventItem)
	readonly property bool unconfirmed: Shared.isUnconfirmedResponse(response)
	readonly property bool tentative: response === 'tentative'
	readonly property bool declined: response === 'declined'
	readonly property bool outOfOffice: !!eventItem && eventItem.eventType === 'outOfOffice'
	readonly property bool striped: tentative || outOfOffice

	readonly property color fillColor: appletConfig.eventFillColor(color, response)
	readonly property color textColor: appletConfig.eventTextColor(color, response)
	readonly property color outlineColor: appletConfig.eventOutlineColor(color, response)
	// Maybe: stripes in the event color; out of office: in the text color.
	readonly property color stripeColor: tentative ? color : textColor
}
