/*
 * Copyright 2013  Heena Mahour <heena393@gmail.com>
 * Copyright 2013 Sebastian Kügler <sebas@kde.org>
 * Copyright 2015, 2016 Kai Uwe Broulik <kde@privat.broulik.de>
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
import QtQuick.Layouts
import QtQuick.Controls as QQC2

import org.kde.kirigami as Kirigami
import org.kde.ksvg as KSvg
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.core as PlasmaCore

import "./badges"
import "Shared.js" as Shared
import "WeekDrag.js" as WeekDrag

Item {
	id: daysCalendar

	signal headerClicked

	signal previous
	signal next

	signal activated(int index, var date, var item)
	signal doubleClicked(int index, var date, var item)
	// so it forwards it to the delegate which then emits activated with all the neccessary data
	signal activateHighlightedItem

	readonly property int gridColumns: showWeekNumbers ? calendarGrid.columns + 1 : calendarGrid.columns

	property alias previousLabel: previousButton.tooltip
	property alias nextLabel: nextButton.tooltip

	property int rows
	property int columns

	property bool showWeekNumbers
	property string eventBadgeType: "theme"

	onShowWeekNumbersChanged: canvas.requestPaint()
	onHeaderHeightChanged: canvas.requestPaint()
	property color themeTextColor: Kirigami.Theme.textColor
	onThemeTextColorChanged: canvas.requestPaint()

	// how precise date matching should be, 3 = day+month+year, 2 = month+year, 1 = just year
	property int dateMatchingPrecision

	property alias headerModel: days.model
	property alias gridModel: repeater.model

	property alias title: heading.text

	// Take the calendar width, subtract the inner and outer spacings and divide by number of columns (==days in week)
	readonly property int cellWidth: Math.floor((stack.width - (daysCalendar.columns + 1) * root.borderWidth) / (daysCalendar.columns + (showWeekNumbers ? 1 : 0)))
	// With event titles, the weekday names get a short row in the small font instead of a full cell row.
	readonly property bool compactHeader: eventBadgeType === 'eventTitles' && !!headerModel
	FontMetrics {
		id: headerFontMetrics
		font: Kirigami.Theme.smallFont
	}
	readonly property int compactHeaderHeight: Math.ceil(headerFontMetrics.height) + 4
	// Take the calendar height, subtract the inner spacings and divide by number of rows (root.weeks + one row for day names)
	readonly property int cellHeight: compactHeader
		? Math.floor((stack.height - headingRowHeight - compactHeaderHeight - calendarGrid.rows * root.borderWidth) / (calendarGrid.rows - 1))
		: Math.floor((stack.height - headingRowHeight - calendarGrid.rows * root.borderWidth) / calendarGrid.rows)
	// The popup can show the title and navigation in its own header instead.
	readonly property int headingRowHeight: root.showHeader ? heading.height : 0
	readonly property int headerHeight: !headerModel ? 0 : (compactHeader ? compactHeaderHeight : cellHeight)
	// Y of the line above grid row i (row 0 is the header row when there is one).
	function gridLineY(i) {
		if (!headerModel || i === 0) {
			return (cellHeight + root.borderWidth) * i
		}
		return headerHeight + root.borderWidth + (cellHeight + root.borderWidth) * (i - 1)
	}

	// Event title rows in a day cell, same sizes as DayDelegate / EventTitlesBadge.
	FontMetrics {
		id: dayNumberFontMetrics
		font: Kirigami.Theme.defaultFont
	}
	FontMetrics {
		id: eventTitleFontMetrics
		font: appletConfig.eventFont
	}
	readonly property int eventTitlesTopOffset: Math.ceil(dayNumberFontMetrics.height) + 2 // DayDelegate.eventTitlesHeaderHeight
	readonly property int eventTitleRowHeight: Math.ceil(eventTitleFontMetrics.height) + 4
	readonly property int eventTitleRowSpacing: 1
	// Event rows (titles, bars, "+N") that fit in a day cell.
	readonly property int eventTitleRowCapacity: Math.max(0, Math.floor((cellHeight - eventTitlesTopOffset) / (eventTitleRowHeight + eventTitleRowSpacing)))
	// Multi-day events as bars across the days (EventBuckets.layoutMonth bars), in eventTitles mode.
	property var spanBars: []

	//--- Dragging events to other days (MonthView keeps the state and saves the drop).
	// Points are in this item's coordinates.
	property bool eventDragEnabled: false
	// MonthView.eventDragState: { eventItem, dayIndex, targetFirst, targetCount, copy, pending }.
	property var eventDrag: null
	function canDragEvent(eventItem) {
		return eventDragEnabled && eventBadgeType === 'eventTitles' && WeekDrag.canMove(eventItem) && !(eventDrag && eventDrag.pending)
	}
	// The day cell (index in gridModel) at a point; outside the grid: the nearest one.
	function cellIndexAt(x, y) {
		var step = cellWidth + root.borderWidth
		var column = Math.max(0, Math.min(columns - 1, Math.floor((x - calendarGrid.x) / step)))
		var top = calendarGrid.y + (headerModel ? headerHeight + root.borderWidth : 0)
		var row = Math.max(0, Math.min(rows - 1, Math.floor((y - top) / (cellHeight + root.borderWidth))))
		return row * columns + column
	}
	function eventDragBegin(eventItem, point, copy) {
		root.eventDragBegin(eventItem, cellIndexAt(point.x, point.y), copy)
	}
	function eventDragMove(point, copy) {
		root.eventDragMove(cellIndexAt(point.x, point.y), copy)
	}
	function eventDragDrop(copy) {
		root.eventDragDrop(copy)
	}
	function eventDragCancel() {
		root.eventDragCancel()
	}
	// Where the occurrence menu opens after a drop.
	readonly property Item eventDragTarget: dragTargetGhost

	property real transformScale: 1
	property point transformOrigin: Qt.point(width / 2, height / 2)

	transform: Scale {
		xScale: daysCalendar.transformScale
		yScale: xScale
		origin.x: transformOrigin.x
		origin.y: transformOrigin.y
	}

	Behavior on scale {
		id: scaleBehavior
		ScaleAnimator {
			duration: Kirigami.Units.longDuration
		}
	}

	QQC2.StackView.onStatusChanged: {
		if (QQC2.StackView.status === QQC2.StackView.Inactive) {
			daysCalendar.transformScale = 1
			daysCalendar.opacity = 1
		}
	}

	RowLayout {
		visible: root.showHeader
		anchors {
			top: parent.top
			left: parent.left
			right: parent.right
		}
		spacing: Kirigami.Units.smallSpacing

		PlasmaComponents3.ToolButton {
			id: previousButton
			icon.name: "go-previous"
			onClicked: daysCalendar.previous()
			property string tooltip: ''
			QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
			QQC2.ToolTip.text: tooltip
			QQC2.ToolTip.visible: hovered
			Accessible.name: tooltip
			//SEE QTBUG-58307
			Layout.preferredHeight: implicitHeight + implicitHeight%2
		}

		PlasmaComponents3.ToolButton {
			icon.name: "go-jump-today"
			onClicked: root.resetToToday()
			property string tooltip: i18ndc("libplasma5", "Reset calendar to today", "Today")
			QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
			QQC2.ToolTip.text: tooltip
			QQC2.ToolTip.visible: hovered
			Accessible.name: tooltip
			Accessible.description: i18nd("libplasma5", "Reset calendar to today")
			//SEE QTBUG-58307
			Layout.preferredHeight: implicitHeight + implicitHeight%2
		}

		PlasmaComponents3.ToolButton {
			id: nextButton
			icon.name: "go-next"
			onClicked: daysCalendar.next()
			property string tooltip: ''
			QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
			QQC2.ToolTip.text: tooltip
			QQC2.ToolTip.visible: hovered
			Accessible.name: tooltip
			//SEE QTBUG-58307
			Layout.preferredHeight: implicitHeight + implicitHeight%2
		}

		Kirigami.Heading {
			id: heading

			Layout.fillWidth: true

			level: root.headingFontLevel
			wrapMode: Text.NoWrap
			elide: Text.ElideRight
			font.capitalization: Font.Capitalize
			//SEE QTBUG-58307
			//try to make all heights an even number, otherwise the layout engine gets confused
			Layout.preferredHeight: implicitHeight + implicitHeight%2

			MouseArea {
				id: monthMouse
				property int previousPixelDelta

				anchors.fill: parent
				onClicked: {
					if (!stack.busy) {
						daysCalendar.headerClicked()
					}
				}
				onExited: previousPixelDelta = 0
				onWheel: function(wheel) {
					var delta = wheel.angleDelta.y || wheel.angleDelta.x
					var pixelDelta = wheel.pixelDelta.y || wheel.pixelDelta.x

					// For high-precision touchpad scrolling, we get a wheel event for basically every slightest
					// finger movement. To prevent the view from suddenly ending up in the next century, we
					// cumulate all the pixel deltas until they're larger than the label and then only change
					// the month. Standard mouse wheel scrolling is unaffected since it's fine.
					if (pixelDelta) {
						if (Math.abs(previousPixelDelta) < monthMouse.height) {
							previousPixelDelta += pixelDelta
							return
						}
					}

					if (delta >= 15) {
						daysCalendar.previous()
					} else if (delta <= -15) {
						daysCalendar.next()
					}
					previousPixelDelta = 0
				}
			}
		}
	}

	// Outer frame of the grid (below the weekday names), with rounded corners.
	Rectangle {
		id: gridFrame
		readonly property int frameTop: daysCalendar.headerModel ? root.borderWidth + daysCalendar.headerHeight : 0
		x: canvas.x
		y: canvas.y + frameTop
		width: canvas.width
		height: canvas.height - frameTop
		radius: 6
		color: "transparent"
		border.width: root.borderWidth
		border.color: Kirigami.Theme.textColor
		opacity: root.borderOpacity
	}

	// Paints the inner grid lines
	Canvas {
		id: canvas

		anchors {
			horizontalCenter: parent.horizontalCenter
			bottom: parent.bottom
		}
		width: (daysCalendar.cellWidth + root.borderWidth) * gridColumns + root.borderWidth
		height: daysCalendar.gridLineY(calendarGrid.rows) + root.borderWidth

		opacity: root.borderOpacity
		antialiasing: false
		clip: false
		onPaint: {
			var ctx = getContext("2d");
			// this is needed as otherwise the canvas seems to have some sort of
			// inner clip region which does not update on size changes
			ctx.reset()
			ctx.save()
			ctx.clearRect(0, 0, canvas.width, canvas.height)
			ctx.strokeStyle = Kirigami.Theme.textColor
			ctx.lineWidth = root.borderWidth
			ctx.globalAlpha = 1.0

			ctx.beginPath()

			// When line is more wide than 1px, it is painted with 1px line at the actual coords
			// and then 1px lines are added first to the left of the middle then right (then left again)
			// So all the lines need to be offset a bit to have their middle point in the center
			// of the grid spacing rather than on the left most pixel, otherwise they will be painted
			// over the days grid which will be visible on eg. mouse hover
			var lineBasePoint = Math.floor(root.borderWidth / 2)

			// The weekday names row has no lines around it; the grid starts below it.
			var hasHeader = !!daysCalendar.headerModel
			var gridTop = hasHeader ? root.borderWidth + daysCalendar.headerHeight : 0

			// Inner lines only; the outer frame is a rounded Rectangle (gridFrame).
			// horizontal lines
			for (var i = hasHeader ? 2 : 1; i < calendarGrid.rows; i++) {
				var lineY = lineBasePoint + daysCalendar.gridLineY(i)

				// Stop short of the frame so the lines don't darken where they meet it.
				ctx.moveTo(showWeekNumbers ? daysCalendar.cellWidth + root.borderWidth : root.borderWidth, lineY)
				ctx.lineTo(width - root.borderWidth, lineY)
			}

			// vertical lines
			for (var i = 1; i < gridColumns; i++) {
				var lineX = lineBasePoint + (daysCalendar.cellWidth + root.borderWidth) * (i)
				ctx.moveTo(lineX, gridTop + root.borderWidth)
				ctx.lineTo(lineX, height - root.borderWidth)
			}

			ctx.closePath()
			ctx.stroke()
			ctx.restore()
		}
	}

	KSvg.Svg {
		id: calendarSvg
		imagePath: "widgets/calendar"
	}

	Component {
		id: themeBadgeComponent
		Item {
			id: themeBadge
			KSvg.SvgItem {
				id: eventsMarker
				anchors.bottom: themeBadge.bottom
				anchors.right: themeBadge.right
				height: parent.height / 3
				width: height
				svg: calendarSvg
				elementId: "event"
			}
		}
	}

	Component {
		id: eventColorsBarBadgeComponent
		EventColorsBarBadge {}
	}

	Component {
		id: dotsBadgeComponent
		DotsBadge {}
	}

	Component {
		id: eventTitlesBadgeComponent
		EventTitlesBadge {}
	}

	Column {
		id: weeksColumn
		visible: showWeekNumbers
		anchors {
			top: canvas.top
			left: canvas.left
			bottom: canvas.bottom
			// The borderWidth needs to be counted twice here because it goes
			// in fact through two lines - the topmost one (the outer edge)
			// and then the one below weekday strings
			topMargin: daysCalendar.headerHeight + root.borderWidth + root.borderWidth
		}
		spacing: root.borderWidth

		Repeater {
			model: showWeekNumbers ? calendarBackend.weeksModel : []

			PlasmaComponents3.Label {
				height: daysCalendar.cellHeight
				width: daysCalendar.cellWidth
				horizontalAlignment: Text.AlignHCenter
				verticalAlignment: Text.AlignVCenter
				font.pointSize: -1 // Ignore pixelSize warning
				font.pixelSize: Math.max(Kirigami.Theme.smallFont.pixelSize, Math.min(daysCalendar.cellHeight / 3, daysCalendar.cellWidth * 5/8))
				readonly property bool isCurrentWeek: root.currentMonthContainsToday && modelData == calendarBackend.currentWeek()
				readonly property bool showHighlight: isCurrentWeek && root.highlightCurrentDayWeek
				color: showHighlight ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
				opacity: showHighlight ? 0.75 : 0.4
				text: modelData
			}
		}
	}

	// Weekend columns: one tinted strip per column, from the weekday name to the last week.
	// Only in the days view (it has weekday names), not the year / decade views.
	// Adjacent weekend days share one strip.
	Repeater {
		model: {
			if (!daysCalendar.headerModel) {
				return []
			}
			var flags = []
			for (var i = 0; i < daysCalendar.columns; i++) {
				var dayOfWeek = (calendarBackend.firstDayOfWeek + i) % 7
				flags.push(Shared.isWeekend(new Date(2024, 0, 7 + dayOfWeek))) // 2024-01-07 is a Sunday
			}
			return Shared.runsOf(flags)
		}
		Rectangle {
			// Cover the grid lines around the cells too, so the tint and the lines line up.
			x: calendarGrid.x + modelData.first * (daysCalendar.cellWidth + root.borderWidth) - root.borderWidth
			// Below the weekday names, like the grid frame.
			y: gridFrame.y
			width: modelData.count * (daysCalendar.cellWidth + root.borderWidth) + root.borderWidth
			height: gridFrame.height
			radius: 6
			color: Kirigami.Theme.textColor
			opacity: 0.04
		}
	}

	Grid {
		id: calendarGrid

		anchors {
			right: canvas.right
			rightMargin: root.borderWidth
			bottom: parent.bottom
			bottomMargin: root.borderWidth
		}

		columns: daysCalendar.columns
		rows: daysCalendar.rows + (daysCalendar.headerModel ? 1 : 0)

		spacing: root.borderWidth
		Repeater {
			id: days

			PlasmaComponents3.Label {
				width: daysCalendar.cellWidth
				height: daysCalendar.headerHeight
				font.pointSize: -1 // Ignore pixelSize warning
				font.pixelSize: daysCalendar.compactHeader
					? Math.round(headerFontMetrics.height * 0.75)
					: Math.max(Kirigami.Theme.smallFont.pixelSize, Math.min(daysCalendar.cellHeight / 3, daysCalendar.cellWidth * 5/8))
				horizontalAlignment: Text.AlignHCenter
				verticalAlignment: Text.AlignVCenter
				elide: Text.ElideRight
				fontSizeMode: Text.HorizontalFit
				readonly property int currentDayIndex: (calendarBackend.firstDayOfWeek + index) % 7
				readonly property bool isCurrentDay: root.currentMonthContainsToday && root.today && root.today.getDay() === currentDayIndex
				readonly property bool showHighlight: isCurrentDay && root.highlightCurrentDayWeek
				color: showHighlight ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
				opacity: showHighlight ? 0.75 : 0.4
				text: Qt.locale().dayName(currentDayIndex, Locale.ShortFormat)
			}
		}

		Repeater {
			id: repeater

			DayDelegate {
				id: delegate
				width: daysCalendar.cellWidth
				height: daysCalendar.cellHeight
				calendarView: daysCalendar

				onClicked: daysCalendar.activated(index, model, delegate)
				onDoubleClicked: daysCalendar.doubleClicked(index, model, delegate)

				eventBadgeType: {
					switch (daysCalendar.eventBadgeType) {
						case 'bottomBar':
						case 'dots':
						case 'eventTitles':
							return daysCalendar.eventBadgeType

						case 'theme':
						default:
							if (calendarSvg.hasElement('event')) {
								return daysCalendar.eventBadgeType
							} else {
								return 'bottomBar'
							}
					}
				}

					Connections {
						target: daysCalendar
						function onActivateHighlightedItem() {
							if (delegate.containsMouse) {
								delegate.clicked(null)
							}
						}
				}
			}
		}
	}

	// Dragging an event: the days it would take, tinted.
	function cellX(index) {
		return calendarGrid.x + (index % columns) * (cellWidth + root.borderWidth)
	}
	function cellY(index) {
		return calendarGrid.y + gridLineY(Math.floor(index / columns) + (headerModel ? 1 : 0))
	}
	function isDragSource(eventItem) {
		var d = eventDrag
		return !!d && !!eventItem && d.eventItem.id === eventItem.id && d.eventItem.calendarId === eventItem.calendarId
	}
	Repeater {
		model: {
			var d = daysCalendar.eventDrag
			var cells = []
			if (d) {
				var last = Math.min(daysCalendar.rows * daysCalendar.columns - 1, d.targetFirst + d.targetCount - 1)
				for (var i = Math.max(0, d.targetFirst); i <= last; i++) {
					cells.push(i)
				}
			}
			return cells
		}
		Rectangle {
			x: daysCalendar.cellX(modelData)
			y: daysCalendar.cellY(modelData)
			width: daysCalendar.cellWidth
			height: daysCalendar.cellHeight
			radius: 4
			color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.18)
			border.width: 1
			border.color: Kirigami.Theme.highlightColor
		}
	}

	// Multi-day events: one bar per week row across the days, above the cells, in the lanes the
	// cells keep free at their top (model.reservedRows). Only the bars take the mouse, the rest of
	// the cells still get clicks.
	Repeater {
		model: daysCalendar.eventBadgeType === 'eventTitles' && daysCalendar.headerModel ? daysCalendar.spanBars : []

		Rectangle {
			id: spanBar
			readonly property var bar: modelData
			readonly property var eventItem: bar.eventItem
			readonly property color barColor: appletConfig.eventColor(eventItem ? eventItem.backgroundColor : null)
			readonly property string response: Shared.myResponse(eventItem)
			readonly property int columnStep: daysCalendar.cellWidth + root.borderWidth
			readonly property bool cutLeft: bar.continuesBefore
			readonly property bool cutRight: bar.continuesAfter
			readonly property real cornerRadius: Math.min(7, height / 2)

			x: calendarGrid.x + bar.first * columnStep + 1
			y: calendarGrid.y + daysCalendar.gridLineY(bar.week + 1) + daysCalendar.eventTitlesTopOffset
				+ bar.lane * (daysCalendar.eventTitleRowHeight + daysCalendar.eventTitleRowSpacing)
			width: (bar.last - bar.first + 1) * columnStep - root.borderWidth - 2
			height: daysCalendar.eventTitleRowHeight
			// Past days are dimmed like the cells. Being dragged: faded (not for a copy), the ghost
			// stands in for it once dropped.
			readonly property bool dragSource: daysCalendar.isDragSource(eventItem)
			opacity: dragSource && !daysCalendar.eventDrag.copy ? (daysCalendar.eventDrag.pending ? 0 : 0.35)
				: typeof timeModel !== "undefined" && Shared.isPastDay(new Date(bar.lastTime), timeModel.currentTime) ? appletConfig.pastOpacity : 1

			// Square ends where the event continues in the previous / next week row.
			radius: cornerRadius
			topLeftRadius: cutLeft ? 0 : cornerRadius
			bottomLeftRadius: cutLeft ? 0 : cornerRadius
			topRightRadius: cutRight ? 0 : cornerRadius
			bottomRightRadius: cutRight ? 0 : cornerRadius
			color: appletConfig.eventFillColor(barColor, response)
			border.width: 1
			border.color: appletConfig.eventOutlineColor(barColor, response)

			StripeFill {
				visible: spanBar.response === 'tentative'
				anchors.fill: parent
				anchors.margins: 1
				radius: spanBar.cutLeft || spanBar.cutRight ? 0 : Math.max(0, spanBar.cornerRadius - 1)
				stripeColor: spanBar.barColor
			}

			// Title at the start of the bar, again in each week row.
			Text {
				anchors.fill: parent
				anchors.leftMargin: 4
				anchors.rightMargin: 1
				verticalAlignment: Text.AlignVCenter
				text: spanBar.eventItem ? spanBar.eventItem.summary : ""
				color: appletConfig.eventTextColor(spanBar.barColor, spanBar.response)
				font.strikeout: spanBar.response === 'declined'
				font.family: appletConfig.eventFont.family
				font.pointSize: appletConfig.eventFont.pointSize
				// Event in progress
				font.bold: !!spanBar.eventItem && !(spanBar.eventItem.start && spanBar.eventItem.start.date)
					&& typeof timeModel !== "undefined"
					&& spanBar.eventItem.startDateTime <= timeModel.currentTime && timeModel.currentTime < spanBar.eventItem.endDateTime
				elide: Text.ElideRight
				wrapMode: Text.NoWrap
			}

			// Click opens the event, right click its menu, press and drag moves it to other days
			// (the whole event, by the days dragged; Ctrl: a copy).
			MouseArea {
				anchors.fill: parent
				cursorShape: dragged ? Qt.ClosedHandCursor : Qt.PointingHandCursor
				acceptedButtons: Qt.LeftButton | Qt.RightButton
				readonly property bool draggable: daysCalendar.canDragEvent(spanBar.eventItem)
				preventStealing: draggable
				property point pressPoint
				property bool dragged: false
				onPressed: function(mouse) {
					dragged = false
					pressPoint = Qt.point(mouse.x, mouse.y)
				}
				onPositionChanged: function(mouse) {
					if (!draggable || !(pressedButtons & Qt.LeftButton)) {
						return
					}
					var copy = !!(mouse.modifiers & Qt.ControlModifier)
					if (dragged) {
						daysCalendar.eventDragMove(mapToItem(daysCalendar, mouse.x, mouse.y), copy)
					} else if (Math.abs(mouse.x - pressPoint.x) + Math.abs(mouse.y - pressPoint.y) >= Qt.styleHints.startDragDistance) {
						dragged = true
						daysCalendar.eventDragBegin(spanBar.eventItem, mapToItem(daysCalendar, pressPoint.x, pressPoint.y), copy)
						daysCalendar.eventDragMove(mapToItem(daysCalendar, mouse.x, mouse.y), copy)
					}
				}
				onReleased: function(mouse) {
					if (dragged) {
						daysCalendar.eventDragDrop(!!(mouse.modifiers & Qt.ControlModifier))
					}
				}
				onCanceled: {
					if (dragged) {
						dragged = false
						daysCalendar.eventDragCancel()
					}
				}
				onClicked: function(mouse) {
					if (dragged) { // The end of a drag, not a click
						dragged = false
					} else if (mouse.button === Qt.RightButton) {
						popup.showEventMenu(spanBar.eventItem, spanBar, mouse.x, mouse.y)
					} else {
						popup.activateEvent(spanBar.eventItem)
					}
				}
			}

			PlasmaCore.ToolTipArea {
				anchors.fill: parent
				mainText: spanBar.eventItem ? spanBar.eventItem.summary : ""
				subText: containsMouse ? eventModel.eventDetailsText(spanBar.eventItem) : ""
				textFormat: Text.PlainText
			}
		}
	}

	// The dragged event on its new first day (in the first event row), with its title.
	Rectangle {
		id: dragTargetGhost
		readonly property var info: daysCalendar.eventDrag
		readonly property int cell: info ? Math.max(0, Math.min(daysCalendar.rows * daysCalendar.columns - 1, info.targetFirst)) : 0
		readonly property color barColor: appletConfig.eventColor(info ? info.eventItem.backgroundColor : null)
		z: 2
		visible: !!info
		x: daysCalendar.cellX(cell) + 1
		y: daysCalendar.cellY(cell) + daysCalendar.eventTitlesTopOffset
		width: daysCalendar.cellWidth - 2
		height: daysCalendar.eventTitleRowHeight
		radius: Math.min(7, height / 2)
		color: barColor
		border.width: 1
		border.color: Kirigami.Theme.highlightColor
		Text {
			anchors.fill: parent
			anchors.leftMargin: 4
			anchors.rightMargin: copyBadge.visible ? copyBadge.width + 2 : 1
			verticalAlignment: Text.AlignVCenter
			text: dragTargetGhost.info ? dragTargetGhost.info.eventItem.summary : ""
			color: Shared.contrastTextColor(dragTargetGhost.barColor)
			font.family: appletConfig.eventFont.family
			font.pointSize: appletConfig.eventFont.pointSize
			elide: Text.ElideRight
			wrapMode: Text.NoWrap
		}
		DragCopyBadge {
			id: copyBadge
			visible: !!dragTargetGhost.info && dragTargetGhost.info.copy
			size: Math.min(Kirigami.Units.iconSizes.small, parent.height - 2)
			anchors.right: parent.right
			anchors.rightMargin: 1
			anchors.verticalCenter: parent.verticalCenter
		}
	}
}
