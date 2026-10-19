/*
 * Copyright 2013 Heena Mahour <heena393@gmail.com>
 * Copyright 2013 Sebastian Kügler <sebas@kde.org>
 * Copyright 2013 Martin Klapetek <mklapetek@kde.org>
 * Copyright 2014 David Edmundson <davidedmundson@kde.org>
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
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import "lib/ColorUtil.js" as ColorUtil
import "LocaleFuncs.js" as LocaleFuncs

Item {
	id: clock

	property int horizontalFixedLineWidth: 300 * Screen.devicePixelRatio
	property int verticalFixedLineHeight: 24 * Screen.devicePixelRatio

	property int targetHeight: verticalFixedLineHeight

	property int horizontalHeight: {
		if (useFixedHeight) {
			return fixedHeight
		} else {
			if (showLine2) {
				// DigitalClock default
				var timeHeight = clock.height * 0.56
				var dateHeight = timeHeight * 0.8
				return timeHeight + dateHeight
			} else {
				// DigitalClock default
				var timeHeight = clock.height * 0.71
				return timeHeight
			}
		}
	}

	// The time lines; the date tile and the meeting dot are added below them (verticalExtraHeight).
	property int verticalHeight: {
		if (useFixedHeight) {
			return fixedHeight
		} else {
			if (showLine2) {
				var timeHeight = verticalFixedLineHeight
				var dateHeight = timeHeight * 0.8
				return timeHeight + dateHeight
			} else {
				var timeHeight = verticalFixedLineHeight
				return timeHeight
			}
		}
	}

	//--- Vertical panels: a calendar tile with the date, and a dot when a meeting is near.
	readonly property bool isVertical: plasmoid.formFactor === PlasmaCore.Types.Vertical
	readonly property bool showDateTile: isVertical && plasmoid.configuration.clockVerticalShowDate
	readonly property bool showNextEventDot: isVertical && plasmoid.configuration.clockShowNextEvent && !!nextEvent
	readonly property int verticalExtraHeight: (showDateTile ? dateTile.height + content.spacing : 0)
		+ (showNextEventDot ? nextEventDot.height + content.spacing : 0)

	property date currentTime: new Date()

	readonly property int fixedHeight: plasmoid.configuration.clockMaxHeight
	readonly property bool useFixedHeight: fixedHeight > 0

	readonly property bool showLine2: plasmoid.configuration.clockShowLine2
	readonly property int lineHeight2: targetHeight * plasmoid.configuration.clockLine2HeightRatio
	readonly property int lineHeight1: showLine2 ? targetHeight - lineHeight2 : targetHeight

	readonly property real fixedWidth: showLine2 ? Math.max(timeFormatSizer1.minWidth, timeFormatSizer2.minWidth) : timeFormatSizer1.minWidth

	// Next meeting chip, right of the clock. Horizontal panels only.
	readonly property var nextEvent: typeof upcomingEvents !== "undefined" ? upcomingEvents.nextEvent : null
	readonly property bool showNextEventChip: plasmoid.configuration.clockShowNextEvent
		&& plasmoid.formFactor === PlasmaCore.Types.Horizontal
		&& !!nextEvent
	readonly property real nextEventChipWidth: showNextEventChip ? nextEventChip.width + Kirigami.Units.smallSpacing * 2 : 0

	Column {
		id: content
		anchors.centerIn: parent
		anchors.horizontalCenterOffset: -clock.nextEventChipWidth / 2
		spacing: Math.max(2, Math.round(clock.width / 12))

		Column {
			id: labels
			spacing: 0
			anchors.horizontalCenter: parent.horizontalCenter

			Item {
				id: timeContainer1

				PlasmaComponents3.Label {
					id: timeLabel1
					anchors.centerIn: parent

					font.family: appletConfig.clockFontFamily
					font.weight: appletConfig.lineWeight1
					font.pointSize: -1
					font.pixelSize: timeContainer1.height
					minimumPixelSize: 1

					fontSizeMode: Text.FixedSize
					wrapMode: Text.NoWrap

					horizontalAlignment: Text.AlignHCenter
					verticalAlignment: Text.AlignVCenter
					smooth: true

					property string timeFormat: appletConfig.line1TimeFormat // Used in TimeFormatSizeHelper
					text: Qt.formatDateTime(clock.currentTime, timeFormat)
				}

				// Debugging
				// Rectangle { border.color: "#ff0"; anchors.fill: parent; border.width: 1; color: "transparent"; visible: plasmoid.configuration.debugging }
				// Rectangle { border.color: "#f00"; anchors.fill: timeLabel1; border.width: 1; color: "transparent"; visible: plasmoid.configuration.debugging }
			}
			Item {
				id: timeContainer2
				visible: clock.showLine2

				PlasmaComponents3.Label {
					id: timeLabel2
					anchors.centerIn: parent
					font.family: appletConfig.clockFontFamily
					font.weight: appletConfig.lineWeight2
					font.pointSize: -1
					font.pixelSize: timeContainer2.height
					minimumPixelSize: 1

					fontSizeMode: Text.FixedSize
					wrapMode: Text.NoWrap

					horizontalAlignment: Text.AlignHCenter
					verticalAlignment: Text.AlignVCenter
					smooth: true

					property string timeFormat: appletConfig.line2TimeFormat // Used in TimeFormatSizeHelper
					text: Qt.formatDateTime(clock.currentTime, timeFormat)
				}

				// Debugging
				// Rectangle { border.color: "#ff0"; anchors.fill: parent; border.width: 1; color: "transparent"; visible: plasmoid.configuration.debugging }
				// Rectangle { border.color: "#f00"; anchors.fill: timeLabel2; border.width: 1; color: "transparent"; visible: plasmoid.configuration.debugging }
			}
		}

		// The date in a narrow panel: the short weekday as text, the day number big and bold on a
		// badge in the highlight color. As wide as the panel allows, to stay readable.
		Column {
			id: dateTile
			visible: clock.showDateTile
			anchors.horizontalCenter: parent.horizontalCenter
			readonly property int tileWidth: Math.max(16, Math.min(clock.width - 2, Kirigami.Units.gridUnit * 2.5))
			width: tileWidth
			spacing: 0

			PlasmaComponents3.Label {
				width: parent.width
				horizontalAlignment: Text.AlignHCenter
				// "pon." / "Mon": the dot only takes room.
				text: Qt.locale().dayName(clock.currentTime.getDay(), Locale.ShortFormat).replace(/\.$/, '')
				font.family: appletConfig.clockFontFamily
				font.pointSize: -1
				font.pixelSize: Math.max(8, Math.round(dateTile.tileWidth * 0.42))
				fontSizeMode: Text.HorizontalFit
				minimumPixelSize: 7
				opacity: 0.8
			}
			Rectangle {
				width: parent.width
				height: Math.round(dateTile.tileWidth * 0.78)
				radius: Math.round(height / 4)
				color: Kirigami.Theme.highlightColor
				PlasmaComponents3.Label {
					anchors.fill: parent
					anchors.leftMargin: 1
					anchors.rightMargin: 1
					horizontalAlignment: Text.AlignHCenter
					verticalAlignment: Text.AlignVCenter
					text: clock.currentTime.getDate()
					color: Kirigami.Theme.highlightedTextColor
					font.family: appletConfig.clockFontFamily
					font.pointSize: -1
					font.pixelSize: Math.max(9, Math.round(parent.height * 0.78))
					font.weight: Font.Bold
					fontSizeMode: Text.HorizontalFit
					minimumPixelSize: 8
				}
			}
		}

		// A meeting near (the horizontal panel's chip doesn't fit): a dot in its calendar's color.
		Rectangle {
			id: nextEventDot
			visible: clock.showNextEventDot
			anchors.horizontalCenter: parent.horizontalCenter
			width: Math.max(6, Math.round(clock.width / 5))
			height: width
			radius: width / 2
			color: appletConfig.eventColor(clock.nextEvent ? clock.nextEvent.backgroundColor : "")
			border.width: 1
			border.color: ColorUtil.setAlpha(Kirigami.Theme.textColor, 0.4)
		}
	}

	// "Standup · in 5 min", or during the meeting "Standup · 12 min left" with a thin progress bar
	// under the text in the calendar's color.
	Item {
		id: nextEventChip
		visible: clock.showNextEventChip
		anchors.left: content.right
		anchors.leftMargin: Kirigami.Units.smallSpacing * 2
		anchors.verticalCenter: parent.verticalCenter
		width: chipRow.width
		height: chipRow.height

		readonly property int fontPixelSize: Math.max(Kirigami.Theme.smallFont.pixelSize, Math.round(clock.height * 0.32))
		readonly property color eventColor: appletConfig.eventColor(clock.nextEvent ? clock.nextEvent.backgroundColor : "")
		readonly property bool inProgress: typeof upcomingEvents !== "undefined" && upcomingEvents.nextEventInProgress
		readonly property bool showProgress: inProgress && plasmoid.configuration.clockShowMeetingProgress

		function whenText() {
			if (inProgress) {
				var left = upcomingEvents.nextEventMinutesLeft
				return left < 60
					? i18ncp("time left in the current meeting", "%1 min left", "%1 min left", left)
					: i18nc("time left in the current meeting, %1 = 1h20m", "%1 left", LocaleFuncs.durationShortFormat(left * 60))
			}
			var until = upcomingEvents.nextEventMinutesUntil
			return until < 60
				? i18ncp("meeting starts in", "in %1 min", "in %1 min", until)
				: i18nc("meeting starts in, %1 = 1h20m", "in %1", LocaleFuncs.durationShortFormat(until * 60))
		}

		Row {
			id: chipRow
			spacing: Kirigami.Units.smallSpacing

			Rectangle {
				anchors.verticalCenter: parent.verticalCenter
				width: Math.round(nextEventChip.fontPixelSize * 0.6)
				height: width
				radius: width / 2
				color: nextEventChip.eventColor
				border.width: 1
				border.color: ColorUtil.setAlpha(Kirigami.Theme.textColor, 0.4)
			}
			PlasmaComponents3.Label {
				id: nextEventLabel
				anchors.verticalCenter: parent.verticalCenter
				font.pointSize: -1
				font.pixelSize: nextEventChip.fontPixelSize
				text: clock.nextEvent
					? i18nc("%1 = event title, %2 = in 5 min / 12 min left", "%1 · %2", clock.nextEvent.summary, nextEventChip.whenText())
					: ""
				elide: Text.ElideMiddle // Keep the time visible.
				width: Math.min(implicitWidth, Kirigami.Units.gridUnit * 12)
			}
		}

		// Progress of the current meeting, under the text.
		Rectangle {
			visible: nextEventChip.showProgress
			x: nextEventLabel.x
			y: nextEventLabel.y + nextEventLabel.height + 1
			width: nextEventLabel.width
			height: Math.max(2, Math.round(nextEventChip.fontPixelSize / 7))
			radius: height / 2
			color: ColorUtil.setAlpha(Kirigami.Theme.textColor, 0.15)
			Rectangle {
				width: parent.width * (typeof upcomingEvents !== "undefined" ? upcomingEvents.nextEventProgress : 0)
				height: parent.height
				radius: parent.radius
				color: nextEventChip.eventColor
			}
		}
	}

	TimeFormatSizeHelper {
		id: timeFormatSizer1
		timeLabel: timeLabel1
	}
	TimeFormatSizeHelper {
		id: timeFormatSizer2
		timeLabel: timeLabel2
	}

	state: "verticalPanel"
	states: [
		State {
			name: "horizontalPanel"
			when: plasmoid.formFactor === PlasmaCore.Types.Horizontal

			PropertyChanges { target: clock
				targetHeight: clock.horizontalHeight
				width: clock.fixedWidth + clock.nextEventChipWidth
				Layout.minimumWidth: clock.fixedWidth + clock.nextEventChipWidth
				Layout.preferredWidth: clock.fixedWidth + clock.nextEventChipWidth
			}
			PropertyChanges { target: timeContainer1
				width: clock.fixedWidth
				height: clock.lineHeight1
			}
			PropertyChanges { target: timeContainer2
				width: clock.fixedWidth
				height: clock.lineHeight2
			}
		},

		State {
			name: "verticalPanel"
			when: plasmoid.formFactor === PlasmaCore.Types.Vertical

			PropertyChanges { target: clock
				targetHeight: clock.verticalHeight
				Layout.minimumHeight: clock.targetHeight + clock.verticalExtraHeight
				Layout.preferredHeight: clock.targetHeight + clock.verticalExtraHeight
			}
			PropertyChanges { target: timeContainer1
				width: clock.width
				height: clock.lineHeight1
			}
			PropertyChanges { target: timeContainer2
				width: clock.width
				height: clock.lineHeight2
			}
			PropertyChanges { target: timeLabel1
				width: timeContainer1.width
				fontSizeMode: Text.HorizontalFit
			}
			PropertyChanges { target: timeLabel2
				width: timeContainer2.width
				fontSizeMode: Text.HorizontalFit
			}
		},

		State {
			name: "floating"
			when: plasmoid.formFactor === PlasmaCore.Types.Planar

			PropertyChanges { target: clock
				targetHeight: clock.verticalFixedLineHeight
				width: clock.horizontalFixedLineWidth
				Layout.preferredWidth: clock.horizontalFixedLineWidth
				height: clock.targetHeight
				Layout.preferredHeight: clock.targetHeight
			}
			PropertyChanges { target: timeContainer1
				width: clock.width
				height: clock.lineHeight1
			}
			PropertyChanges { target: timeContainer2
				width: clock.width
				height: clock.lineHeight2
			}
			PropertyChanges { target: timeLabel1
				width: timeContainer1.width
				fontSizeMode: Text.HorizontalFit
			}
			PropertyChanges { target: timeLabel2
				width: timeContainer2.width
				fontSizeMode: Text.HorizontalFit
			}
		}
	]
}
