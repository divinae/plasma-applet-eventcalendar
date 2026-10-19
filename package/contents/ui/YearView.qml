import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "lib"
import "YearCounts.js" as YearCounts

// Year view: twelve small month grids, days with events tinted by how many there are.
// Click a day: Day view. Click a month name: Month view. The popup header shows the title
// and the navigation (title, goPrevious, goNext, goToday).
Item {
	id: yearView

	property int year: new Date().getFullYear()
	property date today: new Date()
	property var eventModel
	property int firstDayOfWeek: Qt.locale().firstDayOfWeek % 7 // 0 = Sunday

	signal yearRequested(int year)
	signal dayClicked(date date)
	signal monthClicked(date date)

	readonly property string title: String(year)
	function goPrevious() { yearRequested(year - 1) }
	function goNext() { yearRequested(year + 1) }
	function goToday() { yearRequested(today.getFullYear()) }

	property var counts: ({})
	function rebuild() {
		var data = eventModel ? eventModel.eventsData : null
		counts = YearCounts.countsByDay(data && data.items ? data.items : [], year)
	}
	onYearChanged: rebuild()
	Component.onCompleted: rebuild()

	// Wide popups: 4 x 3 months, otherwise 3 x 4.
	readonly property int monthColumns: width >= height * 1.15 ? 4 : 3
	readonly property int monthRows: Math.ceil(12 / monthColumns)
	readonly property real gap: Kirigami.Units.largeSpacing

	FontMetrics {
		id: dayFontMetrics
		font: Kirigami.Theme.smallFont
	}

	GridLayout {
		id: monthGrid
		anchors.fill: parent
		anchors.margins: Kirigami.Units.smallSpacing
		columns: yearView.monthColumns
		columnSpacing: yearView.gap
		rowSpacing: yearView.gap

		Repeater {
			model: 12

			ColumnLayout {
				id: monthItem
				readonly property int month: index // 0-11
				readonly property var cells: YearCounts.monthCells(yearView.year, month, yearView.firstDayOfWeek)
				readonly property bool isCurrentMonth: yearView.today.getFullYear() === yearView.year && yearView.today.getMonth() === month
				Layout.fillWidth: true
				Layout.fillHeight: true
				Layout.preferredWidth: 1 // Equal columns
				Layout.preferredHeight: 1
				spacing: 2

				PlasmaComponents3.ToolButton {
					id: monthButton
					Layout.fillWidth: true
					Layout.preferredHeight: implicitHeight
					text: Qt.locale().standaloneMonthName(monthItem.month, Locale.LongFormat)
					font.bold: true
					font.capitalization: Font.Capitalize
					contentItem: PlasmaComponents3.Label {
						text: monthButton.text
						font: monthButton.font
						color: monthItem.isCurrentMonth ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
						horizontalAlignment: Text.AlignLeft
						verticalAlignment: Text.AlignVCenter
						elide: Text.ElideRight
					}
					onClicked: yearView.monthClicked(new Date(yearView.year, monthItem.month, 1))
					Accessible.name: text
				}

				// Weekday initials, then six weeks.
				Grid {
					id: dayGrid
					Layout.fillWidth: true
					Layout.fillHeight: true
					columns: 7
					readonly property real cellWidth: width / 7
					readonly property real cellHeight: height / 7

					Repeater {
						model: 7
						PlasmaComponents3.Label {
							width: dayGrid.cellWidth
							height: dayGrid.cellHeight
							text: Qt.locale().dayName((yearView.firstDayOfWeek + index) % 7, Locale.NarrowFormat)
							font: Kirigami.Theme.smallFont
							horizontalAlignment: Text.AlignHCenter
							verticalAlignment: Text.AlignVCenter
							opacity: 0.6
						}
					}

					Repeater {
						model: monthItem.cells

						Item {
							id: dayCell
							readonly property int day: modelData
							readonly property int count: day ? (yearView.counts[YearCounts.dayKey(yearView.year, monthItem.month + 1, day)] || 0) : 0
							readonly property int level: YearCounts.level(count)
							readonly property bool isToday: monthItem.isCurrentMonth && yearView.today.getDate() === day
							width: dayGrid.cellWidth
							height: dayGrid.cellHeight

							Rectangle {
								visible: dayCell.day > 0 && (dayCell.level > 0 || dayCell.isToday || dayMouse.containsMouse)
								anchors.centerIn: parent
								width: Math.min(parent.width, parent.height) - 1
								height: width
								radius: width / 2
								color: dayCell.level > 0
									? Qt.alpha(Kirigami.Theme.highlightColor, [0, 0.22, 0.42, 0.65][dayCell.level])
									: Qt.alpha(Kirigami.Theme.highlightColor, dayMouse.containsMouse ? 0.12 : 0)
								border.width: dayCell.isToday ? 2 : 0
								border.color: Kirigami.Theme.highlightColor
							}
							PlasmaComponents3.Label {
								visible: dayCell.day > 0
								anchors.fill: parent
								text: dayCell.day
								font.pointSize: -1
								font.pixelSize: Math.max(7, Math.round(Math.min(dayFontMetrics.height * 0.78, parent.height * 0.6)))
								font.bold: dayCell.isToday || dayCell.level >= 3
								color: dayCell.level >= 3 ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
								horizontalAlignment: Text.AlignHCenter
								verticalAlignment: Text.AlignVCenter
							}
							MouseArea {
								id: dayMouse
								anchors.fill: parent
								enabled: dayCell.day > 0
								hoverEnabled: true
								cursorShape: Qt.PointingHandCursor
								onClicked: yearView.dayClicked(new Date(yearView.year, monthItem.month, dayCell.day))
							}
							PlasmaComponents3.ToolTip.text: dayCell.count > 0 ? i18np("1 event", "%1 events", dayCell.count) : ""
							PlasmaComponents3.ToolTip.visible: dayMouse.containsMouse && dayCell.count > 0
							PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
							Accessible.role: Accessible.Button
							Accessible.name: dayCell.day > 0 ? Qt.formatDate(new Date(yearView.year, monthItem.month, dayCell.day), Locale.LongFormat) : ""
							Accessible.description: PlasmaComponents3.ToolTip.text
						}
					}
				}
			}
		}
	}
}
