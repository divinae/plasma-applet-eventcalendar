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
import "lib/ColorUtil.js" as ColorUtil

MouseArea {
	id: dayStyle

	hoverEnabled: true
	property string eventBadgeType: "bottomBar"
	// 'eventTitles': day number at the top, event titles listed below it.
	readonly property bool showEventTitles: eventBadgeType === 'eventTitles'
	// Theme fonts are set in points (pixelSize is -1), so measure them.
	FontMetrics {
		id: dayHeaderFontMetrics
		font: Kirigami.Theme.defaultFont
	}
	readonly property int eventTitlesHeaderHeight: Math.ceil(dayHeaderFontMetrics.height) + 2
	// Relative to the cell size, but capped: large cells (full month view) would get huge corners.
	property real radius: Math.min(8, Math.min(width, height) * 0.2)

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

	Rectangle {
		id: todayRect
		anchors.fill: parent
		// Today: light highlight tint with a highlight-colored frame, like the week view.
		visible: today
		color: ColorUtil.setAlpha(Kirigami.Theme.highlightColor, 0.12)
		border.width: 2
		border.color: ColorUtil.setAlpha(Kirigami.Theme.highlightColor, 0.5)
		radius: dayStyle.radius
	}

	Rectangle {
		id: highlightDate
		anchors.fill: parent
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
		Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration*2 } }
		color: Kirigami.Theme.highlightColor
		radius: dayStyle.radius
		z: todayRect.z - 1
	}

	// model.events is a ListModel, or a plain array (Qt 6.12 sequence) from some calendar sources.
	function eventsLength(events) {
		if (!events) {
			return 0
		}
		if (typeof events.count === "number") {
			return events.count
		}
		if (typeof events.length === "number") {
			return events.length
		}
		return 0
	}
	function eventAt(events, index) {
		if (!events) {
			return null
		}
		if (typeof events.get === "function") {
			return events.get(index)
		}
		return events[index]
	}

	property int eventCount: eventsLength(model.events)
	property var eventColors: []
	property bool useHightlightColor: eventColors.length === 0

	onEventCountChanged: updateEventColors()
	function updateEventColors() {
		var set = {}
		for (var i = 0; i < eventCount; i++) {
			var eventItem = eventAt(model.events, i)
			if (eventItem && eventItem.backgroundColor) {
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
				switch (dayStyle.eventBadgeType) {
					case 'bottomBar': return eventColorsBarBadgeComponent
					case 'eventTitles': return eventTitlesBadgeComponent
					case 'theme': return themeBadgeComponent
					default: return dotsBadgeComponent // 'dots', and the removed 'count' / 'bottomBarHighlight'
				}
			}
			sourceComponent: badgeComponent

			readonly property var modelEvents: model.events
			readonly property int modelEventsCount: dayStyle.eventsLength(modelEvents)
			property alias dayStyle: dayStyle // aka DayDelegate
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
		font.pixelSize: Math.max(Kirigami.Theme.smallFont.pixelSize, Math.min(Math.floor(dayStyle.height / 3), Math.floor(dayStyle.width * 5/8)))
		// This is to avoid the "Both point size and
		// pixel size set. Using pixel size" warnings
		font.pointSize: -1
		font.bold: today // The frame marks today
		color: Kirigami.Theme.textColor
	}

	PlasmaCore.ToolTipArea {
		anchors.fill: parent
		// With event titles each event bar has its own tooltip.
		active: root.showTooltips && !dayStyle.showEventTitles
		visible: root.showTooltips && !dayStyle.showEventTitles // Needed with active=false to make sure the ToolTipArea doesn't close a parent ToolTipArea. Eg: DateSelector.
		mainText: containsMouse ? Qt.formatDate(thisDate, Qt.locale().dateFormat(Locale.LongFormat)) : ""
		subText: containsMouse ? tooltipBody() : ""
		function tooltipBody() {
			var count = eventsLength(model.events)
			if (!count) {
				return ''
			}
			var lines = []
			var now = new Date()
			for (var i = 0; i < count; i++) {
				var eventItem = eventAt(model.events, i)
				if (!eventItem) {
					continue
				}
				// Event text is escaped: the tooltip is rich text.
				var bullet = eventItem.endDateTime && eventItem.endDateTime < now ? "✓" : "■"
				var line = ''
				line += '<font color="' + Shared.escapeHtml(eventItem.backgroundColor) + '">' + bullet + '</font> '
				line += '<b>' + Shared.escapeHtml(eventItem.summary) + ':</b> '
				line += Shared.escapeHtml(LocaleFuncs.formatEventDuration(eventItem, {
					relativeDate: thisDate,
					clock24h: appletConfig.clock24h,
				}))
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
