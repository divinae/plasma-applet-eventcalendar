import QtQuick
import "code/GooglePalette.js" as GooglePalette
import "lib/CalendarSelection.js" as CalendarSelection

FormComboBox {
	id: calendarSelector
	model: [
		{ text: i18n("[No Calendars]") }
	]
	textRole: "text"

	readonly property var selectedCalendar: currentIndex >= 0 ? model[currentIndex] : null
	readonly property var selectedCalendarId: selectedCalendar ? selectedCalendar.calendarId : null
	readonly property bool selectedIsTasklist: {
		if (!selectedCalendar) {
			return false
		}
		return selectedCalendar.isTasklist === true
	}

	// Select a calendar of the list by id (eg: back to the event's own calendar).
	function selectCalendar(calendarId) {
		for (var i = 0; i < model.length; i++) {
			if (model[i].calendarId === calendarId) {
				currentIndex = i
				return
			}
		}
	}

	// Which calendars, which selected (the remembered one, else the primary calendar) and their
	// labels ("Calendar (account)"): CalendarSelection.
	function populate(calendarList, initialCalendarId) {
		var choices = CalendarSelection.buildChoices(calendarList, initialCalendarId)
		var list = choices.calendars.map(function(calendar) {
			return {
				'calendarId': calendar.id,
				'text': CalendarSelection.choiceLabel(calendar),
				'backgroundColor': GooglePalette.displayCalendarColor(calendar, plasmoid.configuration.googleColorPalette),
				'isTasklist': calendar.isTasklist,
				'timeZone': calendar.timeZone || '', // Needed for recurring events
				'primary': calendar.primary === true, // Google: out of office / focus time only there
				// Video conferencing the calendar allows, eg: ['hangoutsMeet']; null when unknown.
				'conferenceTypes': calendar.conferenceProperties && calendar.conferenceProperties.allowedConferenceSolutionTypes || null,
			}
		})
		var selectedIndex = choices.selectedIndex
		if (list.length === 0) {
			list.push({
				text: i18n("[No Calendars]"),
				calendarId: "",
				isTasklist: false,
			})
		}
		calendarSelector.model = list
		calendarSelector.currentIndex = selectedIndex
	}
}
