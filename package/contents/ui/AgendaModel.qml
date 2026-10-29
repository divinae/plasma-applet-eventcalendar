import QtQuick

import "MeetingLink.js" as MeetingLink
import "Shared.js" as Shared
import "Tasks.js" as Tasks

ListModel {
	id: agendaModel
	property var timeModel

	dynamicRoles: false

	property bool populating: false
	property int parseGeneration: 0
	property int parseChunkSize: 50

	// The daily forecast by day (main.qml weatherByDay), applied once the days are filled.
	property var lastWeatherByDay: null
	property var pendingWeatherByDay: null

	property int showNextNumDays: 14
	property bool showAllDaysInMonth: true
	property bool clipEventsOutsideLimits: true
	// A multi-day event broken up into at most this many days.
	readonly property int maxEventDays: 400
	property bool clipEventsFromOtherMonths: true
	property date visibleDateMin: new Date()
	property date visibleDateMax: new Date()
	property date currentMonth: new Date()

	function getDateRange(targetDate) {
		var today = new Date(timeModel.currentTime)

		// We could calculate how many days are shown before the start of the month,
		// like monthView.firstDisplayedDate() does, but it's easier to just fetch
		// a constant 7 days and crop the unused events.
		var targetMonthMin = new Date(targetDate.getFullYear(), targetDate.getMonth(), 1)
		var dateMin = new Date(targetMonthMin.getFullYear(), targetMonthMin.getMonth(), targetMonthMin.getDate() - 7)

		// Same as dateMin, we just add 7 days after the end of the month,
		// instead of using monthView.lastDisplayedDate(), as it's easier.
		// targetMonthMaxExclusive is the first day of the next month,
		// so we only need to add 6 days.
		var targetMonthMaxExclusive = new Date(targetDate.getFullYear(), targetDate.getMonth()+1, 1)
		var monthViewDateMax = new Date(targetMonthMaxExclusive.getFullYear(), targetMonthMaxExclusive.getMonth(), targetMonthMaxExclusive.getDate() + 6)

		// If the targetDate is from today's month, then we need to check if
		// agendaViewDateMax is later than monthViewDateMax.
		var targetMonthContainsToday = targetMonthMin <= today && today < targetMonthMaxExclusive
		var dateMax
		if (targetMonthContainsToday) {
			var agendaViewDateMax = new Date(today.getFullYear(), today.getMonth(), today.getDate() + agendaModel.showNextNumDays)
			dateMax = new Date(Math.max(monthViewDateMax, agendaViewDateMax))
		} else {
			dateMax = monthViewDateMax
		}

		return {
			min: dateMin,
			max: dateMax,
		}
	}

	property var rowSignatures: [] // Per model row, see agendaItemSignature()

	function agendaItemSignature(agendaItem) {
		function time(d) {
			return d ? d.getTime() : 0
		}
		return JSON.stringify([
			agendaItem.date.getTime(),
			agendaItem.events.map(function(e) {
				return [e.id, e.calendarId, e.etag || e.updated || '', e.summary, e.location || '',
					(e.description || '').length, time(e.startDateTime), time(e.endDateTime), e.backgroundColor || '', !!e.canEdit, Shared.myResponse(e),
					e.attendeeGuestCount, e.conflictTitlesText, e.meetingUrl]
			}),
			agendaItem.tasks.map(function(t) {
				return [t.id, t.calendarId, t.etag || t.updated || '', t.summary, !!t.isCompleted, t.parent || '',
					(t.notes || '').length, time(t.startDateTime), t.backgroundColor || '']
			}),
			agendaItem.showWeather, agendaItem.tempLow, agendaItem.tempHigh, agendaItem.weatherIcon,
		])
	}

	function buildAgendaItem(dateTime) {
		return {
			date: new Date(dateTime),
			events: [],
			tasks: [],
			showWeather: false,
			tempLow: 0,
			tempHigh: 0,
			weatherIcon: "",
		};
	}

	// Agenda items are looked up by day through a { dayKey: agendaItem } index
	// instead of scanning the list for every event.
	function indexAgendaItems(agendaItemList) {
		var byDay = {}
		for (var i = 0; i < agendaItemList.length; i++) {
			byDay[Shared.dayKey(agendaItemList[i].date)] = agendaItemList[i]
		}
		return byDay
	}

	function addAgendaItemIfMissing(agendaItemList, byDay, day) {
		var key = Shared.dayKey(day)
		if (byDay[key]) {
			return
		}
		// Order doesn't matter here, the list is sorted afterwards.
		var newAgendaItem = buildAgendaItem(day)
		byDay[key] = newAgendaItem
		agendaItemList.push(newAgendaItem)
	}

	function insertEventAtDate(agendaItemList, byDay, date, eventItem) {
		var key = Shared.dayKey(date)
		var agendaItem = byDay[key]
		if (!agendaItem) {
			agendaItem = buildAgendaItem(date)
			byDay[key] = agendaItem
			agendaItemList.push(agendaItem)
		}
		if (eventItem.kind === 'tasks#task') {
			agendaItem.tasks.push(eventItem)
		} else {
			agendaItem.events.push(eventItem)
		}
	}

	// Subtasks right after their parent task. Linear, and safe with missing / cyclic parents.
	function sortSubTasks(eventList) {
		var orderedItems = []
		var orderedTasks = []
		var taskById = {}
		var childrenByParent = {}
		var visitedTasks = {}
		function taskVisitKey(taskItem) {
			if (taskItem && taskItem.id) {
				return taskItem.id
			}
			return [
				taskItem && taskItem.parent || "",
				taskItem && taskItem.position || "",
				taskItem && taskItem.title || "",
			].join("|")
		}

		for (var i = 0; i < eventList.length; i++) {
			var eventItem = eventList[i]
			if (eventItem.kind === 'tasks#task') {
				orderedTasks.push(eventItem)
				if (eventItem.id) {
					taskById[eventItem.id] = eventItem
				}
			} else {
				orderedItems.push(eventItem)
			}
		}

		for (var j = 0; j < orderedTasks.length; j++) {
			var taskItem = orderedTasks[j]
			var parentId = taskItem.parent || ""
			if (!childrenByParent[parentId]) {
				childrenByParent[parentId] = []
			}
			childrenByParent[parentId].push(taskItem)
		}

		function appendTask(taskItem) {
			var visitKey = taskVisitKey(taskItem)
			if (!taskItem || visitedTasks[visitKey]) {
				return
			}
			visitedTasks[visitKey] = true
			orderedItems.push(taskItem)

			var children = childrenByParent[taskItem.id] || []
			for (var childIndex = 0; childIndex < children.length; childIndex++) {
				appendTask(children[childIndex])
			}
		}

		for (var k = 0; k < orderedTasks.length; k++) {
			var topLevelTask = orderedTasks[k]
			if (!topLevelTask.parent || !taskById[topLevelTask.parent]) {
				appendTask(topLevelTask)
			}
		}

		for (var remainingIndex = 0; remainingIndex < orderedTasks.length; remainingIndex++) {
			appendTask(orderedTasks[remainingIndex])
		}

		eventList.splice(0, eventList.length)
		for (var orderedIndex = 0; orderedIndex < orderedItems.length; orderedIndex++) {
			eventList.push(orderedItems[orderedIndex])
		}
	}

	function parseGCalEvents(data) {
		agendaModel.populating = true

		if (!(data && data.items)) {
			agendaModel.populating = false
			return
		}
		var generation = ++agendaModel.parseGeneration
		// Copy: items is shared with the month view and reminders. Don't sort or rewrite it in place.
		// Events only: tasks are in the Tasks tab and the Day view. (A new array: items is shared with
		// the month view and reminders, so it isn't sorted or rewritten in place.)
		var items = Tasks.withoutTasks(data.items)

		// Sort by start time if event, or position if tasks
		items.sort(function(a,b) {
			var aIsTask = a.kind === 'tasks#task'
			var bIsTask = b.kind === 'tasks#task'
			if (!aIsTask && bIsTask) {
				return -1
			} else if (aIsTask && !bIsTask) {
				return 1
			} else if (aIsTask && bIsTask) {
				var ap = a.position
				var bp = b.position
				if (ap === bp) {
					return 0
				} else if (ap < bp) {
					return -1
				} else { // ap > bp
					return 1
				}
			} else { // neither is task
				return a.startDateTime - b.startDateTime
			}
		})
		sortSubTasks(items)

		var agendaItemList = []
		var byDay = {}
		var itemIndex = 0

		function finalizeAgendaItems() {
			if (generation !== agendaModel.parseGeneration) {
				return
			}

			var today = new Date(timeModel.currentTime)
			var nextNumDaysEndExclusive = new Date(today.getFullYear(), today.getMonth(), today.getDate() + showNextNumDays + 1)
			var currentMonthMin = new Date(currentMonth.getFullYear(), currentMonth.getMonth(), 1)
			var currentMonthMaxExclusive = new Date(currentMonth.getFullYear(), currentMonth.getMonth()+1, 1)
			var currentMonthContainsToday = currentMonthMin <= today && today < currentMonthMaxExclusive

			if (clipEventsFromOtherMonths) {
				// Remove calendar from different months
				agendaItemList = agendaItemList.filter(function(agendaItem) {
					return !(agendaItem.date < currentMonthMin || currentMonthMaxExclusive <= agendaItem.date && nextNumDaysEndExclusive < agendaItem.date)
				})
				byDay = indexAgendaItems(agendaItemList)
			}

			if (showAllDaysInMonth) {
				for (var day = new Date(currentMonthMin); day < currentMonthMaxExclusive; day.setDate(day.getDate() + 1)) {
					addAgendaItemIfMissing(agendaItemList, byDay, day)
				}
			}

			if (currentMonthContainsToday && showNextNumDays > 0) {
				var todayMidnight = Shared.startOfDay(today)
				for (var day = todayMidnight; day < nextNumDaysEndExclusive; day.setDate(day.getDate() + 1)) {
					addAgendaItemIfMissing(agendaItemList, byDay, day)
				}
			}

			// Make sure the agendaItemList is sorted.
			// When we have a in-progress multiday event on the current date,
			// and agendaBreakupMultiDayEvents is false, the current date agendaItem is
			// out of order since the agendaItem is inserted earlier.
			agendaItemList.sort(function(a,b) { return a.date - b.date })

			// Fill in weather before writing to the model so the weather column doesn't flicker.
			var weatherByDay = agendaModel.pendingWeatherByDay || agendaModel.lastWeatherByDay
			agendaModel.pendingWeatherByDay = null
			for (var i = 0; i < agendaItemList.length; i++) {
				var weatherFields = agendaModel.weatherFields(weatherByDay, agendaItemList[i].date)
				if (weatherFields) {
					Object.assign(agendaItemList[i], weatherFields)
				}
			}

			var minCount = Math.min(agendaItemList.length, agendaModel.count)
			var maxCount = Math.max(agendaItemList.length, agendaModel.count)
			// Only rewrite rows whose content changed. Each set() rebuilds the row's
			// nested event/task models and their delegates.
			var signatures = agendaItemList.map(agendaItemSignature)
			for (var i = 0; i < minCount; i++) {
				if (agendaModel.rowSignatures[i] !== signatures[i]) {
					agendaModel.set(i, agendaItemList[i]) // Replace the existing values
				}
			}
			if (agendaItemList.length > agendaModel.count) {
				for (var i = minCount; i < agendaItemList.length; i++) {
					agendaModel.append(agendaItemList[i]) // Add the missing delegates
				}
			} else if (agendaItemList.length < agendaModel.count) {
				agendaModel.remove(minCount, maxCount-minCount) // Remove the extra delegates
			} else { // agendaItemList.length == agendaModel.count
				// skip
			}
			agendaModel.rowSignatures = signatures
			agendaModel.populating = false
		}

		function processChunk() {
			if (generation !== agendaModel.parseGeneration) {
				return
			}
			var end = Math.min(itemIndex + agendaModel.parseChunkSize, items.length)
			var breakupMultiDayEvents = plasmoid.configuration.agendaBreakupMultiDayEvents
			for (; itemIndex < end; itemIndex++) {
				var eventItem = items[itemIndex]
				if (eventItem.kind !== 'tasks#task') {
					// Nested lists summed up once per event (also when on many days): the rows don't
					// walk nested ListModels in bindings (issue #3).
					eventItem = Shared.withPlainSummary(eventItem, MeetingLink.find(eventItem))
				}
				if (breakupMultiDayEvents) {
					// for Max(start, visibleMin) .. Min(end, visibleMax)
					var lowerLimitDate = (agendaModel.clipEventsOutsideLimits && eventItem.startDateTime < agendaModel.visibleDateMin
						? agendaModel.visibleDateMin
						: eventItem.startDateTime
					)
					var upperLimitDate = eventItem.endDateTime
					if (eventItem.end.date) {
						// All Day event "ends" day before.
						upperLimitDate = new Date(eventItem.endDateTime)
						upperLimitDate.setDate(upperLimitDate.getDate() - 1)
					} else if (eventItem.endDateTime > eventItem.startDateTime) {
						// Timed event ending exactly at midnight doesn't occupy the next day.
						upperLimitDate = new Date(eventItem.endDateTime.getTime() - 1)
					}
					if (agendaModel.clipEventsOutsideLimits && upperLimitDate > agendaModel.visibleDateMax) {
						upperLimitDate = agendaModel.visibleDateMax
					}
					// An invalid start or end (NaN) would never pass the end: the start's day only.
					if (isNaN(lowerLimitDate) || isNaN(upperLimitDate)) {
						if (!isNaN(eventItem.startDateTime)) {
							insertEventAtDate(agendaItemList, byDay, eventItem.startDateTime, eventItem)
						}
						continue
					}
					// Compare by day so a timed event crossing midnight also lands on its last day. At most
					// maxEventDays days (an event over years, not clipped to the visible range).
					var eventItemDate = new Date(lowerLimitDate)
					for (var dayCount = 0; dayCount < agendaModel.maxEventDays && !Shared.isDateAfter(eventItemDate, upperLimitDate); dayCount++) {
						insertEventAtDate(agendaItemList, byDay, eventItemDate, eventItem)
						eventItemDate.setDate(eventItemDate.getDate() + 1)
					}
				} else {
					var now = new Date(timeModel.currentTime)
					var inProgress = eventItem.startDateTime <= now && now <= eventItem.endDateTime
					if (inProgress) {
						var today = Shared.startOfDay(now)
						insertEventAtDate(agendaItemList, byDay, today, eventItem)
					} else {
						insertEventAtDate(agendaItemList, byDay, eventItem.startDateTime, eventItem)
					}
				}
			}

			if (itemIndex < items.length) {
				Qt.callLater(processChunk)
				return
			}

			finalizeAgendaItems()
		}

		processChunk()
	}

	// The agenda day's weather fields, or null without a forecast for that day.
	function weatherFields(weatherByDay, date) {
		var forecastItem = weatherByDay ? weatherByDay[Shared.dayKey(date)] : null
		if (!forecastItem) {
			return null
		}
		return {
			tempLow: Math.floor(forecastItem.temp.min),
			tempHigh: Math.ceil(forecastItem.temp.max),
			weatherIcon: forecastItem.iconName || 'weather-severe-alert',
			showWeather: true,
		}
	}

	function applyWeatherForecast(weatherByDay) {
		for (var i = 0; i < agendaModel.count; i++) {
			var weatherFields = agendaModel.weatherFields(weatherByDay, agendaModel.get(i).date)
			if (weatherFields) {
				agendaModel.set(i, weatherFields) // One change signal per row instead of four.
				agendaModel.rowSignatures[i] = null // Row changed outside finalizeAgendaItems.
			}
		}
	}

	// weatherByDay: { Shared.dayKey: daily forecast item } (DayWeather.byDay).
	function parseWeatherForecast(weatherByDay) {
		agendaModel.lastWeatherByDay = weatherByDay
		if (agendaModel.populating) {
			agendaModel.pendingWeatherByDay = weatherByDay
			return
		}
		agendaModel.pendingWeatherByDay = null
		agendaModel.applyWeatherForecast(weatherByDay)
	}

	Component.onCompleted: {
		parseGCalEvents({ "items": [] })
		parseWeatherForecast({})
	}
}
