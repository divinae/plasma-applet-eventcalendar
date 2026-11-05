.pragma library
// The calendar picker of the new-event forms (CalendarSelector): which calendars it lists, which
// one starts selected, and their labels. After ALikesToCode's fork (their commits 0c7b2aef,
// fa874264).

// "Calendar (account)": the calendar's own name first, so a narrow picker still shows which one it
// is. A primary calendar named after its account: the name once. Without an account (or a name),
// its summary as it is.
function choiceLabel(calendar) {
	var name = calendar.calendarName
	var account = calendar.accountLabel
	if (name && account) {
		if (calendar.primary === true && name === account) {
			return name
		}
		return name + " (" + account + ")"
	}
	return calendar.summary
}

// The calendars one can add to (and the initial one, even read-only), in their order; the one
// selected: the initial (remembered) one, else the first primary calendar (not the first writable
// one, eg: a shared family calendar), else the first. { calendars: [calendar], selectedIndex }.
function buildChoices(calendarList, initialCalendarId) {
	var calendars = []
	var selectedIndex = -1
	var primaryIndex = -1
	;(calendarList || []).forEach(function(calendar) {
		var canEdit = calendar.accessRole === 'writer' || calendar.accessRole === 'owner'
		var isInitial = !!initialCalendarId && calendar.id === initialCalendarId
		if (!canEdit && !isInitial) {
			return
		}
		if (isInitial && selectedIndex < 0) {
			selectedIndex = calendars.length
		}
		if (calendar.primary === true && !calendar.isTasklist && primaryIndex < 0) {
			primaryIndex = calendars.length
		}
		calendars.push(calendar)
	})
	if (selectedIndex < 0) {
		selectedIndex = primaryIndex >= 0 ? primaryIndex : 0
	}
	return { calendars: calendars, selectedIndex: selectedIndex }
}

if (typeof module !== "undefined") {
	module.exports = { choiceLabel: choiceLabel, buildChoices: buildChoices }
}
