import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "Shared.js" as Shared
import "Tasks.js" as Tasks

// A small month calendar (the Day view, beside the hours): the month's name with previous / next,
// the weekday initials, and the days of six weeks. The shown day (selectedDate) is filled in the
// accent color, today is in the accent color, days of the months around are dimmed, and a dot
// under a day says it has events (eventModel.eventsData, tasks left out). A click picks the day
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
	readonly property var eventDays: {
		var items = eventModel && eventModel.eventsData ? Tasks.withoutTasks(eventModel.eventsData.items) : []
		return Shared.eventDayKeys(items, gridStart, Shared.addDays(gridStart, 42))
	}

	readonly property real cellSize: Math.floor(width / 7)
	readonly property real rowHeight: Math.round(Kirigami.Units.gridUnit * 1.75)
	spacing: 2

	// "October 2026", previous, next.
	RowLayout {
		Layout.fillWidth: true
		spacing: 0
		PlasmaComponents3.Label {
			Layout.fillWidth: true
			Layout.leftMargin: Kirigami.Units.smallSpacing
			// The standalone month name ("Październik", not the "Października" of a date).
			text: Qt.locale().standaloneMonthName(miniMonth.monthStart.getMonth(), Locale.LongFormat) + " " + miniMonth.monthStart.getFullYear()
			textFormat: Text.PlainText
			font.weight: Font.DemiBold
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
		Layout.alignment: Qt.AlignHCenter
		columns: 7
		spacing: 0

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
				readonly property bool hasEvents: !!miniMonth.eventDays[Shared.dayKey(day)]
				width: miniMonth.cellSize
				// Compact rows: the tasks below keep their room.
				height: miniMonth.rowHeight
				hoverEnabled: true
				text: Shared.formatDate(day, Locale.LongFormat)
				Accessible.name: hasEvents ? i18nc("%1 = date", "%1, has events", text) : text
				onClicked: miniMonth.dayClicked(day)

				background: Rectangle {
					anchors.centerIn: parent
					width: Math.min(parent.width, parent.height) - 2
					height: width
					radius: width / 2
					color: dayButton.selected ? Kirigami.Theme.highlightColor
						: dayButton.hovered ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1)
						: "transparent"
				}
				contentItem: Item {
					PlasmaComponents3.Label {
						anchors.centerIn: parent
						anchors.verticalCenterOffset: -1
						text: dayButton.day.getDate()
						textFormat: Text.PlainText
						font.pointSize: Kirigami.Theme.smallFont.pointSize
						font.weight: dayButton.isToday || dayButton.selected ? Font.Bold : Font.Normal
						color: dayButton.selected ? Kirigami.Theme.highlightedTextColor
							: dayButton.isToday ? Kirigami.Theme.highlightColor
							: Kirigami.Theme.textColor
						opacity: dayButton.inMonth || dayButton.selected ? 1 : 0.45
					}
					// Has events: a small dot under the number.
					Rectangle {
						visible: dayButton.hasEvents
						anchors.horizontalCenter: parent.horizontalCenter
						anchors.bottom: parent.bottom
						anchors.bottomMargin: Math.round(parent.height * 0.12)
						width: 4
						height: 4
						radius: 2
						color: dayButton.selected ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.highlightColor
						opacity: dayButton.inMonth || dayButton.selected ? 1 : 0.45
					}
				}
			}
		}
	}
}
