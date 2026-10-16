import QtQuick

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

	function populate(calendarList, initialCalendarId) {
		var list = []
		var selectedIndex = 0
		calendarList.forEach(function(calendar){
			var canEditCalendar = calendar.accessRole === 'writer' || calendar.accessRole === 'owner'
			var isSelected = calendar.id === initialCalendarId

			if (isSelected) {
				selectedIndex = list.length // set index after insertion
			}

			if (canEditCalendar || isSelected) {
				list.push({
					'calendarId': calendar.id,
					'text': calendar.summary,
					'backgroundColor': calendar.backgroundColor,
					'isTasklist': calendar.isTasklist,
					'timeZone': calendar.timeZone || '', // Needed for recurring events
				})
			}
		})
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
