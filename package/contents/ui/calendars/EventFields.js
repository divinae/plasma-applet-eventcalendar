.pragma library

// Fields the widget adds to an event when it parses or shows it (CalendarManager.defaultEventParsing,
// GoogleCalendarManager.parseEvent, EventModel: the disk cache, conflicts). Never sent to Google:
// removed from update bodies (GoogleCalendarManager.cloneRawEvent) and undo copies (Undo.js).
var widgetFields = ['calendarManagerId', 'calendarId', 'startDateTime', 'endDateTime', 'canEdit',
	'_summary', 'reminderMinutes', 'reminderOwn', 'fromCache', 'conflictsWith']

// Deletes the widget's fields from data (a copy of an event), in place.
function stripWidgetFields(data) {
	widgetFields.forEach(function(key) {
		delete data[key]
	})
	return data
}
