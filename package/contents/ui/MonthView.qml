/*
 * Copyright 2013  Heena Mahour <heena393@gmail.com>
 * Copyright 2013 Sebastian Kügler <sebas@kde.org>
 * Copyright 2015 Kai Uwe Broulik <kde@privat.broulik.de>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of
 * the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.workspace.calendar as PlasmaCalendar
import org.kde.plasma.core as PlasmaCore

import "EventBuckets.js" as EventBuckets
import "Shared.js" as Shared
import "Tasks.js" as Tasks
import "WeekDrag.js" as WeekDrag

PinchArea {
	id: root

	// false: the popup shows title and navigation in its own header (see currentTitle, goPrevious, ...).
	property bool showHeader: true
	readonly property string currentTitle: stack.currentItem ? stack.currentItem.title : ""
	function goPrevious() {
		if (stack.currentItem) {
			stack.currentItem.previous()
		}
	}
	function goNext() {
		if (stack.currentItem) {
			stack.currentItem.next()
		}
	}
	// Month title click: zoom out to the year / decade view.
	function titleClicked() {
		if (stack.currentItem && !stack.busy) {
			stack.currentItem.headerClicked()
		}
	}

	property alias displayedDate: calendarBackend.displayedDate
	property bool showTooltips: true

	property QtObject date
	property date currentDate
	// The selected day was picked with the keyboard (PopupView): it gets a focus ring.
	property bool keyboardActive: false

	property int borderWidth: 1
	property real borderOpacity: 0.4
	// Islands style (the popup): the grid, with the weekday names and the week numbers, sits in a
	// card (IslandCard), a card gap from the sides and the bottom. The card edge stands in for the
	// grid's outer frame.
	property bool islands: false
	property int headingFontLevel: 1

	property int columns: calendarBackend.days
	property int rows: calendarBackend.weeks

	property alias today: calendarBackend.today
	property bool showWeekNumbers: false
	property bool highlightCurrentDayWeek: true

	readonly property bool currentMonthContainsToday: {
		return daysModel && daysModel.count > 0
			&& firstDisplayedDate() <= today && today <= lastDisplayedDate()
	}

	property alias cellHeight: mainDaysCalendar.cellHeight

	// Opt-in (the popup): with event titles, multi-day events as bars across the days instead of
	// their title in every day. The owner fills spanBars and the reservedRows / hiddenSpanCount
	// roles (EventBuckets.layoutMonth) and fills again when eventRowCapacity changes.
	// Event titles in the day cells (the popup's month view), else the monthEventBadgeType setting.
	property bool eventTitles: false // The popup's Month view: event titles in the days
	// A small month (a small popup): dots for the events instead of titles cut to a letter or two.
	// From the view's own size: a cell's height depends on the badge type (the compact header).
	// About 5 letters of a title (4.5 grid units) and a title row under the day number.
	readonly property bool roomForTitles: width / 7 >= Kirigami.Units.gridUnit * 4.5 && height / 7 >= Kirigami.Units.gridUnit * 2.5
	readonly property bool showsTitles: eventTitles && roomForTitles
	property bool spanBarsEnabled: false
	readonly property bool spanBarsActive: spanBarsEnabled && mainDaysCalendar.eventBadgeType === 'eventTitles'
	property var spanBars: []
	readonly property int eventRowCapacity: mainDaysCalendar.eventTitleRowCapacity
	// Each cell's events (daysModel's order), plain arrays set by setEvents.
	property var dayEvents: []
	property alias daysModel : daysModel

	//--- Dragging events to other days (with event titles): the event moves by whole days, timed
	// events keep their time of day. Ctrl held at the drop: a copy instead. Opt-in (the popup).
	property bool eventDragEnabled: false
	property var eventDragModel: null // The popup's EventModel: loads and saves the dragged events
	// { eventItem, pressIndex, dayIndex, days, targetFirst, targetCount, copy, pending }: day cells
	// are indexes in daysModel. targetFirst / targetCount: the cells the moved event takes.
	// pending: dropped and being saved; the ghost stays until the events are filled again.
	property var eventDragState: null
	function dayCellDate(index) {
		var day = daysModel.get(index)
		return new Date(day.yearNumber, day.monthNumber - 1, day.dayNumber)
	}
	// The loaded event for one from a day cell (those are ListModel copies).
	function loadedEvent(eventItem) {
		var items = eventDragModel && eventDragModel.eventsData ? eventDragModel.eventsData.items : []
		for (var i = 0; i < items.length; i++) {
			if (items[i].id === eventItem.id && items[i].calendarId === eventItem.calendarId) {
				return items[i]
			}
		}
		return null
	}
	function eventDragBegin(eventItem, cellIndex, copy) {
		var item = loadedEvent(eventItem)
		if (!eventDragEnabled || !item || !WeekDrag.canMove(item) || (eventDragState && eventDragState.pending)) {
			return
		}
		eventDragState = {
			eventItem: item,
			pressIndex: cellIndex,
			dayIndex: cellIndex,
			days: 0,
			targetFirst: 0,
			targetCount: 0,
			copy: !!copy,
			pending: false,
		}
		eventDragMove(cellIndex, copy)
	}
	function eventDragMove(cellIndex, copy) {
		var d = eventDragState
		if (!d || d.pending) {
			return
		}
		d.dayIndex = cellIndex
		d.days = WeekDrag.dayDelta(dayCellDate(d.pressIndex), dayCellDate(cellIndex))
		var times = WeekDrag.movedByDays(d.eventItem, d.days)
		d.targetFirst = WeekDrag.dayDelta(dayCellDate(0), times.startDateTime)
		d.targetCount = Shared.eventDayCount({ start: d.eventItem.start, startDateTime: times.startDateTime, endDateTime: times.endDateTime })
		if (copy !== undefined) {
			d.copy = !!copy
		}
		eventDragState = Object.assign({}, d) // A new object, so the preview updates
	}
	function eventDragDrop(copy) {
		var d = eventDragState
		if (!d || d.pending) {
			return
		}
		if (copy !== undefined) {
			d.copy = !!copy
		}
		if (d.days === 0) { // The same day: nothing to do
			eventDragState = null
			return
		}
		d.pending = true
		eventDragState = Object.assign({}, d)
		var times = WeekDrag.movedByDays(d.eventItem, d.days)
		var target = mainDaysCalendar.eventDragTarget
		eventMover.drop(d.eventItem, times.start, times.end, d.copy, target, 0, target.height)
	}
	function eventDragCancel() {
		eventDragState = null
	}
	EventMover {
		id: eventMover
		eventModel: root.eventDragModel
		onCanceled: root.eventDragCancel()
	}
	// The drag was reset (eg: the days were filled again) while the occurrence menu is open: no save.
	onEventDragStateChanged: {
		if (!eventDragState) {
			eventMover.abandon()
		}
	}

	signal dateSelected(date selectedDate)
	// The day cells were recreated (other month, first open, ...): their events must be filled again.
	signal daysRebuilt()
	signal dateClicked(date clickedDate)
	signal dayDoubleClicked(var dayData)

	property QtObject calendarBackend: calendarBackend

	onPinchStarted: function(pinch) { stack.currentItem.transformOrigin = pinch.center }
	onPinchUpdated: function(pinch) {
		var item = stack.currentItem
		if (stack.depth < 3 && pinch.scale < 1) {
			item.transformScale = pinch.scale
			item.opacity = pinch.scale
		} else if (stack.depth > 1 && pinch.scale > 1) {
			item.transformScale = pinch.scale
			item.opacity = (2 - pinch.scale / 2)
		}
	}
	onPinchFinished: function(pinch) {
		var item = stack.currentItem
		if (item.transformScale < 0.7) {
			item.headerClicked()
		} else if (item.transformScale > 1.4) {
			item.activateHighlightedItem()
		} else {
			item.transformScale = 1
			item.opacity = 1
		}
	}

	function setSelectedDate(d) {
		currentDate = d
		dateSelected(currentDate)
	}

	function resetToToday() {
		calendarBackend.resetToToday()
		setSelectedDate(calendarBackend.today)
		stack.pop(null)
	}

	// https://stackoverflow.com/questions/1184334/get-number-days-in-a-specified-month-using-javascript
	function daysInMonth(year, month) {
		return new Date(year, month+1, 0).getDate()
	}

	// Implement Calendar.updateData()
	// https://github.com/KDE/plasma-framework/blob/master/src/declarativeimports/calendar/calendar.cpp#L215
	// Month the days model was built for. Selecting a day or "today" in the same month changes
	// displayedDate too; rebuilding then recreated every day cell and its event badges.
	property string builtMonthKey: ""

	function updateMonthOverview() {
		var date = calendarBackend.displayedDate
		var month = date.getMonth() // 0-11
		var year = date.getFullYear()

		var monthKey = year + '-' + month + '-' + calendarBackend.firstDayOfWeek + '-' + calendarBackend.days * calendarBackend.weeks
		if (monthKey === builtMonthKey && daysModel.count > 0) {
			return
		}
		builtMonthKey = monthKey

		daysModel.clear()
		dayEvents = [] // By cell: filled again by setEvents
		var totalDays = calendarBackend.days * calendarBackend.weeks
		var daysBeforeCurrentMonth = 0
		var daysAfterCurrentMonth = 0
		var firstDay = new Date(year, month, 1)
		var firstDayOfWeek = firstDay.getDay() === 0 ? 7 : firstDay.getDay()
		if (calendarBackend.firstDayOfWeek < firstDayOfWeek) {
			daysBeforeCurrentMonth = firstDayOfWeek - calendarBackend.firstDayOfWeek
		} else {
			daysBeforeCurrentMonth = calendarBackend.days - (calendarBackend.firstDayOfWeek - firstDayOfWeek)
		}

		var daysInCurrentMonth = daysInMonth(year, month)
		var daysThusFar = daysBeforeCurrentMonth + daysInCurrentMonth
		if (daysThusFar < totalDays) {
			daysAfterCurrentMonth = totalDays - daysThusFar
		}

		if (daysBeforeCurrentMonth > 0) {
			var previousMonth = new Date(year, month-1, 1)
			var daysInPreviousMonth = daysInMonth(year, month-1)
			for (var i = 0; i < daysBeforeCurrentMonth; i++) {
				var dayData = {}
				dayData.isCurrent = false
				dayData.dayNumber = daysInPreviousMonth - (daysBeforeCurrentMonth - (i + 1))
				dayData.monthNumber = previousMonth.getMonth() + 1
				dayData.yearNumber = previousMonth.getFullYear()
				dayData.showEventBadge = false
				dayData.events = []
				dayData.reservedRows = 0
				dayData.hiddenSpanCount = 0
				daysModel.append(dayData)
			}
		}

		for (var i = 0; i < daysInCurrentMonth; i++) {
			var dayData = {}
			dayData.isCurrent = true
			dayData.dayNumber = i + 1
			dayData.monthNumber = month + 1
			dayData.yearNumber = year
			dayData.showEventBadge = false
			dayData.events = []
			dayData.reservedRows = 0
			dayData.hiddenSpanCount = 0
			daysModel.append(dayData)
		}

		if (daysAfterCurrentMonth > 0) {
			var nextMonth = new Date(year, month+1, 1)
			for (var i = 0; i < daysAfterCurrentMonth; i++) {
				var dayData = {}
				dayData.isCurrent = false
				dayData.dayNumber = i + 1
				dayData.monthNumber = nextMonth.getMonth() + 1
				dayData.yearNumber = nextMonth.getFullYear()
				dayData.showEventBadge = false
				dayData.events = []
				dayData.reservedRows = 0
				dayData.hiddenSpanCount = 0
				daysModel.append(dayData)
			}
		}
		spanBars = []
		daysRebuilt()
	}

	// Fill the day cells with events (plain event items, eg: eventModel.eventsData.items). Tasks are
	// left out (the Tasks view has them): they take no row and aren't counted in "+N".
	// Bucket events per visible day in plain JS first, then write each day to the model once.
	// https://github.com/KDE/plasma-framework/blob/master/src/declarativeimports/calendar/daysmodel.h
	function setEvents(items) {
		// The days are filled again (eg: with a dropped event saved): a drag in progress ends.
		eventDragState = null
		// Not laid out yet (eg: just switched to the month view): fill once the cells have a size,
		// see onEventRowCapacityChanged, so they aren't filled twice in different orders.
		if (spanBarsActive && eventRowCapacity <= 0) {
			return
		}
		items = Tasks.withoutTasks(items)
		var dayTimes = []
		for (var i = 0; i < daysModel.count; i++) {
			var dayData = daysModel.get(i)
			dayTimes.push(new Date(dayData.yearNumber, dayData.monthNumber - 1, dayData.dayNumber).getTime())
		}
		var layout = spanBarsActive
			? EventBuckets.layoutMonth(items, dayTimes, calendarBackend.days, eventRowCapacity)
			: { bars: [], dayEvents: EventBuckets.bucketByDay(items, dayTimes), reservedRows: [], hiddenSpanCount: [] }
		// The events as plain arrays (dayEvents): copying them into the cells' nested ListModels took
		// most of the time of a fill.
		for (var j = 0; j < layout.dayEvents.length; j++) {
			var day = daysModel.get(j)
			var dayEvents = layout.dayEvents[j]
			var reservedRows = layout.reservedRows[j] || 0
			var hiddenSpanCount = layout.hiddenSpanCount[j] || 0
			if (day.reservedRows !== reservedRows) {
				daysModel.setProperty(j, 'reservedRows', reservedRows)
			}
			if (day.hiddenSpanCount !== hiddenSpanCount) {
				daysModel.setProperty(j, 'hiddenSpanCount', hiddenSpanCount)
			}
			var showEventBadge = dayEvents.length > 0 || hiddenSpanCount > 0
			if (day.showEventBadge !== showEventBadge) {
				daysModel.setProperty(j, 'showEventBadge', showEventBadge)
			}
		}
		root.dayEvents = layout.dayEvents
		spanBars = layout.bars
	}

	function updateYearOverview() {
		var year = calendarBackend.displayedDate.getFullYear()

		for (var i = 0, j = monthModel.count; i < j; ++i) {
			monthModel.setProperty(i, "yearNumber", year)
		}
	}

	function updateDecadeOverview() {
		var year = calendarBackend.displayedDate.getFullYear()
		var decade = year - year % 10

		for (var i = 0, j = yearModel.count; i < j; ++i) {
			var label = decade - 1 + i
			yearModel.setProperty(i, "yearNumber", label)
			yearModel.setProperty(i, "label", label)
		}
	}

	// https://github.com/KDE/plasma-framework/blob/master/src/declarativeimports/calendar/calendar.cpp
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

		Component.onCompleted: {
			// Bind after configuration is loaded to prevent calling updateMonthOverview a 3rd time.
			calendarBackend.firstDayOfWeekChanged.connect(function(){
				updateMonthOverview()
				// TODO: Note, this resets the MonthView event badges, the user needs to manually update.
			})
		}

		onTodayChanged: {
			logger.debug('onTodayChanged', displayedDate, today)
			displayedDate = today
		}

		onDisplayedDateChanged: {
			updateMonthOverview()
		}

		onYearChanged: {
			updateMonthOverview()
			updateYearOverview()
			updateDecadeOverview()
		}
	}

	ListModel {
		id: daysModel
		dynamicRoles: true

		Component.onCompleted: {
			updateMonthOverview()
		}
	}

	function firstDisplayedDate() {
		var day = daysModel.get(0)
		if (!day) {
			return null
		}
		return new Date(day.yearNumber, day.monthNumber-1, day.dayNumber)
	}

	function lastDisplayedDate() {
		var day = daysModel.get(daysModel.count - 1)
		if (!day) {
			return null
		}
		return new Date(day.yearNumber, day.monthNumber-1, day.dayNumber)
	}

	ListModel {
		id: monthModel

		Component.onCompleted: {
			for (var i = 0; i < 12; ++i) {
				append({
					label: Qt.locale().standaloneMonthName(i, Locale.LongFormat),
					monthNumber: i + 1,
					isCurrent: true,
				})
			}
			updateYearOverview()
		}
	}

	ListModel {
		id: yearModel

		Component.onCompleted: {
			for (var i = 0; i < 12; ++i) {
				append({
					isCurrent: (i > 0 && i < 11) // first and last year are outside the decade
				})
			}
			updateDecadeOverview()
		}
	}

	IslandCard {
		id: gridCard
		shown: root.islands
		// Edge to edge: the popup's own padding is the margin (a card margin on top of it doubled it).
		anchors.fill: parent

		// Sized by the card (its content).
		QQC2.StackView {
			id: stack

			pushEnter: Transition {
				NumberAnimation {
					duration: Kirigami.Units.longDuration
					property: "opacity"
					from: 0
					to: 1
				}
				NumberAnimation {
					duration: Kirigami.Units.longDuration
					property: "transformScale"
					from: 1.5
					to: 1
				}
			}
			pushExit: Transition {
				NumberAnimation {
					duration: Kirigami.Units.longDuration
					property: "opacity"
					from: 1
					to: 0
				}
			}

			popEnter: Transition {
				NumberAnimation {
					duration: Kirigami.Units.longDuration
					property: "opacity"
					from: 0
					to: 1
				}
			}
			popExit: Transition {
				id: popExit
				NumberAnimation {
					duration: Kirigami.Units.longDuration
					property: "opacity"
					from: 1
					to: 0
				}
				NumberAnimation {
					duration: Kirigami.Units.longDuration
					property: "transformScale"
					// so no matter how much you scaled, it would still fly towards you
					to: popExit.ViewTransition.item.transformScale * 1.5
				}
			}

			initialItem: DaysCalendar {
				id: mainDaysCalendar
				dayEvents: root.dayEvents
				// The month's standalone name ("Listopad", not the "listopada" of a date) and the
				// year; no day.
				title: {
					var shown = calendarBackend.displayedDate
					var name = Qt.locale().standaloneMonthName(shown.getMonth(), Locale.LongFormat)
					name = name.charAt(0).toLocaleUpperCase() + name.slice(1)
					return name + " " + shown.getFullYear()
				}

				columns: calendarBackend.days
				rows: calendarBackend.weeks

				showWeekNumbers: root.showWeekNumbers
				spanBars: root.spanBarsActive ? root.spanBars : []
				eventDragEnabled: root.eventDragEnabled
				eventDrag: root.eventDragState
				eventBadgeType: root.showsTitles ? 'eventTitles' : root.eventTitles ? 'dots' : plasmoid.configuration.monthEventBadgeType

				headerModel: calendarBackend.days
				gridModel: daysModel

				dateMatchingPrecision: PlasmaCalendar.Calendar.MatchYearMonthAndDay

				previousLabel: i18nd("libplasma5", "Previous Month")
				nextLabel: i18nd("libplasma5", "Next Month")

				onPrevious: calendarBackend.previousMonth()
				onNext: calendarBackend.nextMonth()
				onHeaderClicked: {
					stack.push(yearOverview)
				}
				onActivated: function(index, date, item) {
					root.date = date
					var dt = new Date(date.yearNumber, date.monthNumber - 1, date.dayNumber)
					root.setSelectedDate(dt)
					root.dateClicked(dt)
				}
				onDoubleClicked: function(index, date, item) {
					root.dayDoubleClicked(date)
				}
			}
		}
	}

	Component {
		id: yearOverview

		DaysCalendar {
			title: calendarBackend.displayedDate.getFullYear()
			columns: 3
			rows: 4

			dateMatchingPrecision: PlasmaCalendar.Calendar.MatchYearAndMonth

			gridModel: monthModel

			previousLabel: i18nd("libplasma5", "Previous Year")
			nextLabel: i18nd("libplasma5", "Next Year")

			onPrevious: calendarBackend.previousYear()
			onNext: calendarBackend.nextYear()
			onHeaderClicked: {
				updateDecadeOverview()
				stack.push(decadeOverview)
			}
			onActivated: function(index, date, item) {
				calendarBackend.goToMonth(date.monthNumber)
				stack.pop()
			}
		}
	}

	Component {
		id: decadeOverview

		DaysCalendar {
			readonly property int decade: {
				var year = calendarBackend.displayedDate.getFullYear()
				return year - year % 10
			}

			title: decade + " – " + (decade + 9)
			columns: 3
			rows: 4

			dateMatchingPrecision: PlasmaCalendar.Calendar.MatchYear

			gridModel: yearModel

			previousLabel: i18nd("libplasma5", "Previous Decade")
			nextLabel: i18nd("libplasma5", "Next Decade")

			onPrevious: calendarBackend.previousDecade()
			onNext: calendarBackend.nextDecade()
			onActivated: function(index, date, item) {
				calendarBackend.goToYear(date.yearNumber)
				stack.pop()
			}
		}
	}

	Component.onCompleted: {
		setSelectedDate(calendarBackend.today)
	}
}
