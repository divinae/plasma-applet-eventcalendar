/*
 * Copyright 2013 Heena Mahour <heena393@gmail.com>
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
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.workspace.calendar as PlasmaCalendar

import "LocaleFuncs.js" as LocaleFuncs
import "Shared.js" as Shared

MouseArea {
	id: dayStyle

	hoverEnabled: true
	property string eventBadgeType: "bottomBar"
	// 'eventTitles': day number at the top, event titles listed below it.
	readonly property bool showEventTitles: eventBadgeType == 'eventTitles'
	// Theme fonts are set in points (pixelSize is -1), so measure them.
	FontMetrics {
		id: dayHeaderFontMetrics
		font: Kirigami.Theme.defaultFont
	}
	readonly property int eventTitlesHeaderHeight: Math.ceil(dayHeaderFontMetrics.height) + 2
	property string todayStyle: "theme"
	// Relative to the cell size, but capped: large cells (full month view) would get huge corners.
	property real radius: Math.min(8, Math.min(width, height) * plasmoid.configuration.monthCellRadius)

	signal activated()

	readonly property date thisDate: new Date(yearNumber, typeof monthNumber !== "undefined" ? monthNumber - 1 : 0, typeof dayNumber !== "undefined" ? dayNumber : 1)
	readonly property bool today: {
		var today = root.today
		var result = true
		if (dateMatchingPrecision >= PlasmaCalendar.Calendar.MatchYear) {
			result = result && today.getFullYear() === thisDate.getFullYear()
		}
		if (dateMatchingPrecision >= PlasmaCalendar.Calendar.MatchYearAndMonth) {
			result = result && today.getMonth() === thisDate.getMonth()
		}
		if (dateMatchingPrecision >= PlasmaCalendar.Calendar.MatchYearMonthAndDay) {
			result = result && today.getDate() === thisDate.getDate()
		}
		return result
	}
	readonly property bool selected: {
		var current = root.currentDate
		var result = true
		if (dateMatchingPrecision >= PlasmaCalendar.Calendar.MatchYear) {
			result = result && current.getFullYear() === thisDate.getFullYear()
		}
		if (dateMatchingPrecision >= PlasmaCalendar.Calendar.MatchYearAndMonth) {
			result = result && current.getMonth() === thisDate.getMonth()
		}
		if (dateMatchingPrecision >= PlasmaCalendar.Calendar.MatchYearMonthAndDay) {
			result = result && current.getDate() === thisDate.getDate()
		}
		return result
	}

	onHeightChanged: {
		// this is needed here as the text is first rendered, counting with the default root.cellHeight
		// then root.cellHeight actually changes to whatever it should be, but the Label does not pick
		// it up after that, so we need to change it explicitly after the cell size changes
		// label.font.pixelSize = Math.max(Kirigami.Theme.smallFont.pixelSize, Math.floor(daysCalendar.cellHeight / 3))
	}

	Rectangle {
		id: todayRect
		anchors.fill: parent
		// anchors.centerIn: parent
		// width: Math.min(parent.width, parent.height)
		// height: width
		// radius: width / 2
		// Today: light highlight tint with a highlight-colored frame, like the week view.
		visible: todayStyle == "theme" && today
		color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.12)
		border.width: 2
		border.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.5)
		radius: dayStyle.radius
	}

	Rectangle {
		id: highlightDate
		anchors.fill: parent
		// anchors.centerIn: parent
		// width: Math.min(parent.width, parent.height)
		// height: width
		// radius: width / 2
		// Light tints: strong fills made event titles in the cell hard to read.
		opacity: {
			if (selected) {
				return 0.22
			} else if (dayStyle.containsMouse) {
				return 0.1
			} else {
				return 0
			}
		}
		// visible: !today
		Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration*2 } }
		color: Kirigami.Theme.highlightColor
		radius: dayStyle.radius
		z: todayRect.z - 1
	}


	property int eventCount: model.events ? model.events.count : 0
	property var eventColors: []
	property bool useHightlightColor: eventColors.length === 0

	onEventCountChanged: updateEventColors()
	function updateEventColors() {
		var set = {}
		for (var i = 0; i < eventCount; i++) {
			var eventItem = model.events.get(i)
			if (eventItem.backgroundColor) {
				set[eventItem.backgroundColor] = true
			}
		}
		eventColors = Object.keys(set)
	}


	// Past days are dimmed (day number, events, weather).
	readonly property bool isPast: typeof timeModel !== "undefined" && Shared.isPastDay(thisDate, timeModel.currentTime)
	readonly property real contentOpacity: isPast ? appletConfig.pastOpacity : 1

	Item {
		id: eventBadge
		visible: model.showEventBadge || false
		opacity: dayStyle.contentOpacity
		anchors.fill: parent

		Loader {
			id: eventBadgeLoader
			anchors.fill: parent

			active: parent.visible
			property Component badgeComponent: {
				if (dayStyle.eventBadgeType == 'bottomBar') {
					return eventColorsBarBadgeComponent
				} else if (dayStyle.eventBadgeType == 'bottomBarHighlight') {
					return highlightBarBadgeComponent
				} else if (dayStyle.eventBadgeType == 'count') {
					return eventCountBadgeComponent
				} else if (dayStyle.eventBadgeType == 'dots') {
					return dotsBadgeComponent
				} else if (dayStyle.eventBadgeType == 'eventTitles') {
					return eventTitlesBadgeComponent
				} else if (dayStyle.eventBadgeType == 'theme') {
					return themeBadgeComponent
				} else {
					return null
				}
			}
			sourceComponent: badgeComponent

			readonly property var modelEvents: model.events
			readonly property int modelEventsCount: modelEvents ? modelEvents.count : 0
			property alias dayStyle: dayStyle // aka DayDelegate
		}
	}

	// Weather (month view): small icon and high temperature, top right of the cell.
	readonly property var weather: showEventTitles && root.weatherByDay ? root.weatherByDay[Shared.dayKey(thisDate)] : null
	Row {
		visible: !!dayStyle.weather
		opacity: dayStyle.contentOpacity
		anchors.top: parent.top
		anchors.right: parent.right
		anchors.rightMargin: 3
		height: dayStyle.eventTitlesHeaderHeight
		spacing: 1
		Kirigami.Icon {
			anchors.verticalCenter: parent.verticalCenter
			width: Math.round(dayStyle.eventTitlesHeaderHeight * 0.75)
			height: width
			source: dayStyle.weather ? dayStyle.weather.iconName : ""
		}
		Text {
			anchors.verticalCenter: parent.verticalCenter
			text: dayStyle.weather ? Shared.formatTemp(dayStyle.weather.temp.max) : ""
			color: Kirigami.Theme.textColor
			opacity: 0.75
			font.pixelSize: Math.round(dayHeaderFontMetrics.height * 0.7)
		}
	}

	Text {
		id: label
		anchors {
			left: parent.left
			right: parent.right
			top: parent.top
			bottom: parent.bottom
			margins: Kirigami.Units.smallSpacing
		}
		states: State {
			when: dayStyle.showEventTitles
			AnchorChanges { target: label; anchors.bottom: undefined }
			PropertyChanges { target: label
				anchors.margins: 0
				height: dayStyle.eventTitlesHeaderHeight
				verticalAlignment: Text.AlignVCenter
				font.pixelSize: Math.round(dayHeaderFontMetrics.height * 0.75)
			}
		}
		horizontalAlignment: Text.AlignHCenter
		verticalAlignment: Text.AlignVCenter
		text: model.label || dayNumber
		opacity: (isCurrent ? 1.0 : 0.5) * dayStyle.contentOpacity
		wrapMode: Text.NoWrap
		elide: Text.ElideRight
		fontSizeMode: Text.HorizontalFit
		font.pixelSize: {
			if (today && todayStyle == "bigNumber") {
				return Math.max(Kirigami.Theme.smallFont.pixelSize, Math.min(Math.floor(dayStyle.height / 2), Math.floor(dayStyle.width * 7/8)))
			} else {
				return Math.max(Kirigami.Theme.smallFont.pixelSize, Math.min(Math.floor(dayStyle.height / 3), Math.floor(dayStyle.width * 5/8)))
			}
		}
		// This is to avoid the "Both point size and
		// pixel size set. Using pixel size" warnings
		font.pointSize: -1
		font.bold: today
		color: {
			if (today) {
				if (todayStyle == "bigNumber") {
					if (dayStyle.containsMouse || dayStyle.selected) {
						return Kirigami.Theme.textColor
					} else {
						return Kirigami.Theme.highlightColor
					}
				} else { // todayStyle == "theme": bold text color, the frame marks today
					return Kirigami.Theme.textColor
				}
			} else {
				return Kirigami.Theme.textColor
			}
		}
		Behavior on color {
			ColorAnimation { duration: Kirigami.Units.shortDuration * 2 }
		}
	}

	PlasmaCore.ToolTipArea {
		anchors.fill: parent
		// With event titles each event bar has its own tooltip.
		active: root.showTooltips && !dayStyle.showEventTitles
		visible: root.showTooltips && !dayStyle.showEventTitles // Needed with active=false to make sure the ToolTipArea doesn't close a parent ToolTipArea. Eg: DateSelector.
		mainText: containsMouse ? Qt.formatDate(thisDate, Qt.locale().dateFormat(Locale.LongFormat)) : ""
		subText: containsMouse ? tooltipBody() : ""
		function tooltipBody() {
			if (!model.events) {
				return ''
			}
			var lines = []
			for (var i = 0; i < model.events.count; i++) {
				var eventItem = model.events.get(i)
				var line = ''
				line += '<font color="' + eventItem.backgroundColor + '">■</font> '
				line += '<b>' + eventItem.summary + ':</b> '
				line += LocaleFuncs.formatEventDuration(eventItem, {
					relativeDate: thisDate,
					clock24h: appletConfig.clock24h,
				})
				lines.push(line)
			}
			return lines.join('<br>')
		}
	}

	Component.onCompleted: {
		if (stack.depth === 1 && today) {
			root.date = model
		}
	}
}
