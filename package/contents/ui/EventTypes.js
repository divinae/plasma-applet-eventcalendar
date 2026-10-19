.pragma library

// Google event types the editor creates: a normal event, out of office or focus time. Google only
// allows the special ones on primary calendars, always busy (opaque), without guests, video call
// or location.

var TYPES = ['default', 'outOfOffice', 'focusTime']
var DECLINE_MODES = ['declineNone', 'declineOnlyNewConflictingInvitations', 'declineAllConflictingInvitations']
var CHAT_STATUSES = ['doNotDisturb', 'available']

function isSpecial(type) {
	return type === 'outOfOffice' || type === 'focusTime'
}

// Settings of a special type, from the editor: { autoDeclineMode, declineMessage, chatStatus }.
function properties(type, options) {
	options = options || {}
	var mode = DECLINE_MODES.indexOf(options.autoDeclineMode) >= 0 ? options.autoDeclineMode : DECLINE_MODES[0]
	var props = { autoDeclineMode: mode }
	var message = String(options.declineMessage || '').trim()
	if (message && mode !== 'declineNone') {
		props.declineMessage = message
	}
	if (type === 'focusTime') {
		props.chatStatus = CHAT_STATUSES.indexOf(options.chatStatus) >= 0 ? options.chatStatus : CHAT_STATUSES[0]
	}
	return props
}

// Makes a new event body (events.insert) of `type`: adds eventType and its properties, and drops
// what Google refuses on these events. A normal event is left as it is.
function applyTo(body, type, options) {
	if (!isSpecial(type)) {
		return body
	}
	body.eventType = type
	if (type === 'outOfOffice') {
		body.outOfOfficeProperties = properties(type, options)
	} else {
		body.focusTimeProperties = properties(type, options)
	}
	body.transparency = 'opaque'
	delete body.attendees
	delete body.conferenceData
	delete body.location
	return body
}

// The editor's settings from an event of a special type (eg: a duplicate), or null.
function optionsOf(event) {
	if (!event || !isSpecial(event.eventType)) {
		return null
	}
	var props = (event.eventType === 'outOfOffice' ? event.outOfOfficeProperties : event.focusTimeProperties) || {}
	return {
		type: event.eventType,
		autoDeclineMode: DECLINE_MODES.indexOf(props.autoDeclineMode) >= 0 ? props.autoDeclineMode : DECLINE_MODES[0],
		declineMessage: props.declineMessage || '',
		chatStatus: CHAT_STATUSES.indexOf(props.chatStatus) >= 0 ? props.chatStatus : CHAT_STATUSES[0],
	}
}
