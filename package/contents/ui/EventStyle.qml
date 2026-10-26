import QtQuick
import org.kde.kirigami as Kirigami

import "Shared.js" as Shared
import "Tasks.js" as Tasks

// How an event looks in the views: its color (AppletConfig.eventColor) and the user's answer to
// it, like Google Calendar: not (yet) a yes is outlined in the event color on the background,
// maybe and out of office are striped (StripeFill), declined is struck through. With the "bar"
// event look (AppletConfig.barEventLook) timed events are a light tint with a bar in their color.
// Tasks: in the bar look outlined with a bar (so they differ from all-day events, which are filled),
// filled in the solid look; done ones are struck through and dimmed (doneOpacity).
QtObject {
	property var eventItem: null

	readonly property color color: appletConfig.eventColor(eventItem ? eventItem.backgroundColor : null)
	readonly property string response: Shared.myResponse(eventItem)
	readonly property bool unconfirmed: Shared.isUnconfirmedResponse(response)
	readonly property bool tentative: response === 'tentative'
	readonly property bool declined: response === 'declined'
	readonly property bool outOfOffice: !!eventItem && eventItem.eventType === 'outOfOffice'
	readonly property bool striped: tentative || outOfOffice

	readonly property bool isTask: Tasks.isTask(eventItem)
	readonly property bool done: isTask && Tasks.isDone(eventItem)
	// Done tasks: their title struck through, and this opacity.
	readonly property real doneOpacity: done ? 0.55 : 1
	readonly property bool struckThrough: declined || done

	readonly property bool allDay: !!eventItem && !!eventItem.start && !!eventItem.start.date && !eventItem.start.dateTime
	// The bar in the event color (the view draws it on the start side).
	readonly property bool showBar: appletConfig.barEventLook && !!eventItem && (!allDay || isTask)
	// Bar look: the shape outlined in the bar color around a transparent inside (not yet answered, tasks).
	readonly property bool outlined: showBar && (unconfirmed || isTask)
	readonly property bool tinted: showBar && !outlined

	// The bar, and the base of the tint and the outline (pale colors darker, AppletConfig.eventBarColor).
	readonly property color barColor: showBar ? appletConfig.eventBarColor(color) : color

	// Bar look, not yet answered: no fill, the cell shows through (outline and bar only).
	readonly property color fillColor: tinted ? appletConfig.eventTintColor(barColor)
		: outlined ? "transparent" : appletConfig.eventFillColor(color, response)
	// Bar look: not yet answered (not maybe) has its title in the event color (on the background, outlined), so
	// it stands apart from the tinted events.
	readonly property color textColor: showBar ? (outlined && !tentative ? appletConfig.eventColoredTextColor(barColor) : Kirigami.Theme.textColor) : appletConfig.eventTextColor(color, response)
	readonly property color outlineColor: tinted && !declined ? appletConfig.eventTintOutlineColor(barColor) : outlined && isTask ? barColor : appletConfig.eventOutlineColor(barColor, response)
	// Maybe: stripes in the event color; out of office: in the text color.
	readonly property color stripeColor: tentative ? barColor : textColor
}
