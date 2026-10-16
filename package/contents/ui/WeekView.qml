import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3

import "Shared.js" as Shared

// Week view like Google Calendar: hour grid with event blocks, all-day row on top.
Item {
	id: weekView

	property var eventModel
	// false: the popup shows title and navigation in its own header.
	property bool showHeader: true
	function goPrevious() {
		weekStart = dayDate(-dayCount)
	}
	function goNext() {
		weekStart = dayDate(dayCount)
	}
	function goToday() {
		weekStart = startOfWeek(currentTime)
		scrollToWorkingHours()
	}
	readonly property date currentTime: timeModel.currentTime
	property date weekStart: startOfWeek(currentTime)
	// 7: week view. 1: today / day view (the same hour grid with one wide column).
	property int dayCount: 7
	readonly property bool singleDay: dayCount === 1
	// One day stretched over a wide popup looks wrong: cap its width and center it.
	// Weather from the popup (Logic). weatherByDay: Shared.dayKey -> daily item.
	property var weatherByDay: ({})
	property var weatherHourly: []
	property var weatherCurrent: null
	property bool weatherIsSetup: false
	readonly property bool showWeather: Object.keys(weatherByDay).length > 0 || weatherIsSetup

	// Day view: the day grid (capped width) with the weather panel beside it, both centered.
	// Too narrow for both: the panel becomes a compact row above the grid.
	readonly property real weatherPanelWidth: Kirigami.Units.gridUnit * 13
	readonly property bool weatherBeside: singleDay && showWeather && width >= Kirigami.Units.gridUnit * 36
	readonly property real contentWidth: {
		if (!singleDay) {
			return width
		}
		var room = weatherBeside ? width - weatherPanelWidth - Kirigami.Units.largeSpacing * 2 : width
		return Math.min(room, Kirigami.Units.gridUnit * 32)
	}
	readonly property real contentX: {
		var total = contentWidth + (weatherBeside ? weatherPanelWidth + Kirigami.Units.largeSpacing * 2 : 0)
		return Math.round((width - total) / 2)
	}
	readonly property date todayStart: new Date(currentTime.getFullYear(), currentTime.getMonth(), currentTime.getDate())
	function dayWeather(d) {
		return weatherByDay ? weatherByDay[Shared.dayKey(d)] : null
	}
	onDayCountChanged: {
		weekStart = startOfWeek(currentTime)
		rebuild()
		scrollToWorkingHours()
	}

	// [{ date, allDay: [eventItem], timed: [{ eventItem, start, end, column, columns }] }]
	property var days: []
	// All-day events laid out for the whole week: one bar per event across its days,
	// in the same lane on every day. [{ eventItem, first, last, lane }]
	property var allDayBars: []
	property int allDayLaneCount: 0
	property var allDayHiddenPerDay: [] // Events per day in lanes that aren't shown.

	FontMetrics {
		id: fontMetrics
		font: Kirigami.Theme.defaultFont
	}
	FontMetrics {
		id: smallFontMetrics
		font: Kirigami.Theme.smallFont
	}
	readonly property int lineHeight: Math.ceil(fontMetrics.height)
	// Visible hours: the configured range, stretched to fit this week's timed events.
	property int firstHour: plasmoid.configuration.weekViewStartHour
	property int lastHour: plasmoid.configuration.weekViewEndHour // Exclusive
	readonly property int hourCount: Math.max(1, lastHour - firstHour)
	readonly property int minHourHeight: lineHeight + 6
	// Fill the view when the range fits, scroll otherwise.
	readonly property real hourHeight: Math.max(minHourHeight, flickable.height / hourCount)
	readonly property int gutterWidth: Math.ceil(Math.max(smallFontMetrics.advanceWidth(formatHour(23)), smallFontMetrics.advanceWidth(formatHour(12)))) + Kirigami.Units.smallSpacing * 2
	readonly property real columnWidth: Math.max(1, (timeGrid.width - gutterWidth) / dayCount)
	readonly property int allDayRowHeight: lineHeight + 4
	readonly property int maxVisibleAllDayRows: 3
	// Same lines as the month grid. Hour lines stay (fainter) when grid lines are off.
	readonly property color gridLineColor: appletConfig.showGridLines
		? appletConfig.gridLineColor
		: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, appletConfig.faintGridLineOpacity)

	function startOfWeek(d) {
		var day = new Date(d.getFullYear(), d.getMonth(), d.getDate())
		if (dayCount < 7) {
			return day // Day view starts on the day itself.
		}
		var diff = (day.getDay() - Qt.locale().firstDayOfWeek + 7) % 7
		day.setDate(day.getDate() - diff)
		return day
	}
	function dayDate(i) {
		return new Date(weekStart.getFullYear(), weekStart.getMonth(), weekStart.getDate() + i)
	}
	function formatHour(hour) {
		var d = new Date(2000, 0, 1, hour)
		return Qt.formatTime(d, appletConfig.clock24h ? 'HH:mm' : 'h AP')
	}
	function isToday(d) {
		return Shared.isSameDate(d, currentTime)
	}

	readonly property string title: {
		if (singleDay) {
			return Qt.formatDate(weekStart, Qt.locale().dateFormat(Locale.LongFormat))
		}
		var first = weekStart
		var last = dayDate(dayCount - 1)
		if (first.getFullYear() !== last.getFullYear()) {
			return Qt.formatDate(first, 'd MMM yyyy') + ' – ' + Qt.formatDate(last, 'd MMM yyyy')
		} else if (first.getMonth() !== last.getMonth()) {
			return Qt.formatDate(first, 'd MMM') + ' – ' + Qt.formatDate(last, 'd MMM yyyy')
		}
		return Qt.formatDate(first, 'd') + ' – ' + Qt.formatDate(last, 'd MMMM yyyy')
	}

	//--- Data
	function rebuild() {
		var items = eventModel && eventModel.eventsData ? eventModel.eventsData.items : []
		var result = []
		for (var i = 0; i < dayCount; i++) {
			var dayStart = dayDate(i).getTime()
			var dayEnd = dayDate(i + 1).getTime()
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

		var first = plasmoid.configuration.weekViewStartHour
		var last = plasmoid.configuration.weekViewEndHour
		for (var d = 0; d < result.length; d++) {
			var timedList = result[d].timed
			for (var t = 0; t < timedList.length; t++) {
				var block = timedList[t]
				// A piece continued from the previous day starts at midnight; don't stretch the range for it,
				// it's cut off at the top instead. Same for pieces continuing into the next day.
				if (!block.continued) {
					first = Math.min(first, Math.floor((block.start - block.dayStart) / 3600000))
				}
				if (!block.continues) {
					last = Math.max(last, Math.ceil((Math.max(block.end, block.start + 30 * 60000) - block.dayStart) / 3600000))
				}
			}
		}
		firstHour = Math.max(0, first)
		lastHour = Math.min(24, Math.max(last, firstHour + 1))
	}

	function layoutAllDay(dayList) {
		// Collect each event once with its first and last day index in this week.
		var byEvent = []
		for (var i = 0; i < dayList.length; i++) {
			var list = dayList[i].allDay
			for (var j = 0; j < list.length; j++) {
				var found = null
				for (var k = 0; k < byEvent.length; k++) {
					if (byEvent[k].eventItem === list[j]) {
						found = byEvent[k]
						break
					}
				}
				if (found) {
					found.last = i
				} else {
					byEvent.push({ eventItem: list[j], first: i, last: i, lane: 0 })
				}
			}
		}
		// Earlier first, then longer first, like Google Calendar.
		byEvent.sort(function(a, b) {
			return (a.first - b.first) || ((b.last - b.first) - (a.last - a.first))
		})
		var laneEnds = [] // Last day index used per lane
		for (var e = 0; e < byEvent.length; e++) {
			var bar = byEvent[e]
			var lane = 0
			while (lane < laneEnds.length && laneEnds[lane] >= bar.first) {
				lane++
			}
			laneEnds[lane] = bar.last
			bar.lane = lane
		}
		var laneCount = laneEnds.length
		// Too many lanes: show maxVisibleAllDayRows - 1 lanes and a "+N" row.
		var shownLanes = laneCount > maxVisibleAllDayRows ? maxVisibleAllDayRows - 1 : laneCount
		var hidden = []
		for (var d = 0; d < dayCount; d++) {
			hidden.push(0)
		}
		for (var h = 0; h < byEvent.length; h++) {
			if (byEvent[h].lane >= shownLanes) {
				for (var day = byEvent[h].first; day <= byEvent[h].last; day++) {
					hidden[day]++
				}
			}
		}
		allDayBars = byEvent.filter(function(bar) { return bar.lane < shownLanes })
		allDayHiddenPerDay = hidden
		allDayLaneCount = laneCount
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

	onWeekStartChanged: rebuild()
	Component.onCompleted: {
		rebuild()
		scrollToWorkingHours()
	}

	function scrollToWorkingHours() {
		var showsNow = currentTime >= weekStart && currentTime < dayDate(dayCount)
		var hour = showsNow ? Math.max(firstHour, currentTime.getHours() - 1) : firstHour
		flickable.contentY = Math.min((hour - firstHour) * hourHeight, Math.max(0, flickable.contentHeight - flickable.height))
	}
	function hourY(ms, dayStart) {
		return ((ms - dayStart) / 3600000 - firstHour) * hourHeight
	}

	function openEvent(eventItem) {
		popup.activateEvent(eventItem)
	}

	//--- UI
	// Weekend days: tint the whole column, from the day name down through the hours.
	// Adjacent weekend days share one strip.
	Repeater {
		model: {
			var flags = []
			for (var i = 0; i < weekView.dayCount; i++) {
				flags.push(Shared.isWeekend(weekView.dayDate(i)))
			}
			return Shared.runsOf(flags)
		}
		Rectangle {
			x: weekView.contentX + weekView.gutterWidth + modelData.first * weekView.columnWidth
			y: dayNamesRow.y
			width: modelData.count * weekView.columnWidth
			height: weekView.height - y
			radius: 6
			color: Kirigami.Theme.textColor
			opacity: 0.04
		}
	}

	WeatherPanel {
		visible: weekView.weatherBeside
		x: weekView.contentX + weekView.contentWidth + Kirigami.Units.largeSpacing * 2
		width: weekView.weatherPanelWidth
		height: parent.height
		isSetup: weekView.weatherIsSetup
		locationName: plasmoid.configuration.weatherService === 'OpenMeteo' ? plasmoid.configuration.openMeteoLocationName : ""
		current: weekView.weatherCurrent
		today: weekView.dayWeather(weekView.weekStart)
		hourly: weekView.weatherHourly
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

	ColumnLayout {
		x: weekView.contentX
		width: weekView.contentWidth
		height: parent.height
		spacing: Kirigami.Units.smallSpacing

		WeatherPanel {
			visible: weekView.singleDay && weekView.showWeather && !weekView.weatherBeside && weekView.weatherIsSetup
			Layout.fillWidth: true
			compact: true
			isSetup: weekView.weatherIsSetup
			current: weekView.weatherCurrent
			today: weekView.dayWeather(weekView.weekStart)
		}

		RowLayout {
			Layout.fillWidth: true
			visible: weekView.showHeader
			PlasmaComponents3.ToolButton {
				icon.name: "go-previous"
				onClicked: weekView.weekStart = weekView.dayDate(-7)
				PlasmaComponents3.ToolTip.text: i18n("Previous Week")
				PlasmaComponents3.ToolTip.visible: hovered
			}
			PlasmaComponents3.ToolButton {
				text: i18n("Today")
				onClicked: {
					weekView.weekStart = weekView.startOfWeek(weekView.currentTime)
					weekView.scrollToWorkingHours()
				}
			}
			PlasmaComponents3.ToolButton {
				icon.name: "go-next"
				onClicked: weekView.weekStart = weekView.dayDate(7)
				PlasmaComponents3.ToolTip.text: i18n("Next Week")
				PlasmaComponents3.ToolTip.visible: hovered
			}
			Kirigami.Heading {
				Layout.fillWidth: true
				level: 3
				text: weekView.title
				elide: Text.ElideRight
			}
		}

		// Day names
		Row {
			id: dayNamesRow
			Layout.fillWidth: true
			Item {
				width: weekView.gutterWidth
				height: 1
			}
			Repeater {
				model: weekView.dayCount
				Column {
					readonly property date date: weekView.dayDate(index)
					readonly property bool today: weekView.isToday(date)
					readonly property var weather: weekView.dayWeather(date)
					width: weekView.columnWidth
					opacity: date < weekView.todayStart ? appletConfig.pastOpacity : 1
					// Day name, with the weather on the same line (week view): "pt. ☁ 13°".
					Row {
						anchors.horizontalCenter: parent.horizontalCenter
						spacing: 3
						PlasmaComponents3.Label {
							anchors.verticalCenter: parent.verticalCenter
							text: Qt.locale().dayName(parent.parent.date.getDay(), Locale.ShortFormat)
							font: Kirigami.Theme.smallFont
							color: parent.parent.today ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
							opacity: parent.parent.today ? 1 : 0.6
						}
						Kirigami.Icon {
							visible: !weekView.singleDay && !!parent.parent.weather
							anchors.verticalCenter: parent.verticalCenter
							width: Kirigami.Units.iconSizes.small
							height: width
							source: parent.parent.weather ? parent.parent.weather.iconName + "-symbolic" : "" // Monochrome: readable on any background
							fallback: parent.parent.weather ? parent.parent.weather.iconName : ""
						}
						PlasmaComponents3.Label {
							visible: !weekView.singleDay && !!parent.parent.weather
							anchors.verticalCenter: parent.verticalCenter
							text: parent.parent.weather ? Shared.formatTemp(parent.parent.weather.temp.max) : ""
							font: Kirigami.Theme.smallFont
							opacity: 0.8
						}
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
							visible: parent.parent.today
						}
						PlasmaComponents3.Label {
							id: dayNumberLabel
							anchors.centerIn: parent
							text: parent.parent.date.getDate()
							font.weight: Font.Bold
							color: parent.parent.today ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
						}
					}
				}
			}
		}

		// All-day events
		Item {
			id: allDayArea
			Layout.fillWidth: true
			readonly property int rows: Math.min(weekView.allDayLaneCount, weekView.maxVisibleAllDayRows)
			readonly property bool hasHiddenRow: weekView.allDayLaneCount > weekView.maxVisibleAllDayRows
			Layout.preferredHeight: rows * (weekView.allDayRowHeight + 1)
			visible: rows > 0

			Repeater {
				model: weekView.allDayBars
				Rectangle {
					readonly property var bar: modelData
					readonly property var eventItem: bar.eventItem
					readonly property color barColor: eventItem.backgroundColor || Kirigami.Theme.highlightColor
					x: weekView.gutterWidth + bar.first * weekView.columnWidth + 1
					y: bar.lane * (weekView.allDayRowHeight + 1)
					opacity: bar.eventItem.endDateTime <= weekView.todayStart ? appletConfig.pastOpacity : 1
					width: (bar.last - bar.first + 1) * weekView.columnWidth - 2
					height: weekView.allDayRowHeight
					// Square ends where the event continues before or after this week.
					readonly property bool cutLeft: bar.eventItem.startDateTime < weekView.weekStart
					readonly property bool cutRight: bar.eventItem.endDateTime > weekView.dayDate(weekView.dayCount)
					readonly property real cornerRadius: Math.min(8, height / 2)
					radius: cornerRadius
					topLeftRadius: cutLeft ? 0 : cornerRadius
					bottomLeftRadius: cutLeft ? 0 : cornerRadius
					topRightRadius: cutRight ? 0 : cornerRadius
					bottomRightRadius: cutRight ? 0 : cornerRadius
					color: barColor
					border.width: 1
					border.color: appletConfig.eventBorderColor
					PlasmaComponents3.Label {
						anchors.fill: parent
						anchors.leftMargin: 7
						anchors.rightMargin: 2
						verticalAlignment: Text.AlignVCenter
						text: parent.eventItem.summary
						color: Shared.contrastTextColor(parent.barColor)
						elide: Text.ElideRight
					}
					MouseArea {
						anchors.fill: parent
						cursorShape: Qt.PointingHandCursor
						onClicked: weekView.openEvent(parent.eventItem)
					}
					PlasmaCore.ToolTipArea {
						anchors.fill: parent
						mainText: parent.eventItem.summary
						subText: containsMouse ? weekView.eventModel.eventDetailsText(parent.eventItem) : ""
						textFormat: Text.PlainText
					}
				}
			}

			// "+N" per day for events in lanes that don't fit.
			Repeater {
				model: allDayArea.hasHiddenRow ? weekView.dayCount : 0
				PlasmaComponents3.Label {
					readonly property int hiddenCount: weekView.allDayHiddenPerDay[index] || 0
					visible: hiddenCount > 0
					x: weekView.gutterWidth + index * weekView.columnWidth
					y: (allDayArea.rows - 1) * (weekView.allDayRowHeight + 1)
					width: weekView.columnWidth
					height: weekView.allDayRowHeight
					horizontalAlignment: Text.AlignHCenter
					verticalAlignment: Text.AlignVCenter
					text: i18nc("more events not shown", "+%1", hiddenCount)
					opacity: 0.7
				}
			}
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
				width: weekView.columnWidth * weekView.dayCount
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
				PlasmaComponents3.ScrollBar.vertical: PlasmaComponents3.ScrollBar {}

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
							PlasmaComponents3.Label {
								visible: index > 0
								width: weekView.gutterWidth - Kirigami.Units.smallSpacing
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
								width: weekView.columnWidth * weekView.dayCount - 2
								height: 1
								color: weekView.gridLineColor
							}
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
								border.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.5)
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
								color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.15)
								border.width: 1
								border.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.6)
								PlasmaComponents3.Label {
									anchors.fill: parent
									anchors.margins: 2
									anchors.leftMargin: 6
									text: {
										var format = appletConfig.clock24h ? 'HH:mm' : 'h:mm AP'
										var start = slotArea.slotStart()
										var end = new Date(start.getTime() + 60 * 60 * 1000)
										return Qt.formatTime(start, format) + ' – ' + Qt.formatTime(end, format)
									}
									font: Kirigami.Theme.smallFont
									color: Kirigami.Theme.highlightColor
									elide: Text.ElideRight
								}
							}

							Repeater {
								model: dayColumn.day.timed
								Rectangle {
									id: eventBlock
									readonly property var block: modelData
									readonly property var eventItem: block.eventItem
									readonly property color barColor: eventItem.backgroundColor || Kirigami.Theme.highlightColor
									readonly property real slotWidth: (dayColumn.width - 3) / block.columns
									// Clip to the visible hour range.
									readonly property real rangeStart: block.dayStart + weekView.firstHour * 3600000
									readonly property real rangeEnd: block.dayStart + weekView.lastHour * 3600000
									readonly property real visibleStart: Math.max(block.start, rangeStart)
									readonly property real visibleEnd: Math.min(Math.max(block.end, block.start + 15 * 60000), rangeEnd)
									opacity: eventItem.endDateTime <= weekView.currentTime ? appletConfig.pastOpacity : 1
									visible: visibleEnd > visibleStart
									x: 2 + block.column * slotWidth
									y: weekView.hourY(visibleStart, block.dayStart) + 1
									width: slotWidth - 1
									height: Math.max(weekView.lineHeight + 2, (visibleEnd - visibleStart) / 3600000 * weekView.hourHeight - 2)
									// Square edges where the event continues beyond what's shown
									// (from the previous day / before the first hour, or past the last one).
									readonly property bool cutTop: block.continued || block.start < rangeStart
									readonly property bool cutBottom: block.continues || block.end > rangeEnd
									readonly property real cornerRadius: Math.min(10, height / 2)
									radius: cornerRadius
									topLeftRadius: cutTop ? 0 : cornerRadius
									topRightRadius: cutTop ? 0 : cornerRadius
									bottomLeftRadius: cutBottom ? 0 : cornerRadius
									bottomRightRadius: cutBottom ? 0 : cornerRadius
									color: barColor
									border.width: 1
									border.color: appletConfig.eventBorderColor

									Column {
										anchors.fill: parent
										anchors.margins: 2
										anchors.leftMargin: 6
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
												var format = appletConfig.clock24h ? 'HH:mm' : 'h:mm AP'
												var parts = [item.summary, Qt.formatTime(item.startDateTime, format) + ' – ' + Qt.formatTime(item.endDateTime, format)]
												if (item.location) {
													parts.push(item.location)
												}
												return parts.join(' · ')
											}
											color: Shared.contrastTextColor(eventBlock.barColor)
											// Event in progress
											font.bold: eventBlock.eventItem.startDateTime <= weekView.currentTime && weekView.currentTime < eventBlock.eventItem.endDateTime
											elide: Text.ElideRight
											wrapMode: Text.WordWrap
											maximumLineCount: Math.max(1, Math.floor((eventBlock.height - 4) / weekView.lineHeight) - 1)
										}
										PlasmaComponents3.Label {
											width: parent.width
											visible: eventBlock.height >= weekView.lineHeight * 2 + 4
											text: {
												var format = appletConfig.clock24h ? 'HH:mm' : 'h:mm AP'
												var item = eventBlock.eventItem
												// Day view has room for the end time and location.
												if (weekView.singleDay) {
													var text = Qt.formatTime(item.startDateTime, format) + ' – ' + Qt.formatTime(item.endDateTime, format)
													return item.location ? text + ' · ' + item.location : text
												}
												return Qt.formatTime(item.startDateTime, format)
											}
											color: Shared.contrastTextColor(eventBlock.barColor)
											font: Kirigami.Theme.smallFont
											elide: Text.ElideRight
										}
									}
									MouseArea {
										anchors.fill: parent
										cursorShape: Qt.PointingHandCursor
										onClicked: weekView.openEvent(eventBlock.eventItem)
									}
									PlasmaCore.ToolTipArea {
										anchors.fill: parent
										mainText: eventBlock.eventItem.summary
										subText: containsMouse ? weekView.eventModel.eventDetailsText(eventBlock.eventItem) : ""
										textFormat: Text.PlainText
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
