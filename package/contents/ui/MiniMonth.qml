import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "Shared.js" as Shared
import "Tasks.js" as Tasks

// A small month calendar (the Day view, beside the hours): the month's name with previous / next,
// the weekday initials, and the days of six weeks. Today is a solid accent tile (as in the views'
// headers), the shown day (selectedDate) a pale one with its number in the accent color, or with
// rangeStart / rangeEnd (the Agenda) the days in sight a band. Days of the months around are
// dimmed, and dots under a day say how busy it is: 1 for 1-2 events, 2 for 3-4, 3 for 5 or more
// (eventModel.eventsData, tasks left out), in the colors of its events. A click picks the day
// (dayClicked); the month shown follows selectedDate and can be paged through on its own.
ColumnLayout {
	id: miniMonth

	property var eventModel: null
	property date selectedDate: new Date()
	property date today: new Date()
	// 0 = Sunday … 6 (as Date.getDay()).
	property int firstDayOfWeek: 1

	signal dayClicked(date day)

	// The first day of the month shown.
	property date monthStart: new Date(selectedDate.getFullYear(), selectedDate.getMonth(), 1)
	onSelectedDateChanged: {
		if (selectedDate.getFullYear() !== monthStart.getFullYear() || selectedDate.getMonth() !== monthStart.getMonth()) {
			monthStart = new Date(selectedDate.getFullYear(), selectedDate.getMonth(), 1)
		}
	}
	function pageMonth(delta) {
		monthStart = new Date(monthStart.getFullYear(), monthStart.getMonth() + delta, 1)
		daysSlide.run(delta, 0)
	}
	// The first day in the grid: the week's start on or before the 1st.
	readonly property date gridStart: Shared.addDays(monthStart, -((monthStart.getDay() - firstDayOfWeek + 7) % 7))
	readonly property var days: {
		var list = []
		for (var i = 0; i < 42; i++) {
			list.push(Shared.addDays(gridStart, i))
		}
		return list
	}
	readonly property var dayEvents: eventModel && eventModel.eventsData ? Tasks.withoutTasks(eventModel.eventsData.items) : []
	readonly property var eventColors: Shared.eventDayColors(dayEvents, gridStart, Shared.addDays(gridStart, 42))
	// The events per day: the colors' counts summed up (one walk over the events, not two).
	readonly property var eventCounts: {
		var counts = {}
		for (var key in eventColors) {
			var total = 0
			for (var color in eventColors[key]) {
				total += eventColors[key][color]
			}
			counts[key] = total
		}
		return counts
	}
	function dotCount(count) {
		return count >= 5 ? 3 : count >= 3 ? 2 : count > 0 ? 1 : 0
	}

	// The days in sight elsewhere (the Agenda): a band across them, no shown-day tile.
	property date rangeStart: new Date(NaN)
	property date rangeEnd: new Date(NaN)
	readonly property bool hasRange: !isNaN(rangeStart.getTime()) && !isNaN(rangeEnd.getTime())
	readonly property bool showSelection: !hasRange
	readonly property real rangeStartTime: hasRange ? Shared.startOfDay(rangeStart).getTime() : NaN
	readonly property real rangeEndTime: hasRange ? Shared.startOfDay(rangeEnd).getTime() : NaN
	readonly property real cellSize: Math.floor(width / 7)
	readonly property real rowHeight: Math.round(Kirigami.Units.gridUnit * 1.75)
	// A day's tile (today, the shown day) and the band's ends: about square, over the number and its
	// dots, inset from the cell's sides by tileInset.
	readonly property real tileHeight: rowHeight - 2
	readonly property real tileWidth: Math.max(Math.min(cellSize - 4, tileHeight), Math.min(cellSize - 2, tileHeight * 0.8))
	readonly property real tileInset: Math.max(0, (cellSize - tileWidth) / 2)
	readonly property real tileRadius: Math.round(Kirigami.Units.cornerRadius * 1.5)
	spacing: 2

	// "October 2026", previous, next.
	RowLayout {
		Layout.fillWidth: true
		spacing: 0
		// Like the other side cards' titles ("Weather", "Tasks").
		PlasmaComponents3.Label {
			Layout.fillWidth: true
			// The standalone month name ("Październik", not the "Października" of a date).
			text: Qt.locale().standaloneMonthName(miniMonth.monthStart.getMonth(), Locale.LongFormat) + " " + miniMonth.monthStart.getFullYear()
			textFormat: Text.PlainText
			font.weight: Font.Bold
			font.pointSize: appletConfig.fontPoints(Kirigami.Theme.defaultFont) * 1.25
			font.capitalization: Font.Capitalize
			elide: Text.ElideRight
		}
		PlasmaComponents3.ToolButton {
			icon.name: Qt.application.layoutDirection === Qt.RightToLeft ? "go-next" : "go-previous"
			display: QQC2.AbstractButton.IconOnly
			text: i18n("Previous Month")
			onClicked: miniMonth.pageMonth(-1)
			PlasmaComponents3.ToolTip.text: text
			PlasmaComponents3.ToolTip.visible: hovered
		}
		PlasmaComponents3.ToolButton {
			icon.name: Qt.application.layoutDirection === Qt.RightToLeft ? "go-previous" : "go-next"
			display: QQC2.AbstractButton.IconOnly
			text: i18n("Next Month")
			onClicked: miniMonth.pageMonth(1)
			PlasmaComponents3.ToolTip.text: text
			PlasmaComponents3.ToolTip.visible: hovered
		}
	}

	Grid {
		id: daysGrid
		Layout.alignment: Qt.AlignHCenter
		columns: 7
		spacing: 0
		// Paging: the new month slides in from the side it comes from.
		transform: Translate { id: daysShift }
		SlideIn {
			id: daysSlide
			target: daysGrid
			shift: daysShift
		}

		// Weekday initials.
		Repeater {
			model: 7
			PlasmaComponents3.Label {
				width: miniMonth.cellSize
				horizontalAlignment: Text.AlignHCenter
				text: Qt.locale().standaloneDayName((miniMonth.firstDayOfWeek + index) % 7, Locale.NarrowFormat)
				textFormat: Text.PlainText
				font: Kirigami.Theme.smallFont
				opacity: 0.7
			}
		}

		Repeater {
			model: miniMonth.days
			QQC2.AbstractButton {
				id: dayButton
				readonly property date day: modelData
				readonly property bool inMonth: day.getMonth() === miniMonth.monthStart.getMonth()
				readonly property bool selected: Shared.isSameDate(day, miniMonth.selectedDate)
				readonly property bool isToday: Shared.isSameDate(day, miniMonth.today)
				readonly property string dayKey: Shared.dayKey(day)
				readonly property int eventCount: miniMonth.eventCounts[dayKey] || 0
				readonly property var dotColors: Shared.dotColors(miniMonth.eventColors[dayKey], miniMonth.dotCount(eventCount))
				width: miniMonth.cellSize
				// Compact rows: the tasks below keep their room.
				height: miniMonth.rowHeight
				hoverEnabled: true
				text: Shared.formatDate(day, Locale.LongFormat)
				Accessible.name: eventCount > 0 ? i18ncp("%2 = date", "%2, %1 event", "%2, %1 events", eventCount, text) : text
				onClicked: miniMonth.dayClicked(day)

				// Today: a solid accent tile, the only solid one. The shown day: a pale accent tile, its
				// number in the accent color (as Google Calendar). The days in sight (rangeStart ..
				// rangeEnd, the Agenda): a soft band across the row instead, its ends as the tiles.
				readonly property color accent: Kirigami.Theme.highlightColor
				readonly property bool marked: selected && miniMonth.showSelection
				readonly property bool inRange: miniMonth.hasRange && day.getTime() >= miniMonth.rangeStartTime && day.getTime() <= miniMonth.rangeEndTime
				readonly property bool rangeLeftEnd: inRange && (index % 7 === 0 || day.getTime() === miniMonth.rangeStartTime)
				readonly property bool rangeRightEnd: inRange && (index % 7 === 6 || day.getTime() === miniMonth.rangeEndTime)
				readonly property color numberColor: isToday ? Kirigami.Theme.highlightedTextColor
					: marked ? (appletConfig.darkTheme ? Qt.lighter(accent, 1.3) : Qt.darker(accent, 1.3))
					: Kirigami.Theme.textColor
				background: Item {
					// The band: its ends where a tile's sides would be, rounded as the tiles (a rounded
					// piece shown over its outer half, a square one over the rest: an even tint).
					Item {
						id: band
						// Fades as the days in sight change (the Agenda scrolling).
						opacity: dayButton.inRange ? 1 : 0
						visible: opacity > 0
						Behavior on opacity { NumberAnimation { duration: appletConfig.shortDuration } }
						readonly property color bandColor: Qt.rgba(dayButton.accent.r, dayButton.accent.g, dayButton.accent.b, 0.14)
						readonly property bool bothEnds: dayButton.rangeLeftEnd && dayButton.rangeRightEnd
						readonly property bool oneEnd: dayButton.rangeLeftEnd || dayButton.rangeRightEnd
						x: dayButton.rangeLeftEnd ? miniMonth.tileInset : 0
						y: (parent.height - miniMonth.tileHeight) / 2
						width: parent.width - (dayButton.rangeLeftEnd ? miniMonth.tileInset : 0) - (dayButton.rangeRightEnd ? miniMonth.tileInset : 0)
						height: miniMonth.tileHeight
						Item {
							visible: band.oneEnd
							clip: !band.bothEnds
							x: dayButton.rangeLeftEnd ? 0 : band.width / 2
							width: band.bothEnds ? band.width : band.width / 2
							height: band.height
							Rectangle {
								x: -parent.x
								width: band.width
								height: band.height
								radius: miniMonth.tileRadius
								color: band.bandColor
							}
						}
						Rectangle {
							visible: !band.bothEnds
							x: dayButton.rangeLeftEnd ? band.width / 2 : 0
							width: band.oneEnd ? band.width / 2 : band.width
							height: band.height
							color: band.bandColor
						}
					}
					// A rounded square over the number and its dots.
					Rectangle {
						anchors.centerIn: parent
						width: miniMonth.tileWidth
						height: miniMonth.tileHeight
						radius: miniMonth.tileRadius
						// The shown day moves (the Agenda scrolling, a click): eased, not jumping.
						Behavior on color { ColorAnimation { duration: appletConfig.shortDuration } }
						color: dayButton.isToday ? dayButton.accent
							: dayButton.marked ? Qt.rgba(dayButton.accent.r, dayButton.accent.g, dayButton.accent.b, dayButton.hovered ? 0.3 : 0.2)
							: dayButton.hovered ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1)
							: "transparent"
					}
				}
				contentItem: Item {
					PlasmaComponents3.Label {
						anchors.centerIn: parent
						anchors.verticalCenterOffset: -1
						text: dayButton.day.getDate()
						textFormat: Text.PlainText
						font.pointSize: appletConfig.fontPoints(Kirigami.Theme.smallFont)
						font.weight: dayButton.isToday || dayButton.marked ? Font.Bold : Font.DemiBold
						color: dayButton.numberColor
						opacity: dayButton.inMonth || dayButton.marked || dayButton.isToday ? 1 : 0.45
					}
					// How busy: 1-3 small dots under the number, in the colors of the day's events.
					Row {
						anchors.horizontalCenter: parent.horizontalCenter
						anchors.bottom: parent.bottom
						anchors.bottomMargin: Math.round(parent.height * 0.12)
						spacing: 2
						Repeater {
							model: dayButton.dotColors
							Rectangle {
								width: 4
								height: 4
								radius: 2
								// The events' colors as their bars elsewhere (the Google palette setting).
								color: dayButton.isToday ? Kirigami.Theme.highlightedTextColor
									: modelData ? appletConfig.eventBarColor(appletConfig.eventColor(modelData)) : Kirigami.Theme.highlightColor
								opacity: dayButton.inMonth || dayButton.marked || dayButton.isToday ? 1 : 0.45
							}
						}
					}
				}
			}
		}
	}
}
