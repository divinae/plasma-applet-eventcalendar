import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.workspace.calendar as PlasmaCalendar

import "../lib"
import "../Shared.js" as Shared
import "../calendars/PlasmaCalendarEventState.js" as PlasmaCalendarEventState
import "../calendars/PlasmaCalendarUtils.js" as PlasmaCalendarUtils

CalendarManager {
	id: plasmaCalendarManager

	calendarManagerId: "plasma"

	property var executable: ExecUtil { id: executable }
	property var calendarModel: {
		// kdepim-addons is optional.
		try {
			return Qt.createQmlObject("import org.kde.plasma.PimCalendars; PimCalendarsModel {}", plasmaCalendarManager)
		} catch (e) {
			return null
		}
	}
	property var eventPluginsManager: null

	function ensureEventPluginsManager() {
		if (eventPluginsManager) {
			return true
		}
		try {
			eventPluginsManager = Qt.createQmlObject(
				"import org.kde.plasma.workspace.calendar as PlasmaCalendar; PlasmaCalendar.EventPluginsManager {}",
				plasmaCalendarManager
			)
			return true
		} catch (e) {
			logger.debug('EventPluginsManager unavailable', e)
			eventPluginsManager = null
			return false
		}
	}
	function syncEnabledPlugins() {
		if (!ensureEventPluginsManager()) {
			return
		}
		PlasmaCalendarUtils.setEnabledPluginsByFilename(
			eventPluginsManager,
			plasmoid.configuration.enabledCalendarPlugins,
			plasmoid.configuration.enabledCalendarPluginsAllowEmpty
		)
	}
	function appendPimCalendars(calendarList) {
		// https://github.com/KDE/kdepim-addons/blob/master/plugins/plasma/pimeventsplugin/PimEventsConfig.qml
		// https://github.com/KDE/kdepim-addons/blob/master/plugins/plasma/pimeventsplugin/pimcalendarsmodel.cpp

		if (!calendarModel) {
			logger.debug('KDEPIM Not installed as PimCalendarsModel import failed.', calendarModel)
			return
		}

		logger.debug('calendarModel.count', calendarModel.rowCount())
		var rows = PlasmaCalendarUtils.pimCalendarRows(calendarModel, Qt.UserRole, Qt.DisplayRole)
		var shownNames = []
		for (var i = 0; i < rows.length; i++) {
			if (!rows[i].checked) {
				continue
			}
			// For new events (konsolekalendar): the plugin doesn't say which calendar an event is from.
			calendarList.push({
				"id": "plasma_Events_" + rows[i].id,
				"summary": rows[i].name,
				"backgroundColor": "#9a9cff",
				"accessRole": "owner",
				"isTasklist": false,
				"inCalendarMenu": false, // Its events are in the one below
			})
			if (shownNames.indexOf(rows[i].name) < 0) {
				shownNames.push(rows[i].name)
			}
		}
		if (!pimEventsPluginEnabled()) {
			return
		}
		// The Akonadi events by their color, a calendar each (eg: to show or hide them in the popup's
		// calendar menu or the Day view): the plugin tells an event's color, not its calendar.
		// Named after the shown calendars of that color (akonadiColors), else a few of their events;
		// calendars of one color share one.
		// Not the Google calendars of an account signed in here: they are with that account.
		var namesByColor = PlasmaCalendarUtils.namesByColor(rows.filter(function(row) {
			return !mirroredCollections[row.id]
		}), akonadiColors)
		var separator = i18nc("separator of names in a list", ", ")
		pimColorCalendars.forEach(function(group) {
			var names = namesByColor[PlasmaCalendarUtils.colorKey(group.color)]
			calendarList.push({
				"id": group.id,
				"summary": names ? names.join(separator) : i18nc("%1 = a few event titles", "Akonadi calendar: %1", group.titles.join(separator)),
				"description": i18np("%1 event", "%1 events", group.count),
				"backgroundColor": group.color,
				"accessRole": "reader",
				"isTasklist": false,
			})
		})
		// Events without a color: all the Akonadi events as one calendar, named after the calendars shown.
		if (pimColorCalendars.length === 0) {
			if (shownNames.length === 0) {
				if (!pimEventsColor) {
					return // No Akonadi events either
				}
				shownNames.push(i18n("KDE PIM (Akonadi)"))
			}
			calendarList.push({
				"id": calendarManagerId + "_Events",
				"summary": shownNames.join(i18nc("separator of names in a list", ", ")),
				"backgroundColor": pimEventsColor || Kirigami.Theme.highlightColor.toString(),
				"accessRole": "reader",
				"isTasklist": false,
			})
		}
	}
	// Akonadi's calendar colors by collection id and its Google calendars, from its database
	// (PlasmaCalendarUtils.akonadiCalendarsCommand), read at the start and again with a fetch at most
	// every 10 minutes.
	property var akonadiColors: ({})
	property string akonadiGoogleCollections: ""
	property real akonadiColorsReadAt: 0
	function readAkonadiColors() {
		if (Date.now() - akonadiColorsReadAt < 10 * 60 * 1000) {
			return
		}
		akonadiColorsReadAt = Date.now()
		executable.execArgv(PlasmaCalendarUtils.akonadiCalendarsCommand(), function(cmd, exitCode, exitStatus, stdout) {
			var colors = PlasmaCalendarUtils.parseAkonadiColors(stdout)
			var changed = JSON.stringify(colors) !== JSON.stringify(akonadiColors)
			akonadiColors = colors
			akonadiGoogleCollections = String(stdout || "")
			if (updateMirroredCollections() || changed) {
				refresh() // The calendars named anew (the reading is throttled: no loop)
			}
		})
	}
	// The Google calendars of the accounts signed in to in the widget: { "email": ["calendar id", ...] }
	// (set by EventModel). Akonadi's copies of them (mirroredCollections) are left out: their events
	// come from the sign-in, and the calendar menu lists them with the account.
	property var googleCalendarIds: ({})
	property var mirroredCollections: ({})
	function updateMirroredCollections() {
		var mirrored = PlasmaCalendarUtils.akonadiMirroredCollections(akonadiGoogleCollections, googleCalendarIds)
		if (JSON.stringify(mirrored) === JSON.stringify(mirroredCollections)) {
			return false
		}
		mirroredCollections = mirrored
		return true
	}
	onGoogleCalendarIdsChanged: {
		if (updateMirroredCollections()) {
			refresh()
		}
	}
	// [{ id, color, count, titles }] from the last fetched Akonadi events, by color.
	property var pimColorCalendars: []
	function updatePimColorCalendars(events) {
		pimColorCalendars = PlasmaCalendarUtils.colorCalendars(events, calendarManagerId + "_EventsColor_", 3)
	}
	function pimEventsPluginEnabled() {
		return PlasmaCalendarUtils.hasPlugin(plasmoid.configuration.enabledCalendarPlugins, "pimevents")
	}
	// The most common color of the last fetched Akonadi events.
	property string pimEventsColor: ""
	function updatePimEventsColor(events) {
		var counts = {}
		var best = ""
		for (var i = 0; i < events.length; i++) {
			var color = events[i].backgroundColor
			counts[color] = (counts[color] || 0) + 1
			if (!best || counts[color] > counts[best]) {
				best = color
			}
		}
		pimEventsColor = best
	}

	// Holidays (KHolidays) come without a color: coral red (Google's "Flamingo"), pastel like the other calendars.
	readonly property string holidayColor: "#e67c73"

	//--- CalendarManager
	function getCalendarList() {
		var calendarList = []

		// KHolidays
		calendarList.push({
			"id": "plasma_Holidays",
			"backgroundColor": holidayColor,
			"accessRole": "reader",
			"isTasklist": false,
		})

		// KDEPIM
		appendPimCalendars(calendarList)

		return calendarList
	}

	// https://github.com/KDE/plasma-framework/blob/master/src/declarativeimports/calendar/eventpluginsmanager.cpp
	// Plugins are located at:
	//     * (Ubuntu) /usr/lib/x86_64-linux-gnu/qt5/plugins/plasmacalendarplugins/
	//     * (Arch) /usr/lib/qt/plugins/plasmacalendarplugins/
	// DigitalClock's config in ~/.config/plasma-____-appletsrc is:
	//   enabledCalendarPlugins=/usr/lib/.../plugins/plasmacalendarplugins/holidaysevents.so
	// Holidays stores the region in:
	//   ~/.config/plasma_calendar_holiday_regions
	//     [General]
	//     selectedRegions=us_en-us,ru_ru

	// PlasmaCalendar.EventPluginsManager.model is EventPluginsManager::pluginsModel()
	// Which is only useful for the config to select the plugins.
	// We need EventPluginsManager::plugins() to iterate the plugins, but it isn't exposed to QML.
	// So we need to use PlasmaCalendar.Calendar which has a DaysModel property that has a function
	// to get a list of events for a specific day.

	Component.onCompleted: {
		syncEnabledPlugins()
		if (pimEventsPluginEnabled()) {
			readAkonadiColors()
		}
	}
	Connections {
		target: plasmoid.configuration
		function onEnabledCalendarPluginsChanged() {
			syncEnabledPlugins()
		}
		function onEnabledCalendarPluginsAllowEmptyChanged() {
			syncEnabledPlugins()
		}
	}

	// From: kdeclarative/.../MonthView.qml
	PlasmaCalendar.Calendar {
		id: calendarBackend

		days: 7
		weeks: 6
		firstDayOfWeek: {
			if (plasmoid.configuration.firstDayOfWeek === -1) {
				return Qt.locale().firstDayOfWeek
			} else {
				return plasmoid.configuration.firstDayOfWeek
			}
		}
		today: timeModel.currentTime

		Component.onCompleted: {
			//daysModel.connect
			if (daysModel && ensureEventPluginsManager() && typeof daysModel.setPluginsManager === "function") {
				try {
					daysModel.setPluginsManager(eventPluginsManager)
				} catch (e) {
					logger.debug('daysModel.setPluginsManager failed', e)
				}
			}
		}
	}

	readonly property var eventTypeLabels: ({
		holidays: [
			i18ndc("plasmashellprivateplugin", "Agenda listview section title", "Holidays"),
			i18ndc("libplasma6", "Agenda listview section title", "Holidays"),
			i18ndc("libplasma5", "Agenda listview section title", "Holidays"),
			i18n("Holidays"),
		],
		events: [
			i18ndc("plasmashellprivateplugin", "Agenda listview section title", "Events"),
			i18ndc("libplasma6", "Agenda listview section title", "Events"),
			i18ndc("libplasma5", "Agenda listview section title", "Events"),
			i18n("Events"),
		],
		todo: [
			i18ndc("plasmashellprivateplugin", "Agenda listview section title", "Todo"),
			i18ndc("libplasma6", "Agenda listview section title", "Todo"),
			i18ndc("libplasma5", "Agenda listview section title", "Todo"),
			i18n("Todo"),
		],
		other: [
			i18ndc("plasmashellprivateplugin", "Means 'Other calendar items'", "Other"),
			i18ndc("libplasma6", "Means 'Other calendar items'", "Other"),
			i18ndc("libplasma5", "Means 'Other calendar items'", "Other"),
			i18n("Other"),
		],
	})
	function isEventType(dayItem, labels) {
		for (var i = 0; i < labels.length; i++) {
			if (dayItem.eventType === labels[i]) {
				return true
			}
		}
		return false
	}
	function parseCalendarId(dayItem) {
		// dayItem.eventType is translated, but is the only way to tell which plugin it belongs to without
		// creating a seperate PlasmaCalendar.EventPluginsManager for each plugin (assuming it's not a singleton).
		// https://github.com/KDE/plasma-framework/blob/master/src/declarativeimports/calendar/eventdatadecorator.cpp#L60
		// Plasma 6 translates them in the "plasmashellprivateplugin" domain, older versions in
		// "libplasma5"/"libplasma6".
		if (isEventType(dayItem, eventTypeLabels.holidays)) {
			return calendarManagerId + "_Holidays"
		} else if (isEventType(dayItem, eventTypeLabels.events)) {
			// By color: the closest to a calendar the plugin tells (pimColorCalendars).
			var colorKey = PlasmaCalendarUtils.colorKey(dayItem.eventColor)
			return calendarManagerId + (colorKey ? "_EventsColor_" + colorKey : "_Events")
		} else if (isEventType(dayItem, eventTypeLabels.todo)) {
			return calendarManagerId + "_Todo"
		} else if (isEventType(dayItem, eventTypeLabels.other)) {
			return calendarManagerId + "_Other"
		} else {
			return calendarManagerId + "_NotImplemented"
		}
	}

	function parseEventsForDate(day, dayEvents) {
		var items = []
		for (var i = 0; i < dayEvents.length; i++) {
			var dayItem = dayEvents[i]

			var start = {}
			var end = {}

			// The dayItem.___DateTime might be "Invalid Date"
			// Eg: the "Astronomical Events" plugin
			var startDateTime = new Date(Shared.isValidDate(dayItem.startDateTime) ? dayItem.startDateTime : day)
			var endDateTime = new Date(Shared.isValidDate(dayItem.endDateTime) ? dayItem.endDateTime : day)
			
			if (dayItem.isAllDay) {
				start.date = Shared.localeDateString(startDateTime) // 2018-01-31
				// Google Calendar has the event start at midnight, and end at midnight the next day
				// Plasma has the date end on the same day, so we need to add 1 day to it so
				// the rest of our code stack works.
				var endDate = new Date(endDateTime)
				endDate.setDate(endDate.getDate() + 1)
				end.date = Shared.localeDateString(endDate) // 2018-01-31
				endDateTime = new Date(end.date)
			} else {
				start.dateTime = startDateTime
				end.dateTime = endDateTime
			}
			var calendarId = parseCalendarId(dayItem)
			var eventId = calendarId + "_" + startDateTime.getTime() + "_" + endDateTime.getTime()

			var isHoliday = calendarId === calendarManagerId + "_Holidays"
			var eventColor = isHoliday ? holidayColor : (dayItem.eventColor || Kirigami.Theme.highlightColor)
			eventColor = "" + eventColor // Cast to string, as dayItem.eventColor is a QColor which JSON treats as an object

			var event = {
				"id": eventId,
				"calendarId": calendarId,
				"htmlLink": "",
				"summary": dayItem.title,
				"description": dayItem.description,
				"start": start,
				"end": end,
				"backgroundColor": eventColor,
			}
			items.push(event)
		}
		return items
	}

	function getEventsForDuration(dateMin, dateMax) {
		var numDays = 0
		for (var day = new Date(dateMin); day < dateMax; day.setDate(day.getDate() + 1)) {
			numDays += 1
		}
		// CalendarBackend needs the actual month we're looking at. We can't arbitrarily grab events for random days.
		var middleDay = new Date(dateMin)
		middleDay.setDate(middleDay.getDate() + Math.floor(numDays/2))
		calendarBackend.displayedDate = middleDay

		var items = []
		
		// 2018-05-24T00:00:00.000Z
		var dateMinUtcStr = Shared.localeDateString(dateMin) + 'T00:00:00.000Z'
		var dateMinUtc = new Date(dateMinUtcStr)

		for (var day = new Date(dateMinUtc); day < dateMax; day.setDate(day.getDate() + 1)) {
			var dayEvents = calendarBackend.daysModel.eventsForDate(day)
			if (dayEvents.length) {
				logger.debugJSON('PlasmaCalendar.dayEvents', {
					date: day.toISOString(),
					count: dayEvents.length,
				})
			}
			items = items.concat(parseEventsForDate(day, dayEvents))
		}

		// Plasma may return the same parsed item more than once for multi-day/plugin events.
		items = PlasmaCalendarEventState.dedupeParsedEvents(items)

		return items
	}

	onFetchAllCalendars: {
		var allEvents = getEventsForDuration(dateMin, dateMax)
		// Akonadi events in a color only Akonadi's copies of signed-in Google calendars have: theirs.
		var mirroredKeys = PlasmaCalendarUtils.mirroredColorKeys(
			PlasmaCalendarUtils.pimCalendarRows(calendarModel, Qt.UserRole, Qt.DisplayRole), akonadiColors, mirroredCollections)
		allEvents = allEvents.filter(function(event) {
			var prefix = calendarManagerId + "_EventsColor_"
			return event.calendarId.indexOf(prefix) !== 0 || !mirroredKeys[event.calendarId.slice(prefix.length)]
		})

		// Filter events into seperate calendars
		var calendarIdList = []
		var calendars = {}
		for (var i = 0; i < allEvents.length; i++) {
			var event = allEvents[i]
			if (calendarIdList.indexOf(event.calendarId) === -1) {
				calendarIdList.push(event.calendarId)
				calendars[event.calendarId] = []
			}
			calendars[event.calendarId].push(event)
		}
		var pimEvents = allEvents.filter(function(event) {
			return event.calendarId.indexOf(calendarManagerId + "_Events") === 0
		})
		updatePimEventsColor(pimEvents)
		updatePimColorCalendars(pimEvents)
		if (pimEvents.length > 0) {
			readAkonadiColors()
		}
		for (var i = 0; i < calendarIdList.length; i++) {
			var calendarId = calendarIdList[i]
			var calendarEvents = calendars[calendarId]
			setCalendarData(calendarId, {
				"items": calendarEvents
			})
		}

		// Register calendars we didn't fetch so we can create events with them
		var calendarList = getCalendarList()
		for (var i = 0; i < calendarList.length; i++) {
			var calendar = calendarList[i]
			if (calendarIdList.indexOf(calendar.id) >= 0) {
				continue
			}
			setCalendarData(calendar.id, {
				"items": [],
			})
		}
	}

	function parseCalendarData(calendarId, data) {
		data.items.forEach(function(event) {
			event.canEdit = false
		})
	}

	//--- Create
	// time: 'HH:mm' for an hour long event (to 23:59 at most), '' for an all-day one.
	function createEvent(calendarId, date, text, time) {
		if (calendarId.indexOf('plasma_Events_') !== 0) {
			logger.log('Could not create event: unknown calendar')
			return
		}
		var akonadiCalendarId = calendarId.substr('plasma_Events_'.length)
		if (!/^[0-9]+$/.test(akonadiCalendarId)) {
			logger.log('Could not parse the Akonadi calendar id')
			return
		}
		var dateString = Shared.localeDateString(date || new Date()) // Local day: toISOString would be UTC

		// konsolekalendar --add --calendar 12 --summary "Summary" --date 2020-07-27 --time 22:00
		var cmd = [
			'konsolekalendar',
			'--add',
			'--calendar',
			akonadiCalendarId,
			'--date',
			dateString,
			'--summary',
			text,
		]
		var m = /^(\d{2}):(\d{2})$/.exec(time || '')
		if (m) {
			var endHour = Number(m[1]) + 1
			var end = endHour > 23 ? '23:59' : (endHour < 10 ? '0' : '') + endHour + ':' + m[2]
			cmd.push('--time', time, '--end-time', end)
		}
		executable.execArgv(cmd, function(cmd, exitCode, exitStatus, stdout, stderr){
			logger.debug('konsolekalendar.exitCode', exitCode, exitStatus) // No command line: the title is in it

			if (exitCode === 0) {
				// It takes a few secs for PIM Events to sync with the PlasmaCalendar API.
				// refresh calls deferredUpdate which is a 200ms delay which seems to work.
				refresh()
			}
		})
	}
}
