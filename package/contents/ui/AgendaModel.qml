import QtQuick

import "Shared.js" as Shared

ListModel {
	id: agendaModel
	property var eventModel
	property var timeModel

	dynamicRoles: false

	property bool populating: false
	property int parseGeneration: 0
	property int parseChunkSize: 50

	property bool showDailyWeather: false
	property var lastWeatherData: null
	property var pendingWeatherData: null

	property int showNextNumDays: 14
	property bool showAllDaysInMonth: true
	property bool clipPastEvents: false
	property bool clipPastEventsToday: false
	property bool clipEventsOutsideLimits: true
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
					(e.description || '').length, time(e.startDateTime), time(e.endDateTime), e.backgroundColor || '', !!e.canEdit]
			}),
			agendaItem.tasks.map(function(t) {
				return [t.id, t.calendarId, t.etag || t.updated || '', t.summary, !!t.isCompleted, t.parent || '',
					(t.notes || '').length, time(t.startDateTime), t.backgroundColor || '']
			}),
			agendaItem.showWeather, agendaItem.tempLow, agendaItem.tempHigh, agendaItem.weatherIcon,
			agendaItem.weatherText, agendaItem.weatherDescription, agendaItem.weatherNotes,
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
			weatherText: "",
			weatherDescription: "",
			weatherNotes: "",
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

	function sortSubTasks(eventList) {
		// Place subtasks below their parent task
		for (var i = 0; i < eventList.length; i++) {
			var eventItem = eventList[i]
			if (eventItem.kind === 'tasks#task' && typeof eventItem.parent !== 'undefined') {
				for (var j = 0; j < eventList.length; j++) {
					var parentItem = eventList[j]
					if (parentItem.kind === 'tasks#task' && parentItem.id === eventItem.parent) {
						var foundDestination = false
						for (var k = j+1; k < eventList.length; k++) {
							var childItem = eventList[k]
							if (childItem.kind != 'tasks#task'
								|| childItem.parent != parentItem.id
								|| childItem.position > eventItem.position
							) {
								// Move eventItem from index i => k
								foundDestination = true
								if (i < k) {
									// Since we removed an item before k, decrement the index
									k--
								}
								if (i != k) {
									eventList.splice(i, 1) // Remove at index=i
									eventList.splice(k, 0, eventItem) // Add at index=k
									i-- // Since eventItem was moved, we need to check index=i again.
								}
								break
							}
						} // end loop k

						if (!foundDestination) {
							// Move eventItem from index i => end of list
							var k = eventList.length - 1
							if (i != k) {
								eventList.splice(i, 1) // Remove at index=i
								eventList.push(eventItem)
								i-- // Since eventItem was moved, we need to check index=i again.
							}
						}

						break
					}
				} // end loop j
			}
		} // end loop i
	}

	function parseGCalEvents(data) {
		agendaModel.populating = true

		if (!(data && data.items)) {
			agendaModel.populating = false
			return
		}
		var generation = ++agendaModel.parseGeneration
		// Copy: items is shared with the month view and reminders. Don't sort or rewrite it in place.
		var items = data.items.slice()

		if (plasmoid.configuration.agendaPlaceOverdueTasksOnToday) {
			for (var i = 0; i < items.length; i++) {
				var eventItem = items[i]
				if (eventItem.kind == 'tasks#task'
					&& eventItem.due
					&& !eventItem.isCompleted
				) {
					var now = new Date(timeModel.currentTime)
					var taskIsOverdue = eventItem.dueEndTime < now
					if (taskIsOverdue) {
						eventItem = Object.assign({}, eventItem)
						eventItem.start = {
							date: Shared.localeDateString(now),
						}
						eventItem.end = {
							date: Shared.localeDateString(now),
						}
						eventItem.startDateTime = now
						eventItem.endDateTime = now
						items[i] = eventItem
					}
				}
			}
		}

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
			
			if (clipPastEvents) {
				// Remove calendar events before today.
				var minDate = today
				if (!clipPastEventsToday) {
					minDate = Shared.startOfDay(today)
				}
				agendaItemList = agendaItemList.filter(function(agendaItem) {
					return !(agendaItem.date < minDate)
				})
			}

			// Make sure the agendaItemList is sorted.
			// When we have a in-progress multiday event on the current date,
			// and agendaBreakupMultiDayEvents is false, the current date agendaItem is
			// out of order since the agendaItem is inserted earlier.
			agendaItemList.sort(function(a,b) { return a.date - b.date })

			// Fill in weather before writing to the model so the weather column doesn't flicker.
			var weatherData = agendaModel.pendingWeatherData || agendaModel.lastWeatherData
			agendaModel.pendingWeatherData = null
			var weatherByDay = agendaModel.weatherFieldsByDay(weatherData)
			var showWeatherColumn = false
			for (var i = 0; i < agendaItemList.length; i++) {
				var weatherFields = weatherByDay[Shared.dayKey(agendaItemList[i].date)]
				if (weatherFields) {
					Object.assign(agendaItemList[i], weatherFields)
					showWeatherColumn = true
				}
			}
			if (weatherData) {
				agendaModel.showDailyWeather = showWeatherColumn
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
					// Compare by day so a timed event crossing midnight also lands on its last day.
					for (var eventItemDate = new Date(lowerLimitDate); !Shared.isDateAfter(eventItemDate, upperLimitDate); eventItemDate.setDate(eventItemDate.getDate() + 1)) {
						insertEventAtDate(agendaItemList, byDay, eventItemDate, eventItem)
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

	function weatherFieldsByDay(data) {
		var byDay = {}
		if (!(data && data.list)) {
			return byDay
		}
		for (var j = 0; j < data.list.length; j++) {
			var forecastItem = data.list[j]
			var key = Shared.dayKey(new Date(forecastItem.dt * 1000))
			byDay[key] = {
				tempLow: Math.floor(forecastItem.temp.min),
				tempHigh: Math.ceil(forecastItem.temp.max),
				weatherIcon: forecastItem.iconName || 'weather-severe-alert',
				weatherText: forecastItem.text || '',
				weatherDescription: forecastItem.description || '',
				weatherNotes: forecastItem.notes || '',
				showWeather: true,
			}
		}
		return byDay
	}

	function applyWeatherForecast(data) {
		if (!(data && data.list)) {
			return
		}

		var weatherByDay = weatherFieldsByDay(data)
		var showWeatherColumn = false
		for (var i = 0; i < agendaModel.count; i++) {
			var weatherFields = weatherByDay[Shared.dayKey(agendaModel.get(i).date)]
			if (weatherFields) {
				agendaModel.set(i, weatherFields) // One change signal per row instead of seven.
				agendaModel.rowSignatures[i] = null // Row changed outside finalizeAgendaItems.
				showWeatherColumn = true
			}
		}
		agendaModel.showDailyWeather = showWeatherColumn
	}

	function parseWeatherForecast(data) {
		agendaModel.lastWeatherData = data
		if (agendaModel.populating) {
			agendaModel.pendingWeatherData = data
			return
		}
		agendaModel.pendingWeatherData = null
		agendaModel.applyWeatherForecast(data)
	}

	Component.onCompleted: {
		parseGCalEvents({ "items": [] })
		parseWeatherForecast({ "list": [] })
	}
}
