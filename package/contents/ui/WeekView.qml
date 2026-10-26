import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3

import "EventBuckets.js" as EventBuckets
import "LocaleFuncs.js" as LocaleFuncs
import "MeetingLink.js" as MeetingLink
import "Shared.js" as Shared
import "Tasks.js" as Tasks
import "TimeZone.js" as TimeZone
import "WeekDrag.js" as WeekDrag
import "lib/ColorUtil.js" as ColorUtil

// Week view like Google Calendar: hour grid with event blocks, all-day row on top.
Item {
	id: weekView

	property var eventModel
	// The popup header shows the title and the navigation (goPrevious, goNext, goToday).
	function goPrevious() {
		weekStart = dayDate(-dayCount)
	}
	function goNext() {
		weekStart = dayDate(dayCount)
	}
	// The week (or day) with today; when it's shown already, still relaid and scrolled once.
	function goToday() {
		var start = startOfWeek(currentTime)
		if (start.getTime() !== weekStart.getTime()) {
			weekStart = start // onWeekStartChanged
		} else {
			resetScroll()
			rebuild()
		}
	}
	readonly property date currentTime: timeModel.currentTime
	property date weekStart: startOfWeek(currentTime)
	// 7: week view. 1: today / day view (the same hour grid with one wide column).
	property int dayCount: 7
	readonly property bool singleDay: dayCount === 1
	// Day view: the tasks strip above the hour grid is open (this session).
	property bool dayTasksExpanded: true
	// Week view without the weekend (the locale's working days). Still whole weeks: navigation and
	// weekStart (the first day of week setting) stay the same, only the columns change.
	property bool workWeek: false
	// The shown days, as offsets from weekStart, one per column in week order.
	readonly property var columnDays: {
		if (workWeek && !singleDay) {
			return Shared.workDayOffsets(weekStart.getDay(), Qt.locale().weekDays)
		}
		var all = []
		for (var i = 0; i < dayCount; i++) {
			all.push(i)
		}
		return all
	}
	readonly property int columnCount: columnDays.length
	// Weather from the popup (Logic). weatherByDay: Shared.dayKey -> daily item.
	property var weatherByDay: ({})
	property var weatherHourly: []
	property var weatherCurrent: null
	property bool weatherIsSetup: false
	property bool weatherLoading: false
	property string weatherError: "" // The last forecast request failed
	signal weatherRetryRequested()
	readonly property bool showWeather: Object.keys(weatherByDay).length > 0 || weatherIsSetup

	// Day view: the weather on the left of the day grid (capped width) and the day's tasks on its
	// right, all centered. Not enough room: the tasks become a strip above the grid, then the
	// weather a compact row above it.
	readonly property real sidePanelWidth: Math.round(Math.min(Kirigami.Units.gridUnit * 13, Math.max(Kirigami.Units.gridUnit * 10, width * 0.25)))
	readonly property real weatherPanelWidth: sidePanelWidth
	// The tasks get more room than the weather: titles are longer than "9°".
	readonly property real tasksPanelWidth: Math.round(Math.min(Kirigami.Units.gridUnit * 19, Math.max(Kirigami.Units.gridUnit * 13, width * 0.34)))
	readonly property real weatherGap: Kirigami.Units.gridUnit // Each side of the space between the grid and a panel
	// Islands style: the hour grid (with the day names and the all-day events) is a card
	// (IslandCard); in the Day view the weather and the tasks are cards too, a card gap apart.
	readonly property bool islands: appletConfig.islands
	readonly property real panelGap: islands ? appletConfig.cardGap : weatherGap * 2 // Between the grid and a panel
	// Islands: room around the cards (sides, bottom), so their rounded corners and shadows show.
	readonly property real islandsEdge: islands ? appletConfig.cardGap : 0
	readonly property real minDayGridWidth: Kirigami.Units.gridUnit * 14
	readonly property bool weatherBeside: singleDay && showWeather && width >= minDayGridWidth + sidePanelWidth + panelGap
	readonly property bool dayHasTaskLists: dayTasksStrip.hasLists
	readonly property bool tasksBeside: singleDay && dayHasTaskLists
		&& width >= minDayGridWidth + tasksPanelWidth + (weatherBeside ? sidePanelWidth + panelGap * 2 : panelGap)
	readonly property real leftPanelSpace: weatherBeside ? sidePanelWidth + panelGap : 0
	readonly property real rightPanelSpace: tasksBeside ? tasksPanelWidth + panelGap : 0
	readonly property real contentWidth: {
		if (!singleDay) {
			return width - islandsEdge * 2
		}
		return Math.min(width - leftPanelSpace - rightPanelSpace - islandsEdge * 2, Kirigami.Units.gridUnit * 32)
	}
	readonly property real contentX: {
		var total = leftPanelSpace + contentWidth + rightPanelSpace
		return Math.round((width - total) / 2) + leftPanelSpace
	}
	readonly property date todayStart: Shared.startOfDay(currentTime)
	function dayWeather(d) {
		return weatherByDay ? weatherByDay[Shared.dayKey(d)] : null
	}
	// Day view: the weather panel follows the shown day.
	readonly property bool showingToday: Shared.startOfDay(weekStart).getTime() === todayStart.getTime()
	// The shown day's daytime hours (7:00 to 19:00) from the hourly forecast.
	function dayHours(d) {
		var from = Shared.startOfDay(d).getTime() + 7 * 3600000
		var to = from + 12 * 3600000
		return (weatherHourly || []).filter(function(item) {
			var t = item.dt * 1000
			return t >= from && t <= to
		})
	}
	onDayCountChanged: goToday()

	// [{ date, allDay: [eventItem], timed: [{ eventItem, start, end, column, columns }] }]
	property var days: []
	// All-day events laid out for the whole week: one bar per event across its days,
	// in the same lane on every day. [{ eventItem, first, last, lane }]
	property var allDayBars: []
	property int allDayLaneCount: 0
	property var allDayHiddenPerDay: [] // Events per day in lanes that aren't shown.

	FontMetrics {
		id: fontMetrics
		font: appletConfig.eventFont // Event text: sets the block line height
	}
	FontMetrics {
		id: eventSmallFontMetrics
		font: appletConfig.eventSmallFont
	}
	FontMetrics {
		id: smallFontMetrics
		font: Kirigami.Theme.smallFont
	}
	readonly property int lineHeight: Math.ceil(fontMetrics.height)
	// The grid has the whole day; scroll for the hours outside the working hours.
	readonly property int firstHour: 0
	readonly property int lastHour: 24 // Exclusive
	readonly property int hourCount: lastHour - firstHour
	// Working hours (settings): they fill the view. Shown first: from the working hours or this
	// week's earliest timed event, whichever is earlier.
	readonly property int workStartHour: plasmoid.configuration.weekViewStartHour
	readonly property int workEndHour: Math.max(workStartHour + 1, plasmoid.configuration.weekViewEndHour)
	property int rangeFirstHour: workStartHour
	readonly property int minHourHeight: lineHeight + 6
	readonly property real hourHeight: Math.max(minHourHeight, flickable.height / (workEndHour - workStartHour))
	// Hour labels: the local ones next to the grid, a second time zone's (settings) left of them.
	readonly property string secondZone: {
		var zone = String(plasmoid.configuration.weekViewSecondTimeZone || "")
		return TimeZone.knows(zone) ? zone : ""
	}
	readonly property int localGutterWidth: Math.ceil(Math.max(smallFontMetrics.advanceWidth(formatHour(23)), smallFontMetrics.advanceWidth(formatHour(12)),
		secondZone ? smallFontMetrics.advanceWidth(zoneAbbreviation("")) + Kirigami.Units.smallSpacing : 0)) + Kirigami.Units.smallSpacing * 2
	readonly property int secondGutterWidth: secondZone ? Math.ceil(Math.max(
		smallFontMetrics.advanceWidth(formatZoneTime(23, 45)), smallFontMetrics.advanceWidth(formatZoneTime(12, 45)),
		smallFontMetrics.advanceWidth(zoneAbbreviation(secondZone)))) + Kirigami.Units.smallSpacing : 0
	readonly property int gutterWidth: localGutterWidth + secondGutterWidth
	// The scroll bar gets its own room right of the grid instead of covering the last day.
	readonly property real scrollBarSpace: hourScrollBar.visible ? hourScrollBar.width : 0
	readonly property real columnWidth: Math.max(1, (timeGrid.width - gutterWidth - scrollBarSpace) / columnCount)
	readonly property int allDayRowHeight: Math.round(lineHeight * 2.2) + 6 // Title + date span
	readonly property int maxVisibleAllDayRows: 3
	// Same faint lines as the month grid.
	readonly property color gridLineColor: ColorUtil.setAlpha(Kirigami.Theme.textColor, appletConfig.faintGridLineOpacity)

	function startOfWeek(d) {
		var day = Shared.startOfDay(d)
		if (dayCount < 7) {
			return day // Day view starts on the day itself.
		}
		// The "First day of week" setting (0 = Sunday … 6, -1 = locale), like the month view.
		// Qt.locale().firstDayOfWeek is 1 = Monday … 7 = Sunday.
		var setting = plasmoid.configuration.firstDayOfWeek
		var firstDay = setting >= 0 ? setting : Qt.locale().firstDayOfWeek % 7
		var diff = (day.getDay() - firstDay + 7) % 7
		day.setDate(day.getDate() - diff)
		return day
	}
	function dayDate(i) {
		return new Date(weekStart.getFullYear(), weekStart.getMonth(), weekStart.getDate() + i)
	}
	// The day shown in column `column`.
	function columnDate(column) {
		return dayDate(columnDays[column])
	}
	// The column showing the day starting at `dayStart` (ms), -1 when it isn't shown.
	function columnOfDay(dayStart) {
		for (var i = 0; i < columnCount; i++) {
			if (columnDate(i).getTime() === dayStart) {
				return i
			}
		}
		return -1
	}
	function formatHour(hour) {
		return formatZoneTime(hour, 0)
	}
	function formatZoneTime(hours, minutes) {
		var d = new Date(2000, 0, 1, hours, minutes)
		return Qt.formatTime(d, appletConfig.clock24h ? 'HH:mm' : (minutes ? 'h:mm AP' : 'h AP'))
	}
	// The second zone's clock at a local hour of the first shown day. When the time difference
	// changes during the shown days (a DST switch), the header says so (secondZoneShifts).
	function secondZoneLabel(hour) {
		var day = columnDate(0)
		var instant = new Date(day.getFullYear(), day.getMonth(), day.getDate(), hour).getTime()
		var wall = TimeZone.wallClock(secondZone, instant)
		return wall ? formatZoneTime(wall.hours, wall.minutes) : ""
	}
	// Short zone names for the hour column header: the local one from Qt, the other from tz rules.
	// Both names when it changes between the first and last shown day (eg: "EDT/EST").
	function zoneAbbreviationAt(zone, ms) {
		return zone ? TimeZone.abbreviation(zone, ms) : Qt.formatDateTime(new Date(ms), "t")
	}
	function zoneAbbreviation(zone) {
		var first = zoneAbbreviationAt(zone, columnDate(0).getTime() + 12 * 3600000)
		var last = zoneAbbreviationAt(zone, columnDate(columnCount - 1).getTime() + 12 * 3600000)
		return first === last ? first : first + "/" + last
	}
	// Whether the second zone's hour labels (of the first shown day) are off for some shown days.
	readonly property bool secondZoneShifts: {
		if (!secondZone || columnCount < 2) {
			return false
		}
		var first = columnDate(0).getTime() + 12 * 3600000
		var last = columnDate(columnCount - 1).getTime() + 12 * 3600000
		var difference = function(ms) {
			return TimeZone.offsetAt(secondZone, ms) + new Date(ms).getTimezoneOffset()
		}
		return difference(first) !== difference(last)
	}
	function isToday(d) {
		return Shared.isSameDate(d, currentTime)
	}

	readonly property string title: {
		if (singleDay) {
			return Qt.formatDate(weekStart, Qt.locale().dateFormat(Locale.LongFormat))
		}
		var first = columnDate(0)
		var last = columnDate(columnCount - 1)
		if (first.getFullYear() !== last.getFullYear()) {
			return Qt.formatDate(first, 'd MMM yyyy') + ' – ' + Qt.formatDate(last, 'd MMM yyyy')
		} else if (first.getMonth() !== last.getMonth()) {
			return Qt.formatDate(first, 'd MMM') + ' – ' + Qt.formatDate(last, 'd MMM yyyy')
		}
		return Qt.formatDate(first, 'd') + ' – ' + Qt.formatDate(last, 'd MMMM yyyy')
	}

	//--- Data
	function rebuild() {
		// The blocks are recreated: a drag in progress ends, a dropped one shows its saved times.
		dragState = null
		// Events only: tasks are in the Tasks view.
		var items = Tasks.withoutTasks(eventModel && eventModel.eventsData ? eventModel.eventsData.items : [])
		var result = []
		for (var i = 0; i < columnCount; i++) {
			var dayStart = columnDate(i).getTime()
			var dayEnd = dayDate(columnDays[i] + 1).getTime()
			var allDay = []
			var timed = []
			for (var j = 0; j < items.length; j++) {
				var eventItem = items[j]
				if (!eventItem.startDateTime || !eventItem.endDateTime) {
					continue
				}
				var start = eventItem.startDateTime.getTime()
				var end = eventItem.endDateTime.getTime()
				// All-day, or timed but lasting a day or more (shown in the all-day row like Google Calendar).
				var isLong = end - start >= 24 * 60 * 60 * 1000
				if ((eventItem.start && eventItem.start.date) || isLong) {
					// All-day: end is the exclusive midnight. Tasks can have end == start.
					if (end <= start) {
						end = start + 24 * 60 * 60 * 1000
					}
					if (start < dayEnd && end > dayStart) {
						allDay.push(eventItem)
					}
				} else if (start < dayEnd && (end > dayStart || (end <= start && start >= dayStart))) {
					timed.push({
						eventItem: eventItem,
						start: Math.max(start, dayStart),
						end: Math.min(Math.max(end, start), dayEnd),
						dayStart: dayStart,
						// Continues from the previous day / into the next day.
						continued: start < dayStart,
						continues: end > dayEnd,
						column: 0,
						columns: 1,
					})
				}
			}
			allDay.sort(function(a, b) { return a.startDateTime - b.startDateTime })
			layoutTimed(timed)
			result.push({ date: new Date(dayStart), allDay: allDay, timed: timed })
		}
		days = result
		layoutAllDay(result)

		var first = workStartHour
		for (var d = 0; d < result.length; d++) {
			var timedList = result[d].timed
			for (var t = 0; t < timedList.length; t++) {
				var block = timedList[t]
				// A piece continued from the previous day starts at midnight; don't stretch the range for it,
				// it's cut off at the top instead. Same for pieces continuing into the next day.
				if (!block.continued) {
					first = Math.min(first, Math.floor((block.start - block.dayStart) / 3600000))
				}
			}
		}
		rangeFirstHour = Math.max(0, first)
		if (!flickable.userScrolled) {
			scrollToWorkingHours() // Eg: an early event that just loaded
		}
	}

	function layoutAllDay(dayList) {
		// One bar per event from its first to its last day in this week, in lanes; too many lanes:
		// maxVisibleAllDayRows - 1 lanes and a "+N" row.
		var layout = EventBuckets.layoutLanes(dayList.map(function(day) { return day.allDay }), maxVisibleAllDayRows)
		allDayBars = layout.bars
		allDayHiddenPerDay = layout.hiddenPerDay
		allDayLaneCount = layout.laneCount
	}

	// Overlapping events are placed side by side. Greedy columns per cluster of overlapping events.
	function layoutTimed(list) {
		var minVisualDuration = 20 * 60 * 1000 // Short events still take some height.
		list.sort(function(a, b) {
			return (a.start - b.start) || ((b.end - b.start) - (a.end - a.start))
		})
		var cluster = []
		var columnEnds = []
		var clusterEnd = 0
		function flush() {
			for (var k = 0; k < cluster.length; k++) {
				cluster[k].columns = columnEnds.length
			}
			cluster = []
			columnEnds = []
			clusterEnd = 0
		}
		for (var i = 0; i < list.length; i++) {
			var item = list[i]
			var visualEnd = Math.max(item.end, item.start + minVisualDuration)
			if (cluster.length && item.start >= clusterEnd) {
				flush()
			}
			var column = -1
			for (var c = 0; c < columnEnds.length; c++) {
				if (columnEnds[c] <= item.start) {
					column = c
					break
				}
			}
			if (column < 0) {
				column = columnEnds.length
				columnEnds.push(visualEnd)
			} else {
				columnEnds[column] = visualEnd
			}
			item.column = column
			cluster.push(item)
			clusterEnd = Math.max(clusterEnd, visualEnd)
		}
		flush()
	}

	onWeekStartChanged: {
		resetScroll()
		rebuild()
	}
	onWorkWeekChanged: rebuild()
	Component.onCompleted: {
		rebuild()
		Qt.callLater(scrollToWorkingHours) // Once the grid has its height
	}

	// Until the user scrolls, the view follows the working hours (and early events once they load).
	function resetScroll() {
		flickable.userScrolled = false
	}
	function scrollToWorkingHours() {
		var showsNow = currentTime >= weekStart && currentTime < dayDate(dayCount)
		var hour = showsNow ? Math.max(rangeFirstHour, currentTime.getHours() - 1) : rangeFirstHour
		// From the grid's height itself: called on height changes, maybe before hourHeight updates.
		var height = Math.max(minHourHeight, flickable.height / (workEndHour - workStartHour))
		flickable.contentY = Math.min((hour - firstHour) * height, Math.max(0, hourCount * height - flickable.height))
	}
	// After the user scrolled: keep the same hour at the top when the hours get taller or shorter.
	property real userTopHour: 0
	onHourHeightChanged: {
		if (flickable.userScrolled) {
			flickable.contentY = Math.min(userTopHour * hourHeight, Math.max(0, hourCount * hourHeight - flickable.height))
		}
	}
	function hourY(ms, dayStart) {
		return ((ms - dayStart) / 3600000 - firstHour) * hourHeight
	}

	//--- Drag & drop: move a timed block (to another time or day) or resize it from its bottom edge.
	// { eventItem, mode: 'move' | 'resize', block, pressY, start, end, dayIndex, pending }.
	// pending: dropped and being saved; the preview stays where it was dropped until the views
	// rebuild with the saved event, or an error puts the block back.
	property var dragState: null
	property point dragPointer // Last pointer position, in flickable (viewport) coordinates
	function timeAtY(y, dayStart) {
		return WeekDrag.timeAtY(y, dayStart, firstHour, hourHeight)
	}
	function dayIndexAtX(x) {
		return WeekDrag.dayIndexAtX(x, gutterWidth, columnWidth, columnCount)
	}
	// Pieces of timed events continuing into another day can't be dragged.
	function canDrag(block) {
		return WeekDrag.canMove(block.eventItem) && !block.continued && !block.continues && !(dragState && dragState.pending)
	}
	// All-day bars (also cut ones: the whole event moves by the days dragged).
	function canDragBar(bar) {
		return WeekDrag.canMove(bar.eventItem) && !(dragState && dragState.pending)
	}
	// copy: Ctrl held (the drop makes a copy); only for moves, not resizing.
	function dragBegin(block, mode, viewportPoint, copy) {
		var item = block.eventItem
		dragState = {
			eventItem: item,
			mode: mode,
			block: block,
			pressY: viewportPoint.y + flickable.contentY,
			start: item.startDateTime,
			end: item.endDateTime,
			dayIndex: Math.max(0, columnOfDay(block.dayStart)), // Column
			copy: mode === 'move' && !!copy,
			pending: false,
		}
		dragMove(viewportPoint, copy)
	}
	function dragMove(viewportPoint, copy) {
		if (!dragState || dragState.pending || dragState.mode === 'days') {
			return
		}
		dragPointer = viewportPoint
		var d = dragState
		var block = d.block
		var dy = viewportPoint.y + flickable.contentY - d.pressY
		var item = d.eventItem
		var times
		if (copy !== undefined) {
			d.copy = d.mode === 'move' && !!copy
		}
		if (d.mode === 'move') {
			d.dayIndex = dayIndexAtX(viewportPoint.x)
			var top = Math.max(0, Math.min(flickable.contentHeight - hourHeight / 4, hourY(block.start, block.dayStart) + dy))
			times = WeekDrag.moved(item.startDateTime, item.endDateTime, timeAtY(top, columnDate(d.dayIndex).getTime()))
		} else {
			var bottom = Math.max(0, Math.min(flickable.contentHeight, hourY(block.end, block.dayStart) + dy))
			times = WeekDrag.resized(item.startDateTime, item.endDateTime, timeAtY(bottom, block.dayStart))
		}
		d.start = times.start
		d.end = times.end
		dragState = Object.assign({}, d) // A new object, so the preview updates
	}
	// copy: Ctrl held at the drop (moves only): a copy at the new times instead of moving the event.
	function dragDrop(copy) {
		var d = dragState
		if (!d || d.pending) {
			return
		}
		if (copy !== undefined) {
			d.copy = d.mode !== 'resize' && !!copy
		}
		var times
		if (d.mode === 'days') {
			if (d.days === 0) {
				dragState = null
				return
			}
			times = WeekDrag.movedByDays(d.eventItem, d.days)
		} else {
			if (d.start.getTime() === d.eventItem.startDateTime.getTime() && d.end.getTime() === d.eventItem.endDateTime.getTime()) {
				dragState = null
				return
			}
			times = WeekDrag.timedTimes(d.eventItem, d.start, d.end)
		}
		d.pending = true
		dragState = Object.assign({}, d)
		var menuParent = d.mode === 'days' ? allDayDragPreview : dragPreview
		eventMover.drop(d.eventItem, times.start, times.end, d.copy, menuParent, 0, menuParent.height)
	}
	function dragCancel() {
		dragState = null
	}

	// All-day bars: dragged between the day columns, the event moves by whole days.
	// dragState { eventItem, mode: 'days', bar, pressIndex, dayIndex, days, start, end, copy, pending }.
	// x: in the all-day row (the same as the hour grid's).
	function dragBeginDays(bar, x, copy) {
		var pressIndex = dayIndexAtX(x)
		dragState = {
			eventItem: bar.eventItem,
			mode: 'days',
			bar: bar,
			pressIndex: pressIndex,
			dayIndex: pressIndex,
			days: 0,
			start: bar.eventItem.startDateTime,
			end: bar.eventItem.endDateTime,
			copy: !!copy,
			pending: false,
		}
		dragMoveDays(x, copy)
	}
	function dragMoveDays(x, copy) {
		var d = dragState
		if (!d || d.pending || d.mode !== 'days') {
			return
		}
		d.dayIndex = dayIndexAtX(x)
		d.days = WeekDrag.dayDelta(columnDate(d.pressIndex), columnDate(d.dayIndex))
		var times = WeekDrag.movedByDays(d.eventItem, d.days)
		d.start = times.startDateTime
		d.end = times.endDateTime
		if (copy !== undefined) {
			d.copy = !!copy
		}
		dragState = Object.assign({}, d)
	}

	EventMover {
		id: eventMover
		eventModel: weekView.eventModel
		onCanceled: weekView.dragCancel()
	}
	// The drag was reset (eg: the blocks were rebuilt) while the occurrence menu is open: no save.
	onDragStateChanged: {
		if (!dragState) {
			eventMover.abandon()
		}
	}
	// Dragging near the top / bottom edge scrolls the grid.
	Timer {
		interval: 30
		repeat: true
		running: !!weekView.dragState && !weekView.dragState.pending && weekView.dragState.mode !== 'days'
		onTriggered: {
			var edge = Math.min(weekView.hourHeight, flickable.height / 4)
			var step = 0
			if (weekView.dragPointer.y < edge) {
				step = -Math.ceil((edge - weekView.dragPointer.y) / 4)
			} else if (weekView.dragPointer.y > flickable.height - edge) {
				step = Math.ceil((weekView.dragPointer.y - flickable.height + edge) / 4)
			}
			var maxY = Math.max(0, flickable.contentHeight - flickable.height)
			var y = Math.max(0, Math.min(maxY, flickable.contentY + step))
			if (y !== flickable.contentY) {
				flickable.contentY = y
				weekView.dragMove(weekView.dragPointer)
			}
		}
	}

	//--- UI
	// Weekend days: tint the whole column, from the day name down through the hours.
	// Adjacent weekend days share one strip.
	Repeater {
		model: {
			var flags = []
			for (var i = 0; i < weekView.columnCount; i++) {
				flags.push(Shared.isWeekend(weekView.columnDate(i)))
			}
			return Shared.runsOf(flags)
		}
		Rectangle {
			// Over the hour grid's card (islands), still faint.
			z: weekView.islands ? 1 : 0
			x: weekView.contentX + gridCard.leftPadding + weekView.gutterWidth + modelData.first * weekView.columnWidth
			y: gridCard.y + gridCard.topPadding + dayNamesRow.y
			width: modelData.count * weekView.columnWidth
			// Down to the bottom of the grid (islands: of its card).
			height: gridCard.y + gridCard.height - gridCard.bottomPadding - y
			radius: 6
			color: Kirigami.Theme.textColor
			opacity: 0.04
		}
	}

	// Day view: the shown day's weather, beside the grid or (too narrow) as a compact row above it.
	component DayWeatherPanel: WeatherPanel {
		isSetup: weekView.weatherIsSetup
		loading: weekView.weatherLoading
		errorText: weekView.weatherError
		onRetryRequested: weekView.weatherRetryRequested()
		isToday: weekView.showingToday
		current: weekView.showingToday ? weekView.weatherCurrent : null
		today: weekView.dayWeather(weekView.weekStart)
	}

	// Left of the grid: the shown day's weather.
	IslandCard {
		visible: weekView.weatherBeside
		shown: weekView.islands
		// Flat: padding on its left (the popup's edge), the same space on the grid side. Islands: a
		// card from the top down, a card gap from the grid.
		x: weekView.islands ? weekView.contentX - weekView.panelGap - weekView.sidePanelWidth
			: weekView.contentX - weekView.weatherGap * 2 - weekView.sidePanelWidth + Kirigami.Units.largeSpacing * 2
		// Top aligned with the day header, like the grid, with a little padding (flat).
		y: weekView.islands ? 0 : gridCard.y + dayNamesRow.y + Kirigami.Units.largeSpacing
		width: weekView.islands ? weekView.sidePanelWidth : weekView.sidePanelWidth - Kirigami.Units.largeSpacing * 2
		// Islands: as tall as the weather (at most down to the bottom edge); flat: the whole height.
		height: weekView.islands ? Math.min(implicitHeight, parent.height - y - weekView.islandsEdge)
			: parent.height - y - Kirigami.Units.largeSpacing

		DayWeatherPanel {
			locationName: plasmoid.configuration.weatherService === 'OpenMeteo' ? plasmoid.configuration.openMeteoLocationName : ""
			hourly: weekView.showingToday ? weekView.weatherHourly : weekView.dayHours(weekView.weekStart)
			nextDays: {
				var list = []
				for (var i = 1; i <= 4; i++) {
					var d = weekView.dayWeather(weekView.dayDate(i))
					if (d) {
						list.push(d)
					}
				}
				return list
			}
		}
	}

	// Right of the grid: the day's tasks (islands: a card as tall as its content).
	IslandCard {
		id: tasksCard
		visible: weekView.tasksBeside
		shown: weekView.islands
		x: weekView.contentX + weekView.contentWidth + (weekView.islands ? weekView.panelGap : weekView.weatherGap * 2)
		y: weekView.islands ? 0 : gridCard.y + dayNamesRow.y + Kirigami.Units.largeSpacing
		width: weekView.islands ? weekView.tasksPanelWidth : weekView.tasksPanelWidth - Kirigami.Units.largeSpacing
		height: implicitHeight

		DayTasksPanel {
			eventModel: weekView.singleDay ? weekView.eventModel : null
			day: weekView.columnDate(0)
			showSeparator: false
			maxListHeight: Math.max(Kirigami.Units.gridUnit * 3, tasksCard.parent.height - tasksCard.y - tasksCard.topPadding - tasksCard.bottomPadding - Kirigami.Units.gridUnit * 5)
		}
	}

	ColumnLayout {
		x: weekView.contentX
		width: weekView.contentWidth
		height: parent.height - weekView.islandsEdge
		spacing: weekView.islands ? appletConfig.cardGap : Kirigami.Units.smallSpacing

		IslandCard {
			visible: weekView.singleDay && weekView.showWeather && !weekView.weatherBeside && weekView.weatherIsSetup
			shown: weekView.islands
			Layout.fillWidth: true
			DayWeatherPanel {
				compact: true
			}
		}

		// Islands: the day's tasks as a strip above the grid's card, in a card of its own (flat: the
		// strip is below the all-day events, dayTasksStrip).
		IslandCard {
			visible: weekView.islands && dayTasksStrip.wanted && dayTasksStrip.hasLists
			shown: weekView.islands
			Layout.fillWidth: true
			DayTasksPanel {
				eventModel: weekView.islands && weekView.singleDay ? weekView.eventModel : null
				day: weekView.columnDate(0)
				collapsible: true
				expanded: weekView.dayTasksExpanded
				onExpandedChanged: weekView.dayTasksExpanded = expanded
				showSeparator: false
				maxListHeight: Math.max(Kirigami.Units.gridUnit * 3, weekView.height * 0.3)
			}
		}

		// The hour grid, with the day names / time zones and the all-day events (islands: a card).
		IslandCard {
			id: gridCard
			shown: weekView.islands
			Layout.fillWidth: true
			Layout.fillHeight: true

			ColumnLayout {
				spacing: Kirigami.Units.smallSpacing

				// Day names. Not in the Today view: the popup header shows the date.
				Row {
					id: dayNamesRow
					Layout.fillWidth: true
					// The Day view: only the time zone names (second time zone).
					Layout.preferredHeight: weekView.singleDay && !weekView.secondZone ? 0 : implicitHeight
					Item {
						width: weekView.gutterWidth
						height: weekView.secondZone ? zoneNamesRow.implicitHeight : 1
						// Time zone names above the hour labels (second time zone).
						Row {
							id: zoneNamesRow
							visible: !!weekView.secondZone
							anchors.bottom: parent.bottom
							PlasmaComponents3.Label {
								width: weekView.secondGutterWidth
								horizontalAlignment: Text.AlignRight
								text: weekView.secondZone ? weekView.zoneAbbreviation(weekView.secondZone) : ""
								font: Kirigami.Theme.smallFont
								opacity: 0.6
								PlasmaComponents3.ToolTip.text: weekView.secondZoneShifts
									? i18nc("%1 = time zone, %2 = a date", "%1\nThe time difference changes during these days: the hours shown are those of %2.",
										weekView.secondZone.replace(/_/g, ' '), Qt.formatDate(weekView.columnDate(0), Qt.locale().dateFormat(Locale.ShortFormat)))
									: weekView.secondZone.replace(/_/g, ' ')
								PlasmaComponents3.ToolTip.visible: secondZoneHover.hovered
								HoverHandler {
									id: secondZoneHover
								}
							}
							PlasmaComponents3.Label {
								width: weekView.localGutterWidth - Kirigami.Units.smallSpacing
								horizontalAlignment: Text.AlignRight
								text: weekView.secondZone ? weekView.zoneAbbreviation("") : ""
								font: Kirigami.Theme.smallFont
								opacity: 0.6
							}
						}
					}
					Repeater {
						model: weekView.columnCount
						Item {
							id: dayHeaderCell
							readonly property date date: weekView.columnDate(index)
							readonly property bool today: weekView.isToday(date)
							readonly property var weather: weekView.dayWeather(date)
							visible: !weekView.singleDay
							width: weekView.columnWidth
							height: dayHeaderColumn.implicitHeight
							opacity: date < weekView.todayStart ? appletConfig.pastOpacity : 1

							Column {
								id: dayHeaderColumn
								width: parent.width
								PlasmaComponents3.Label {
									width: parent.width
									horizontalAlignment: Text.AlignHCenter
									text: Qt.locale().dayName(dayHeaderCell.date.getDay(), Locale.ShortFormat)
									font: Kirigami.Theme.smallFont
									color: dayHeaderCell.today ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
									opacity: dayHeaderCell.today ? 1 : 0.6
								}
								Item {
									width: parent.width
									height: dayNumberLabel.implicitHeight + 4
									Rectangle {
										anchors.centerIn: parent
										width: Math.max(dayNumberLabel.implicitWidth, dayNumberLabel.implicitHeight) + 6
										height: width
										radius: width / 2
										color: Kirigami.Theme.highlightColor
										visible: dayHeaderCell.today
									}
									PlasmaComponents3.Label {
										id: dayNumberLabel
										anchors.centerIn: parent
										text: dayHeaderCell.date.getDate()
										font.weight: Font.Bold
										color: dayHeaderCell.today ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
									}
								}
								// Google working location ("Home", "Office", ...)
								WorkingLocationLabel {
									anchors.horizontalCenter: parent.horizontalCenter
									date: dayHeaderCell.date
									maxWidth: parent.width - 4
									showIcon: dayHeaderCell.width >= Kirigami.Units.gridUnit * 4
								}
							}

							// Week view: small icon and high temperature in the top right corner of the day header.
							Row {
								visible: !weekView.singleDay && !!dayHeaderCell.weather && dayHeaderCell.width >= Kirigami.Units.gridUnit * 5
								anchors.top: parent.top
								anchors.right: parent.right
								anchors.rightMargin: Kirigami.Units.smallSpacing
								spacing: 1
								opacity: 0.7
								Kirigami.Icon {
									anchors.verticalCenter: parent.verticalCenter
									width: Kirigami.Units.iconSizes.small
									height: width
									source: Shared.symbolicIcon(dayHeaderCell.weather ? dayHeaderCell.weather.iconName : "")
									fallback: dayHeaderCell.weather ? dayHeaderCell.weather.iconName : ""
								}
								PlasmaComponents3.Label {
									anchors.verticalCenter: parent.verticalCenter
									text: dayHeaderCell.weather ? Shared.formatTemp(dayHeaderCell.weather.temp.max) : ""
									font: Kirigami.Theme.smallFont
								}
							}
						}
					}
				}

				// Day view: the day's working location (the week view has it in the day header).
				WorkingLocationLabel {
					Layout.leftMargin: weekView.gutterWidth + Kirigami.Units.smallSpacing
					visible: weekView.singleDay && !!text
					date: weekView.columnDate(0)
					maxWidth: weekView.width - weekView.gutterWidth
				}

				// All-day events
				Item {
					id: allDayArea
					Layout.fillWidth: true
					readonly property int rows: Math.min(weekView.allDayLaneCount, weekView.maxVisibleAllDayRows)
					readonly property bool hasHiddenRow: weekView.allDayLaneCount > weekView.maxVisibleAllDayRows
					Layout.preferredHeight: rows * (weekView.allDayRowHeight + 2) + 6
					visible: rows > 0

					Repeater {
						model: weekView.allDayBars
						Rectangle {
							readonly property var bar: modelData
							readonly property var eventItem: bar.eventItem
							readonly property EventStyle eventStyle: EventStyle {
								eventItem: bar.eventItem
							}
							// Light tint of the event color with a full-color stripe and theme text: reads better
							// than a solid bar, also with pastel or (dark theme) darkened colors. With the "bar"
							// event look, all-day events are filled in their color instead (EventStyle).
							readonly property bool solid: appletConfig.barEventLook && eventStyle.allDay
							readonly property bool outlined: eventStyle.unconfirmed
							x: weekView.gutterWidth + bar.first * weekView.columnWidth + 2
							y: 3 + bar.lane * (weekView.allDayRowHeight + 2)
							// Being dragged: faded where it was (not for a copy); dropped: the preview stands in for it.
							readonly property bool dragSource: !!weekView.dragState && weekView.dragState.mode === 'days' && weekView.dragState.eventItem === eventItem
							opacity: (dragSource && !weekView.dragState.copy ? (weekView.dragState.pending ? 0 : 0.35)
								: bar.eventItem.endDateTime <= weekView.todayStart ? appletConfig.pastOpacity : 1) * eventStyle.doneOpacity
							width: (bar.last - bar.first + 1) * weekView.columnWidth - 4
							height: weekView.allDayRowHeight
							// Square ends where the event continues before or after this week.
							// Before the first or after the last shown day (work week: the weekend too).
							readonly property bool cutLeft: bar.eventItem.startDateTime < weekView.columnDate(bar.first)
							readonly property bool cutRight: bar.eventItem.endDateTime > weekView.dayDate(weekView.columnDays[bar.last] + 1)
							readonly property real cornerRadius: Math.min(8, height / 2)
							radius: cornerRadius
							topLeftRadius: cutLeft ? 0 : cornerRadius
							bottomLeftRadius: cutLeft ? 0 : cornerRadius
							topRightRadius: cutRight ? 0 : cornerRadius
							bottomRightRadius: cutRight ? 0 : cornerRadius
							color: solid ? eventStyle.fillColor : outlined ? Kirigami.Theme.backgroundColor : ColorUtil.setAlpha(eventStyle.color, appletConfig.darkTheme ? 0.3 : 0.22)
							border.width: 1
							border.color: solid || outlined ? eventStyle.outlineColor : ColorUtil.setAlpha(eventStyle.color, 0.45)
							readonly property color titleColor: solid ? eventStyle.textColor : Kirigami.Theme.textColor
							clip: true
							// Maybe, or out of office (hatched like Google Calendar). On the light tint, always in
							// the event color (EventStyle.stripeColor is for filled bars).
							StripeFill {
								visible: parent.eventStyle.striped
								anchors.fill: parent
								anchors.margins: 1
								radius: Math.max(0, parent.cornerRadius - 1)
								stripeColor: parent.solid ? parent.eventStyle.stripeColor : parent.eventStyle.color
							}
							// Stripe on the start side (not when the event began before this week), inset so it
							// stays inside the rounded corners.
							Rectangle {
								visible: !parent.cutLeft && !parent.solid
								x: 3
								y: 3
								width: 3
								height: parent.height - 6
								radius: width / 2
								color: parent.eventStyle.color
							}
							// Title, then the date span ("14 – 16 Oct · 3 days") or "All day".
							// Long timed events (24 h+) are in this row too: Shared.eventSpan handles both.
							readonly property var span: Shared.eventSpan(eventItem, appletConfig.timeFormat, weekView.currentTime)
							readonly property string spanText: {
								if (span.allDay && !span.multiDay) {
									return i18n("All day")
								}
								var range = LocaleFuncs.formatRange(span.startText, span.endText)
								return span.allDay ? range + " · " + i18np("%1 day", "%1 days", span.days) : range
							}
							Column {
								anchors.left: parent.left
								anchors.right: parent.right
								anchors.verticalCenter: parent.verticalCenter
								anchors.leftMargin: parent.solid ? 6 : 11
								anchors.rightMargin: 4
								PlasmaComponents3.Label {
									id: allDayTitle
									// Invitation not answered yet: the question mark before the title (Shared.isAwaitingAnswer).
									readonly property bool awaitingAnswer: Shared.isAwaitingAnswer(parent.parent.eventStyle.response)
									readonly property int iconSize: 2 * Math.floor(Math.min(Kirigami.Units.iconSizes.small, height) / 2)
									width: parent.width
									// Never wider than the label: a padding past its width crashed Qt's text layout.
									leftPadding: awaitingAnswer ? Math.min(iconSize + 3, Math.max(0, width - 8)) : 0
									text: eventItem.summary
									textFormat: Text.PlainText // User text: never parsed as HTML
									color: parent.parent.titleColor
									font.family: appletConfig.eventFont.family
									font.pointSize: appletConfig.eventFont.pointSize
									font.weight: Font.DemiBold
									font.strikeout: eventStyle.struckThrough
									elide: Text.ElideRight
									Kirigami.Icon {
										visible: allDayTitle.awaitingAnswer
										anchors.verticalCenter: parent.verticalCenter
										width: allDayTitle.iconSize
										height: width
										roundToIconSize: false
										source: Shared.EVENT_INDICATOR_ICONS.needsAction
										isMask: true
										color: allDayTitle.color
									}
								}
								PlasmaComponents3.Label {
									width: parent.width
									text: spanText
									color: parent.parent.titleColor
									opacity: 0.75
									font: appletConfig.eventSmallFont
									elide: Text.ElideRight
								}
							}
							// Click opens the event, right click its menu, press and drag moves it by days (Ctrl: copies).
							DragMouseArea {
								id: barMouse
								anchors.fill: parent
								eventItem: parent.eventItem
								draggable: weekView.canDragBar(parent.bar)
								mapTo: allDayArea
								onDragStarted: function(from, at, copy) {
									weekView.dragBeginDays(parent.bar, from.x, copy)
									weekView.dragMoveDays(at.x, copy)
								}
								onDragMoved: function(at, copy) { weekView.dragMoveDays(at.x, copy) }
								onDropped: function(copy) { weekView.dragDrop(copy) }
								onDragCanceled: weekView.dragCancel()
							}
							PlasmaCore.ToolTipArea {
								anchors.fill: parent
								mainText: parent.eventItem.summary // Not bound to containsMouse, see EventBar
								subText: weekView.eventModel.eventDetailsText(parent.eventItem)
								textFormat: Text.PlainText
							}
						}
					}

					// Where a dragged all-day bar would go (its lane, moved by the columns dragged), with its new days.
					Rectangle {
						id: allDayDragPreview
						readonly property var info: weekView.dragState && weekView.dragState.mode === 'days' ? weekView.dragState : null
						readonly property int shift: info ? info.dayIndex - info.pressIndex : 0
						readonly property int first: info ? Math.max(0, Math.min(weekView.columnCount - 1, info.bar.first + shift)) : 0
						readonly property int last: info ? Math.max(0, Math.min(weekView.columnCount - 1, info.bar.last + shift)) : 0
						readonly property color stripeColor: info ? appletConfig.eventColor(info.eventItem.backgroundColor) : "transparent"
						readonly property var span: info ? Shared.eventSpan({ start: info.eventItem.start, startDateTime: info.start, endDateTime: info.end }, appletConfig.timeFormat, weekView.currentTime) : null
						z: 3
						visible: !!info
						x: weekView.gutterWidth + first * weekView.columnWidth + 2
						y: info ? 3 + Math.min(info.bar.lane, allDayArea.rows - 1) * (weekView.allDayRowHeight + 2) : 0
						width: (last - first + 1) * weekView.columnWidth - 4
						height: weekView.allDayRowHeight
						radius: Math.min(8, height / 2)
						color: Qt.tint(Kirigami.Theme.backgroundColor, ColorUtil.setAlpha(stripeColor, appletConfig.darkTheme ? 0.45 : 0.35))
						border.width: 1
						border.color: Kirigami.Theme.highlightColor
						Column {
							anchors.left: parent.left
							anchors.right: parent.right
							anchors.verticalCenter: parent.verticalCenter
							anchors.leftMargin: 8
							anchors.rightMargin: 4
							PlasmaComponents3.Label {
								width: parent.width
								text: allDayDragPreview.info ? allDayDragPreview.info.eventItem.summary : ""
								textFormat: Text.PlainText // User text: never parsed as HTML
								font.family: appletConfig.eventFont.family
								font.pointSize: appletConfig.eventFont.pointSize
								font.weight: Font.DemiBold
								elide: Text.ElideRight
							}
							PlasmaComponents3.Label {
								width: parent.width
								readonly property var span: allDayDragPreview.span
								// The new day(s): one day just its date.
								text: !span ? "" : span.allDay && !span.multiDay ? span.startText
									: LocaleFuncs.formatRange(span.startText, span.endText)
								opacity: 0.75
								font: appletConfig.eventSmallFont
								elide: Text.ElideRight
							}
						}
						DragCopyBadge {
							visible: !!allDayDragPreview.info && allDayDragPreview.info.copy
							anchors.right: parent.right
							anchors.verticalCenter: parent.verticalCenter
							anchors.rightMargin: 3
						}
					}

					// "+N" per day for events in lanes that don't fit.
					Repeater {
						model: allDayArea.hasHiddenRow ? weekView.columnCount : 0
						PlasmaComponents3.Label {
							readonly property int hiddenCount: weekView.allDayHiddenPerDay[index] || 0
							visible: hiddenCount > 0
							x: weekView.gutterWidth + index * weekView.columnWidth
							y: 3 + (allDayArea.rows - 1) * (weekView.allDayRowHeight + 2)
							width: weekView.columnWidth
							height: weekView.allDayRowHeight
							horizontalAlignment: Text.AlignHCenter
							verticalAlignment: Text.AlignVCenter
							text: i18nc("more events not shown", "+%1", hiddenCount)
							opacity: 0.7
						}
					}
				}

				// Day view without the weather beside: the day's tasks as a strip that folds away.
				DayTasksPanel {
					id: dayTasksStrip
					Layout.fillWidth: true
					Layout.leftMargin: Kirigami.Units.smallSpacing
					Layout.rightMargin: Kirigami.Units.smallSpacing
					// Also tells whether there are task lists at all (dayHasTaskLists), so it keeps its model.
					readonly property bool wanted: weekView.singleDay && !weekView.tasksBeside
					visible: wanted && hasLists && !weekView.islands
					eventModel: weekView.singleDay ? weekView.eventModel : null
					day: weekView.columnDate(0)
					collapsible: true
					expanded: weekView.dayTasksExpanded
					onExpandedChanged: weekView.dayTasksExpanded = expanded
					maxListHeight: Math.max(Kirigami.Units.gridUnit * 3, weekView.height * 0.3)
				}

				// Hour grid
				Item {
					id: timeGrid
					Layout.fillWidth: true
					Layout.fillHeight: true
					clip: true

					// Frame around the day columns (not the hour labels), with rounded corners.
					Rectangle {
						z: 1
						x: weekView.gutterWidth
						width: weekView.columnWidth * weekView.columnCount
						height: parent.height
						radius: 6
						color: "transparent"
						border.width: 1
						border.color: weekView.gridLineColor
					}

					Flickable {
						id: flickable
						anchors.fill: parent
						contentWidth: width
						contentHeight: weekView.hourCount * weekView.hourHeight
						boundsBehavior: Flickable.StopAtBounds
						PlasmaComponents3.ScrollBar.vertical: PlasmaComponents3.ScrollBar {
							id: hourScrollBar
							onPressedChanged: {
								if (pressed) {
									flickable.userScrolled = true
								} else {
									weekView.userTopHour = flickable.contentY / weekView.hourHeight
								}
							}
						}
						// Opening: scroll to the working hours once the grid has its size, unless scrolled already.
						property bool userScrolled: false
						onMovementStarted: userScrolled = true
						onMovementEnded: weekView.userTopHour = contentY / weekView.hourHeight
						onHeightChanged: {
							if (!userScrolled) {
								weekView.scrollToWorkingHours()
							}
						}

						Item {
							width: flickable.width
							height: flickable.contentHeight

							// Hour lines and labels
							Repeater {
								model: weekView.hourCount
								Item {
									readonly property int hour: weekView.firstHour + index
									y: index * weekView.hourHeight
									width: parent.width
									height: weekView.hourHeight
									// Outside the working hours: a faint shade.
									Rectangle {
										visible: parent.hour < weekView.workStartHour || parent.hour >= weekView.workEndHour
										x: weekView.gutterWidth + 1
										width: weekView.columnWidth * weekView.columnCount - 2
										height: parent.height
										color: Kirigami.Theme.textColor
										opacity: 0.025
									}
									PlasmaComponents3.Label {
										visible: index > 0 && !!weekView.secondZone
										width: weekView.secondGutterWidth
										y: -height / 2
										horizontalAlignment: Text.AlignRight
										text: weekView.secondZone ? weekView.secondZoneLabel(parent.hour) : ""
										font: Kirigami.Theme.smallFont
										opacity: 0.45
									}
									PlasmaComponents3.Label {
										visible: index > 0
										x: weekView.secondGutterWidth
										width: weekView.localGutterWidth - Kirigami.Units.smallSpacing
										y: -height / 2
										horizontalAlignment: Text.AlignRight
										text: weekView.formatHour(parent.hour)
										font: Kirigami.Theme.smallFont
										opacity: 0.6
									}
									Rectangle {
										visible: index > 0
										// Inside the frame, so lines don't darken where they meet it.
										x: weekView.gutterWidth + 1
										width: weekView.columnWidth * weekView.columnCount - 2
										height: 1
										color: weekView.gridLineColor
									}
								}
							}

							// Where a dragged block would go, with its new times.
							Rectangle {
								id: dragPreview
								readonly property var info: weekView.dragState && weekView.dragState.mode !== 'days' ? weekView.dragState : null
								readonly property real dayStart: info ? weekView.columnDate(info.dayIndex).getTime() : 0
								readonly property color barColor: info ? appletConfig.eventColor(info.eventItem.backgroundColor) : "transparent"
								readonly property real topY: info ? Math.max(0, weekView.hourY(info.start.getTime(), dayStart)) : 0
								readonly property real bottomY: info ? Math.min(parent.height, weekView.hourY(info.end.getTime(), dayStart)) : 0
								z: 3
								visible: !!info
								x: info ? weekView.gutterWidth + info.dayIndex * weekView.columnWidth + 2 : 0
								y: topY + 1
								width: weekView.columnWidth - 4
								height: Math.max(weekView.lineHeight + 2, bottomY - topY - 2)
								radius: Math.min(10, height / 2)
								color: ColorUtil.setAlpha(barColor, info && info.pending ? 1 : 0.9)
								border.width: 1
								border.color: Kirigami.Theme.highlightColor
								Column {
									anchors.fill: parent
									anchors.margins: 2
									anchors.leftMargin: 6
									clip: true
									// Too short for two lines: the new times come first, they're what the drag is about.
									readonly property bool oneLine: dragPreview.height < weekView.lineHeight * 2 + 4
									readonly property string timeText: dragPreview.info ? Shared.formatTimeRange(dragPreview.info.start, dragPreview.info.end, appletConfig.timeFormat) : ""
									PlasmaComponents3.Label {
										width: parent.width
										text: dragPreview.info ? (parent.oneLine ? parent.timeText + ' · ' : '') + dragPreview.info.eventItem.summary : ""
										textFormat: Text.PlainText // User text: never parsed as HTML
										color: Shared.contrastTextColor(dragPreview.barColor)
										elide: Text.ElideRight
									}
									PlasmaComponents3.Label {
										width: parent.width
										visible: !parent.oneLine
										text: parent.timeText
										color: Shared.contrastTextColor(dragPreview.barColor)
										font: appletConfig.eventSmallFont
										elide: Text.ElideRight
									}
								}
								DragCopyBadge {
									visible: !!dragPreview.info && dragPreview.info.copy
									anchors.right: parent.right
									anchors.top: parent.top
									anchors.margins: 2
								}
							}

							// Day columns
							Repeater {
								model: weekView.days
								Item {
									id: dayColumn
									readonly property var day: modelData
									readonly property bool today: weekView.isToday(day.date)
									x: weekView.gutterWidth + index * weekView.columnWidth
									width: weekView.columnWidth
									height: parent.height

									Rectangle {
										anchors.fill: parent
										color: Kirigami.Theme.highlightColor
										// Only in the week view: in the day view the whole column is "today".
										opacity: dayColumn.today && !weekView.singleDay ? 0.08 : 0
									}
									// Past part of today (and whole past days): light grey wash.
									Rectangle {
										readonly property real nowY: (weekView.currentTime.getHours() + weekView.currentTime.getMinutes() / 60 - weekView.firstHour) * weekView.hourHeight
										visible: dayColumn.day.date < weekView.todayStart || dayColumn.today
										width: parent.width
										height: dayColumn.day.date < weekView.todayStart ? parent.height : Math.max(0, Math.min(parent.height, nowY))
										color: Kirigami.Theme.textColor
										opacity: 0.04
									}
									// Today: highlight-colored frame around the column (week view only).
									Rectangle {
										visible: dayColumn.today && !weekView.singleDay
										anchors.fill: parent
										anchors.margins: 1
										color: "transparent"
										radius: 6
										border.width: 2
										border.color: ColorUtil.setAlpha(Kirigami.Theme.highlightColor, 0.5)
									}
									Rectangle {
										visible: index > 0 // The frame draws the left edge.
										width: 1
										height: parent.height
										color: weekView.gridLineColor
									}

									// Click an empty spot: new event at that time (rounded down to 30 min), 1 hour long.
									// Hovering previews that slot.
									MouseArea {
										id: slotArea
										anchors.fill: parent
										hoverEnabled: true
										cursorShape: Qt.CrossCursor
										readonly property int slotMinutes: Math.floor((weekView.firstHour + mouseY / weekView.hourHeight) * 60 / 30) * 30
										function slotStart() {
											var start = new Date(dayColumn.day.date)
											start.setMinutes(slotMinutes)
											return start
										}
										onClicked: popup.newEvent(dayColumn.day.date, slotStart())
									}
									Rectangle {
										id: slotPreview
										visible: slotArea.containsMouse
										x: 2
										y: (slotArea.slotMinutes / 60 - weekView.firstHour) * weekView.hourHeight + 1
										width: parent.width - 4
										height: weekView.hourHeight - 2
										radius: Math.min(10, height / 2)
										color: ColorUtil.setAlpha(Kirigami.Theme.highlightColor, 0.15)
										border.width: 1
										border.color: ColorUtil.setAlpha(Kirigami.Theme.highlightColor, 0.6)
										PlasmaComponents3.Label {
											anchors.fill: parent
											anchors.margins: 2
											anchors.leftMargin: 6
											text: {
												var start = slotArea.slotStart()
												var end = new Date(start.getTime() + 60 * 60 * 1000)
												return Shared.formatTimeRange(start, end, appletConfig.timeFormat)
											}
											font: Kirigami.Theme.smallFont
											color: Kirigami.Theme.highlightColor
											elide: Text.ElideRight
										}
									}

									Repeater {
										model: dayColumn.day.timed
										// Click opens the event, right click its menu, press and drag moves it.
										EventBar {
											id: eventBlock
											readonly property var block: modelData
											eventItem: block.eventItem
											detailsModel: weekView.eventModel
											showTitle: false
											readonly property real slotWidth: (dayColumn.width - 3) / block.columns
											// Clip to the visible hour range.
											readonly property real rangeStart: block.dayStart + weekView.firstHour * 3600000
											readonly property real rangeEnd: block.dayStart + weekView.lastHour * 3600000
											readonly property real visibleStart: Math.max(block.start, rangeStart)
											readonly property real visibleEnd: Math.min(Math.max(block.end, block.start + 15 * 60000), rangeEnd)
											dragSource: !!weekView.dragState && weekView.dragState.eventItem === eventItem
											dragCopy: !!weekView.dragState && weekView.dragState.copy
											dragPending: !!weekView.dragState && weekView.dragState.pending
											dimmed: eventItem.endDateTime <= weekView.currentTime
											draggable: weekView.canDrag(block)
											dragMapTo: flickable
											onDragStarted: function(from, at, copy) {
												weekView.dragBegin(block, 'move', from, copy)
												weekView.dragMove(at, copy)
											}
											onDragMoved: function(at, copy) { weekView.dragMove(at, copy) }
											onDropped: function(copy) { weekView.dragDrop(copy) } // Ctrl: a copy
											onDragCanceled: weekView.dragCancel()
											visible: visibleEnd > visibleStart
											x: 2 + block.column * slotWidth
											y: weekView.hourY(visibleStart, block.dayStart) + 1
											width: slotWidth - 1
											height: Math.max(weekView.lineHeight + 2, (visibleEnd - visibleStart) / 3600000 * weekView.hourHeight - 2)
											// Square edges where the event continues beyond what's shown
											// (from the previous day / before the first hour, or past the last one).
											cuttable: true
											cutTop: block.continued || block.start < rangeStart
											cutBottom: block.continues || block.end > rangeEnd
											maxRadius: 10

											// Today view: join button for meetings that haven't ended.
											readonly property var meetingLink: weekView.singleDay && plasmoid.configuration.agendaShowEventHangoutLink && eventItem.endDateTime > weekView.currentTime ? MeetingLink.find(eventItem) : null

											Column {
												z: 1 // Above the block's mouse area: location links take their clicks
												anchors.fill: parent
												anchors.margins: 2
												// Clear of the color bar (bar look), like the month view's rows.
												anchors.leftMargin: eventBlock.showBar ? 9 : 6
												anchors.rightMargin: joinPill.visible ? joinPill.width + Kirigami.Units.smallSpacing * 2 : 2
												clip: true
												PlasmaComponents3.Label {
													width: parent.width
													// Day view, block too short for a second line: put time and location after the title.
													readonly property bool inlineDetails: weekView.singleDay && eventBlock.height < weekView.lineHeight * 2 + 4
													text: {
														var item = eventBlock.eventItem
														if (!inlineDetails) {
															return item.summary
														}
														var parts = [item.summary, Shared.formatTimeRange(item.startDateTime, item.endDateTime, appletConfig.timeFormat)]
														if (item.location) {
															parts.push(item.location)
														}
														return parts.join(' · ')
													}
													color: eventBlock.eventStyle.textColor
													font.family: appletConfig.eventFont.family
													font.pointSize: appletConfig.eventFont.pointSize
													font.strikeout: eventBlock.eventStyle.declined
													font.bold: eventBlock.inProgress // Event in progress
													elide: Text.ElideRight
													wrapMode: Text.WordWrap
													maximumLineCount: Math.max(1, Math.floor((eventBlock.height - 4) / weekView.lineHeight) - 1)
												}
												// Time (day view: and location), then icons for what else is set.
												Row {
													width: parent.width
													visible: eventBlock.height >= weekView.lineHeight * 2 + 4
													spacing: Kirigami.Units.smallSpacing
													// The time first; icons only in the room left.
													PlasmaComponents3.Label {
														id: blockTimeLabel
														width: Math.min(implicitWidth, parent.width)
														text: {
															var format = appletConfig.timeFormat
															var item = eventBlock.eventItem
															// Day view has room for the end time and location (opens in Google Maps).
															if (weekView.singleDay) {
																var text = Shared.formatTimeRange(item.startDateTime, item.endDateTime, format)
																return item.location ? text + ' · ' + Shared.locationLink(item.location) : text
															}
															return Qt.formatTime(item.startDateTime, format)
														}
														textFormat: Text.StyledText
														linkColor: eventBlock.eventStyle.textColor
														onLinkActivated: function(link) { Shared.openExternalUrl(link) }
														color: eventBlock.eventStyle.textColor
														font: appletConfig.eventSmallFont
														elide: Text.ElideRight
													}
													EventIndicators {
														anchors.verticalCenter: parent.verticalCenter
														maxWidth: parent.width - blockTimeLabel.width - parent.spacing
														eventItem: eventBlock.eventItem
														color: eventBlock.eventStyle.textColor
														iconSize: 2 * Math.round(eventSmallFontMetrics.height / 2)
														opacity: 0.85
														// The day view shows the location as text and has a Join button.
														showLocation: !weekView.singleDay
														showMeeting: !joinPill.visible
														// Week view: repeating events (standups, ...) are everywhere, the icon is noise.
														showRepeat: weekView.singleDay
													}
												}
											}
											JoinPill {
												id: joinPill
												visible: !!eventBlock.meetingLink && eventBlock.width >= Kirigami.Units.gridUnit * 10
												anchors.right: parent.right
												anchors.rightMargin: Kirigami.Units.smallSpacing
												// Short blocks: centered and slimmer; taller ones: next to the title.
												readonly property bool compact: eventBlock.height < weekView.lineHeight * 2 + 4
												anchors.verticalCenter: compact ? parent.verticalCenter : undefined
												anchors.top: compact ? undefined : parent.top
												anchors.topMargin: Kirigami.Units.smallSpacing
												verticalPadding: compact ? 0 : Kirigami.Units.smallSpacing / 2
												meetingLink: eventBlock.meetingLink
												textColor: Shared.contrastTextColor(eventBlock.eventStyle.color)
											}
											// Bottom edge: drag to change the end time.
											MouseArea {
												z: 2
												visible: eventBlock.draggable && !eventBlock.cutBottom && eventBlock.height >= weekView.lineHeight * 1.5
												anchors.left: parent.left
												anchors.right: parent.right
												anchors.bottom: parent.bottom
												height: Math.min(Kirigami.Units.smallSpacing * 2, eventBlock.height / 4)
												cursorShape: Qt.SizeVerCursor
												preventStealing: true
												onPressed: function(mouse) {
													weekView.dragBegin(eventBlock.block, 'resize', mapToItem(flickable, mouse.x, mouse.y))
												}
												onPositionChanged: function(mouse) {
													weekView.dragMove(mapToItem(flickable, mouse.x, mouse.y))
												}
												onReleased: weekView.dragDrop(false)
												onCanceled: weekView.dragCancel()
											}
										}
									}

									// Current time
									Rectangle {
										readonly property real hours: weekView.currentTime.getHours() + weekView.currentTime.getMinutes() / 60
										visible: dayColumn.today && hours >= weekView.firstHour && hours <= weekView.lastHour
										y: (hours - weekView.firstHour) * weekView.hourHeight
										width: parent.width
										height: 2
										color: Kirigami.Theme.negativeTextColor
										Rectangle {
											x: -width / 2
											anchors.verticalCenter: parent.verticalCenter
											width: 8
											height: 8
											radius: 4
											color: parent.color
										}
									}
								}
							}
						}
					}
				}
			}
		}
	}
}
