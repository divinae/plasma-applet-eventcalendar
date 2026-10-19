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
	// Vertical panels: the chip doesn't fit, a dot or progress bar above the time instead.
	readonly property bool showMeetingPill: plasmoid.configuration.clockShowNextEvent
		&& plasmoid.formFactor === PlasmaCore.Types.Vertical
		&& !!nextEvent
	readonly property real meetingPillSpace: showMeetingPill ? meetingPill.height + content.spacing : 0

	Column {
		id: content
		anchors.centerIn: parent
		anchors.horizontalCenterOffset: -clock.nextEventChipWidth / 2
		spacing: Math.max(2, Math.round(clock.width / 12))

		// Next meeting in a vertical panel, above the time. Before it: a dot whose color says how
		// close it is (gray, orange from 15 min, red from 5 min). During it: a progress bar. The
		// tooltip has the details.
		Item {
			id: meetingPill
			visible: clock.showMeetingPill
			anchors.horizontalCenter: parent.horizontalCenter
			width: Math.max(16, Math.min(clock.width - 4, Kirigami.Units.gridUnit * 2.5))
			height: Math.max(7, Math.round(width / 3.5))
			readonly property bool inProgress: typeof upcomingEvents !== "undefined" && upcomingEvents.nextEventInProgress
			readonly property int minutesUntil: typeof upcomingEvents !== "undefined" ? upcomingEvents.nextEventMinutesUntil : 0

			Rectangle {
				visible: !meetingPill.inProgress
				anchors.centerIn: parent
				width: parent.height
				height: width
				radius: width / 2
				color: meetingPill.minutesUntil <= 5 ? Kirigami.Theme.negativeTextColor
					: meetingPill.minutesUntil <= 15 ? Kirigami.Theme.neutralTextColor
					: ColorUtil.setAlpha(Kirigami.Theme.textColor, 0.45)
			}
			// The theme's highlight color, not the calendar's: a light calendar color vanished on a light
			// panel.
			Rectangle {
				visible: meetingPill.inProgress
				anchors.verticalCenter: parent.verticalCenter
				width: parent.width
				height: Math.max(4, Math.round(parent.height * 0.8))
				radius: height / 2
				color: ColorUtil.setAlpha(Kirigami.Theme.textColor, 0.2)
				border.width: 1
				border.color: ColorUtil.setAlpha(Kirigami.Theme.textColor, 0.45)
				Rectangle {
					width: Math.max(parent.height, parent.width * (typeof upcomingEvents !== "undefined" ? upcomingEvents.nextEventProgress : 0))
					height: parent.height
					radius: parent.radius
					color: Kirigami.Theme.highlightColor
				}
			}
		}

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
				Layout.minimumHeight: clock.targetHeight + clock.meetingPillSpace
				Layout.preferredHeight: clock.targetHeight + clock.meetingPillSpace
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
