import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "Shared.js" as Shared
import "lib/ColorUtil.js" as ColorUtil

// Weather beside the Today view, in labeled sections: Now, Next hours, Next days.
// Another day than today: that day's forecast (no "Now"), its hours and the days after it.
ColumnLayout {
	id: panel

	property var current: null // { temp, iconName, text }, today only
	property var today: null // daily item of the shown day
	property var hourly: [] // hourly items: from now, or the shown day's daytime hours
	property var nextDays: [] // daily items after the shown day
	property bool isToday: true // false: the view shows another day
	property bool isSetup: true
	property string locationName: ""
	property bool compact: false // One row above the grid when the popup is narrow
	property bool loading: false // A forecast request is running
	readonly property bool hasData: !!current || !!today || hourly.length > 0
	// First load: a loading view instead of the (empty) sections. Refreshes keep the old data.
	readonly property bool showLoading: isSetup && loading && !hasData
	readonly property bool showData: isSetup && !showLoading

	spacing: Kirigami.Units.smallSpacing

	function timeText(dt) {
		return Qt.formatTime(new Date(dt * 1000), appletConfig.clock24h ? 'HH:mm' : 'h AP')
	}
	function precipitationText(mm) {
		return mm > 0 ? i18nc("precipitation in mm", "%1 mm", Math.round(mm * 10) / 10) : ""
	}

	// A line, then the section name.
	component SectionTitle: ColumnLayout {
		property alias text: titleLabel.text
		property bool showSeparator: true
		Layout.fillWidth: true
		Layout.topMargin: showSeparator ? Kirigami.Units.smallSpacing : 0
		spacing: Kirigami.Units.smallSpacing
		Kirigami.Separator {
			visible: parent.showSeparator
			Layout.fillWidth: true
			Layout.bottomMargin: Kirigami.Units.smallSpacing
		}
		PlasmaComponents3.Label {
			id: titleLabel
			Layout.fillWidth: true
			font.weight: Font.DemiBold
			opacity: 0.7
		}
	}

	// Not configured
	ColumnLayout {
		visible: !panel.isSetup
		Layout.fillWidth: true
		Kirigami.Icon {
			Layout.alignment: Qt.AlignHCenter
			source: "weather-none-available"
			Layout.preferredWidth: Kirigami.Units.iconSizes.large
			Layout.preferredHeight: Layout.preferredWidth
			opacity: 0.6
		}
		PlasmaComponents3.Label {
			Layout.fillWidth: true
			horizontalAlignment: Text.AlignHCenter
			wrapMode: Text.Wrap
			text: i18n("Set a location in Settings > Weather to see the forecast here.")
			opacity: 0.7
		}
	}

	// Loading (first time): spinner and text, centered; one row in the compact layout.
	GridLayout {
		visible: panel.showLoading
		Layout.fillWidth: true
		Layout.topMargin: panel.compact ? 0 : Kirigami.Units.gridUnit * 3
		columns: panel.compact ? 2 : 1
		columnSpacing: Kirigami.Units.largeSpacing
		rowSpacing: Kirigami.Units.largeSpacing
		PlasmaComponents3.BusyIndicator {
			running: parent.visible
			Layout.preferredWidth: panel.compact ? Kirigami.Units.iconSizes.medium : Kirigami.Units.iconSizes.large
			Layout.preferredHeight: Layout.preferredWidth
			Layout.alignment: panel.compact ? Qt.AlignVCenter : Qt.AlignHCenter
		}
		PlasmaComponents3.Label {
			Layout.fillWidth: !panel.compact
			Layout.alignment: Qt.AlignVCenter
			horizontalAlignment: panel.compact ? Text.AlignLeft : Text.AlignHCenter
			text: i18n("Loading weather…")
			opacity: 0.7
		}
	}

	// Location, with a small spinner while refreshing.
	RowLayout {
		visible: panel.showData && !panel.compact && !!panel.locationName
		Layout.fillWidth: true
		PlasmaComponents3.Label {
			Layout.fillWidth: true
			elide: Text.ElideRight
			text: panel.locationName
			font.weight: Font.Bold
		}
		PlasmaComponents3.BusyIndicator {
			visible: panel.loading
			running: visible
			Layout.preferredWidth: Kirigami.Units.iconSizes.small
			Layout.preferredHeight: Layout.preferredWidth
		}
	}

	//--- Now (today), or the shown day's forecast
	readonly property bool showDaySummary: !isToday && !!today
	SectionTitle {
		visible: panel.showData && !panel.compact && (!!panel.current || panel.showDaySummary)
		showSeparator: false
		text: panel.isToday ? i18nc("current weather", "Now") : i18nc("weather of the day shown in the Today view", "Forecast")
	}
	RowLayout {
		visible: panel.showData && (!!panel.current || panel.showDaySummary)
		Layout.fillWidth: true
		spacing: Kirigami.Units.largeSpacing
		// Colored icon on a soft round backdrop: light icons (clouds) vanish on a light theme otherwise.
		Rectangle {
			Layout.preferredWidth: (panel.compact ? Kirigami.Units.iconSizes.medium : Kirigami.Units.iconSizes.large) + Kirigami.Units.smallSpacing * 2
			Layout.preferredHeight: Layout.preferredWidth
			radius: width / 2
			color: ColorUtil.setAlpha(Kirigami.Theme.textColor, 0.12)
			Kirigami.Icon {
				anchors.centerIn: parent
				width: parent.width - Kirigami.Units.smallSpacing * 2
				height: width
				source: panel.current ? panel.current.iconName : panel.showDaySummary ? panel.today.iconName : ""
			}
		}
		ColumnLayout {
			Layout.fillWidth: true
			spacing: 0
			Kirigami.Heading {
				level: 2
				text: panel.current ? Shared.formatTemp(panel.current.temp)
					: panel.showDaySummary ? Shared.formatTemp(panel.today.temp.max) + " / " + Shared.formatTemp(panel.today.temp.min) : ""
			}
			PlasmaComponents3.Label {
				Layout.fillWidth: true
				elide: Text.ElideRight
				text: panel.current ? panel.current.text : panel.showDaySummary ? (panel.today.text || panel.today.description || "") : ""
				opacity: 0.8
			}
		}
		// Compact: today's range on the same row
		PlasmaComponents3.Label {
			visible: panel.compact && !!panel.today && !!panel.current
			text: panel.today ? i18nc("high / low temperature", "High %1 · Low %2", Shared.formatTemp(panel.today.temp.max), Shared.formatTemp(panel.today.temp.min)) : ""
			opacity: 0.8
		}
	}
	PlasmaComponents3.Label {
		visible: panel.showData && !panel.compact && !!panel.today
		Layout.fillWidth: true
		wrapMode: Text.Wrap
		text: {
			if (!panel.today) {
				return ""
			}
			if (!panel.isToday) {
				var dayRain = panel.precipitationText(panel.today.precipitation)
				return dayRain ? i18nc("precipitation during the day", "Rain: %1", dayRain) : ""
			}
			var s = i18nc("today's high / low temperature", "Today: high %1, low %2", Shared.formatTemp(panel.today.temp.max), Shared.formatTemp(panel.today.temp.min))
			var rain = panel.precipitationText(panel.today.precipitation)
			return rain ? s + ", " + i18nc("precipitation", "rain %1", rain) : s
		}
		opacity: 0.8
	}

	// Past days and days beyond the forecast
	PlasmaComponents3.Label {
		visible: panel.showData && !panel.isToday && !panel.today && panel.hourly.length === 0
		Layout.fillWidth: true
		wrapMode: Text.Wrap
		text: i18n("No forecast for this day.")
		opacity: 0.7
	}

	//--- Next hours: temperature line with rain bars, labels every 3 hours
	SectionTitle {
		visible: panel.showData && !panel.compact && panel.hourly.length > 1
		text: panel.isToday ? i18n("Next 12 hours") : i18nc("weather by hour of the shown day", "During the day")
	}
	Item {
		id: hourChart
		visible: panel.showData && !panel.compact && points.length > 1
		Layout.fillWidth: true
		Layout.preferredHeight: Kirigami.Units.gridUnit * 7

		readonly property var points: panel.hourly.slice(0, 13)
		readonly property real iconRow: Kirigami.Units.iconSizes.small + 2
		readonly property real labelRow: Math.ceil(chartFontMetrics.height) + 2
		// Plot area for the line: below the icons and temperature labels, above the hour labels.
		readonly property real plotTop: iconRow + labelRow
		readonly property real plotBottom: height - labelRow
		readonly property real minTemp: Math.min.apply(null, points.map(function(p) { return p.temp }))
		readonly property real maxTemp: Math.max.apply(null, points.map(function(p) { return p.temp }))
		readonly property real maxRain: Math.max(1, Math.max.apply(null, points.map(function(p) { return p.precipitation || 0 })))
		function xAt(i) {
			return points.length > 1 ? 6 + i * (width - 12) / (points.length - 1) : width / 2
		}
		function yAt(temp) {
			var range = Math.max(2, maxTemp - minTemp)
			return plotBottom - 4 - (temp - minTemp) / range * (plotBottom - plotTop - 8)
		}
		onPointsChanged: chartCanvas.requestPaint()
		onWidthChanged: chartCanvas.requestPaint()
		onHeightChanged: chartCanvas.requestPaint()

		FontMetrics {
			id: chartFontMetrics
			font: Kirigami.Theme.smallFont
		}

		Canvas {
			id: chartCanvas
			anchors.fill: parent
			onPaint: {
				var ctx = getContext("2d")
				ctx.reset()
				var pts = hourChart.points
				if (pts.length < 2) {
					return
				}
				// Rain bars
				var barWidth = Math.max(2, (width - 12) / (pts.length - 1) * 0.5)
				ctx.fillStyle = Qt.rgba(0.2, 0.5, 0.9, 0.35)
				for (var i = 0; i < pts.length; i++) {
					var rain = pts[i].precipitation || 0
					if (rain > 0) {
						var h = rain / hourChart.maxRain * (hourChart.plotBottom - hourChart.plotTop) * 0.6
						ctx.fillRect(hourChart.xAt(i) - barWidth / 2, hourChart.plotBottom - h, barWidth, h)
					}
				}
				// Temperature line
				ctx.strokeStyle = Kirigami.Theme.highlightColor
				ctx.lineWidth = 2
				ctx.beginPath()
				for (var j = 0; j < pts.length; j++) {
					var x = hourChart.xAt(j)
					var y = hourChart.yAt(pts[j].temp)
					if (j === 0) {
						ctx.moveTo(x, y)
					} else {
						ctx.lineTo(x, y)
					}
				}
				ctx.stroke()
				// Points every 3 hours
				ctx.fillStyle = Kirigami.Theme.highlightColor
				for (var k = 0; k < pts.length; k += 3) {
					ctx.beginPath()
					ctx.arc(hourChart.xAt(k), hourChart.yAt(pts[k].temp), 3, 0, Math.PI * 2)
					ctx.fill()
				}
			}
		}

		// Every 3 hours: icon on top, temperature above the point, time at the bottom.
		Repeater {
			model: hourChart.points.length
			Item {
				visible: index % 3 === 0
				readonly property var point: hourChart.points[index]
				x: hourChart.xAt(index)
				width: 0
				height: hourChart.height
				Kirigami.Icon {
					x: -width / 2
					y: 0
					width: Kirigami.Units.iconSizes.small
					height: width
					source: Shared.symbolicIcon(parent.point ? parent.point.iconName : "")
					fallback: parent.point ? parent.point.iconName : ""
				}
				PlasmaComponents3.Label {
					x: -implicitWidth / 2
					y: hourChart.yAt(parent.point ? parent.point.temp : 0) - implicitHeight - 3
					text: parent.point ? Shared.formatTemp(parent.point.temp) : ""
					font: Kirigami.Theme.smallFont
				}
				PlasmaComponents3.Label {
					x: Math.max(-parent.x, Math.min(-implicitWidth / 2, hourChart.width - parent.x - implicitWidth))
					y: hourChart.plotBottom + 1
					text: parent.point ? panel.timeText(parent.point.dt) : ""
					font: Kirigami.Theme.smallFont
					opacity: 0.7
				}
			}
		}
	}

	//--- Next days: day, icon, high / low
	SectionTitle {
		visible: panel.showData && !panel.compact && panel.nextDays.length > 0
		text: i18n("Next days")
	}
	Repeater {
		model: panel.showData && !panel.compact ? panel.nextDays.slice(0, 4) : []
		RowLayout {
			Layout.fillWidth: true
			spacing: Kirigami.Units.smallSpacing
			PlasmaComponents3.Label {
				Layout.fillWidth: true
				elide: Text.ElideRight
				text: Qt.locale().dayName(new Date(modelData.dt * 1000).getDay(), Locale.LongFormat)
				font.capitalization: Font.Capitalize
			}
			Kirigami.Icon {
				source: Shared.symbolicIcon(modelData.iconName)
				fallback: modelData.iconName
				Layout.preferredWidth: Kirigami.Units.iconSizes.small
				Layout.preferredHeight: Layout.preferredWidth
			}
			PlasmaComponents3.Label {
				Layout.preferredWidth: Kirigami.Units.gridUnit * 4
				horizontalAlignment: Text.AlignRight
				text: Shared.formatTemp(modelData.temp.max) + " / " + Shared.formatTemp(modelData.temp.min)
			}
		}
	}

	Item { Layout.fillHeight: true }
}
