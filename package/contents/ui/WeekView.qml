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
		weekStart = dayDate(-7)
	}
	function goNext() {
		weekStart = dayDate(7)
	}
	function goToday() {
		weekStart = startOfWeek(currentTime)
		scrollToWorkingHours()
	}
	readonly property date currentTime: timeModel.currentTime
	property date weekStart: startOfWeek(currentTime)
	readonly property int dayCount: 7

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
			x: weekView.gutterWidth + modelData.first * weekView.columnWidth
			y: dayNamesRow.y
			width: modelData.count * weekView.columnWidth
			height: weekView.height - y
			radius: 6
			color: Kirigami.Theme.textColor
			opacity: 0.04
		}
	}

	ColumnLayout {
		anchors.fill: parent
		spacing: Kirigami.Units.smallSpacing

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
					width: weekView.columnWidth
					PlasmaComponents3.Label {
						width: parent.width
						horizontalAlignment: Text.AlignHCenter
						text: Qt.locale().dayName(parent.date.getDay(), Locale.ShortFormat)
						font: Kirigami.Theme.smallFont
						color: parent.today ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
						opacity: parent.today ? 1 : 0.6
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
					width: (bar.last - bar.first + 1) * weekView.columnWidth - 2
					height: weekView.allDayRowHeight
					radius: Math.min(8, height / 2)
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

			// Top line of the hour grid: only across the day columns (not the hour labels or past Sunday).
			Rectangle {
				z: 1
				x: weekView.gutterWidth
				width: weekView.columnWidth * weekView.dayCount
				height: 1
				color: weekView.gridLineColor
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
								x: weekView.gutterWidth
								width: parent.width - weekView.gutterWidth
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
								opacity: dayColumn.today ? 0.08 : 0
							}
							// Today: highlight-colored frame around the column.
							Rectangle {
								visible: dayColumn.today
								anchors.fill: parent
								anchors.margins: 1
								color: "transparent"
								radius: 6
								border.width: 2
								border.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.5)
							}
							Rectangle {
								width: 1
								height: parent.height
								color: weekView.gridLineColor
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
									visible: visibleEnd > visibleStart
									x: 2 + block.column * slotWidth
									y: weekView.hourY(visibleStart, block.dayStart) + 1
									width: slotWidth - 1
									height: Math.max(weekView.lineHeight + 2, (visibleEnd - visibleStart) / 3600000 * weekView.hourHeight - 2)
									radius: Math.min(10, height / 2)
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
											text: eventBlock.eventItem.summary
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
											text: Qt.formatTime(eventBlock.eventItem.startDateTime, appletConfig.clock24h ? 'HH:mm' : 'h:mm AP')
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
