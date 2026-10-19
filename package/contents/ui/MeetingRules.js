.pragma library

.import "Shared.js" as Shared

// Which meetings open their link at the start (auto-join). Pure functions, tested in
// tests/meeting_rules.test.js.

function isTimedEvent(eventItem) {
	return !!eventItem
		&& eventItem.kind !== 'tasks#task'
		&& eventItem.status !== 'cancelled'
		&& !(eventItem.start && eventItem.start.date)
}

// Auto-join: a timed event with a meeting link (hasLink: MeetingLink.find found one) that the
// user accepted or organizes (or that has no guests).
function canAutoJoin(eventItem, hasLink) {
	if (!isTimedEvent(eventItem) || !hasLink) {
		return false
	}
	var response = Shared.myResponse(eventItem)
	return response === 'accepted' || response === ''
}
