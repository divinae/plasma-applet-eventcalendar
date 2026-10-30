import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "ForecastChart.js" as ForecastChart
import "Shared.js" as Shared
import "WeatherIcons.js" as WeatherIcons
import "lib/ColorUtil.js" as ColorUtil

// Weather beside the Day view, in labeled sections: Now, Next hours, Next days.
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
	// Sections left out where there's little height (the Day view's right column above the tasks).
	property bool showHourly: true
	property bool showNextDays: true
	property bool loading: false // A forecast request is running
	property string errorText: "" // The last request failed
	signal retryRequested()
	readonly property bool hasData: !!current || !!today || hourly.length > 0
	// First load: a loading view instead of the (empty) sections. Refreshes keep the old data.
	readonly property bool showLoading: isSetup && loading && !hasData
	readonly property bool showData: isSetup && !showLoading && (hasData || !errorText)

	spacing: Kirigami.Units.smallSpacing

	// Secondary text (section titles, descriptions, hours): dimmed less in a light theme, where the
	// translucent card is light grey too.
	readonly property real dimOpacity: appletConfig.darkTheme ? 0.75 : 0.9
	// The chart's line and points: the accent, dark enough to stand out on a light card.
	readonly property color lineColor: appletConfig.eventColoredTextColor(Kirigami.Theme.highlightColor)

	function timeText(dt) {
		return Shared.formatTime(new Date(dt * 1000), appletConfig.clock24h ? 'HH:mm' : 'h AP')
	}
	function precipitationText(mm) {
		return mm > 0 ? i18nc("precipitation in mm", "%1 mm", Math.round(mm * 10) / 10) : ""
	}

	// The section name, underlined: a line below it, then the section's content.
	component SectionTitle: ColumnLayout {
		property alias text: titleLabel.text
		property alias detail: detailLabel.text // On the right, dimmed (eg: the rain to come)
		Layout.fillWidth: true
		Layout.topMargin: Kirigami.Units.largeSpacing * 2
		Layout.bottomMargin: Kirigami.Units.smallSpacing
		spacing: Kirigami.Units.smallSpacing
		RowLayout {
			Layout.fillWidth: true
			PlasmaComponents3.Label {
				id: titleLabel
				Layout.fillWidth: true
				elide: Text.ElideRight
				textFormat: Text.PlainText
				// Above the text below it: larger and bolder, not dimmed.
				font.weight: Font.DemiBold
				font.pointSize: appletConfig.fontPoints(Kirigami.Theme.defaultFont) * 1.1
			}
			PlasmaComponents3.Label {
				id: detailLabel
				visible: !!text
				textFormat: Text.PlainText
				opacity: panel.dimOpacity
			}
		}
		Kirigami.Separator {
			Layout.fillWidth: true
			opacity: appletConfig.darkTheme ? 0.6 : 1
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

	// No forecast yet and the request failed: why, and a way to try again.
	ColumnLayout {
		visible: panel.isSetup && !panel.loading && !panel.hasData && !!panel.errorText
		Layout.fillWidth: true
		Layout.topMargin: panel.compact ? 0 : Kirigami.Units.gridUnit * 3
		spacing: Kirigami.Units.largeSpacing
		Kirigami.Icon {
			visible: !panel.compact
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
			text: panel.errorText
			opacity: 0.7
		}
		PlasmaComponents3.Button {
			Layout.alignment: Qt.AlignHCenter
			icon.name: "view-refresh"
			text: i18n("Retry Now")
			onClicked: panel.retryRequested()
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

	// "Weather" as the card's title (like the Day view's "Tasks" beside it), the location on the
	// right with a pin, a small spinner while refreshing.
	RowLayout {
		visible: panel.showData && !panel.compact
		Layout.fillWidth: true
		spacing: Kirigami.Units.smallSpacing
		PlasmaComponents3.Label {
			text: i18n("Weather")
			textFormat: Text.PlainText
			font.weight: Font.Bold
			font.pointSize: appletConfig.fontPoints(Kirigami.Theme.defaultFont) * 1.25
		}
		Item {
			Layout.fillWidth: true
		}
		PlasmaComponents3.BusyIndicator {
			visible: panel.loading
			running: visible
			Layout.preferredWidth: Kirigami.Units.iconSizes.small
			Layout.preferredHeight: Layout.preferredWidth
		}
		Kirigami.Icon {
			visible: !!panel.locationName
			Layout.alignment: Qt.AlignVCenter
			implicitWidth: Kirigami.Units.iconSizes.small
			implicitHeight: implicitWidth
			source: "mark-location"
			opacity: panel.dimOpacity
		}
		PlasmaComponents3.Label {
			visible: !!panel.locationName
			Layout.alignment: Qt.AlignVCenter
			Layout.minimumWidth: 0
			Layout.maximumWidth: Math.ceil(implicitWidth)
			Layout.fillWidth: true
			elide: Text.ElideRight
			text: panel.locationName
			textFormat: Text.PlainText // User text: never parsed as HTML
			opacity: panel.dimOpacity
			PlasmaComponents3.ToolTip.text: text
			PlasmaComponents3.ToolTip.visible: truncated && locationHover.hovered
			HoverHandler {
				id: locationHover
			}
		}
	}

	// The icon tile's sky for a weather icon name (weather-clear, weather-showers-night, …):
	// [top, bottom] of its gradient, deep enough that the sun and the white clouds stand out.
	function skyColors(iconName) {
		var name = String(iconName || "")
		if (name.indexOf("night") >= 0) {
			return ["#1f2a5a", "#3b4a8c"]
		}
		if (name.indexOf("storm") >= 0 || name.indexOf("severe") >= 0) {
			return ["#463a6e", "#76669f"]
		}
		if (name.indexOf("fog") >= 0 || name === "weather-overcast") {
			return ["#66707c", "#949daa"]
		}
		if (name === "weather-clear" || name === "weather-few-clouds") {
			return ["#2f86dc", "#79bdf3"]
		}
		return ["#4c709a", "#86a7c9"] // Clouds, rain, snow
	}

	//--- Now (today), or the shown day's forecast
	readonly property bool showDaySummary: !isToday && !!today
	RowLayout {
		visible: panel.showData && (!!panel.current || panel.showDaySummary)
		Layout.fillWidth: true
		// Right below the card's title (no section title of its own).
		Layout.topMargin: panel.compact ? 0 : Kirigami.Units.largeSpacing
		spacing: Kirigami.Units.largeSpacing
		// The icon's background (Settings > Weather > Current weather icon background):
		// - sky: a small sky (blue by day, indigo at night, grey for fog, …) with a soft shadow,
		//   light icons (clouds) vanish on a light card otherwise
		// - subtle: a faint tile of the text color
		// - none: the icon alone, as large as the tile would be
		Item {
			id: iconTile
			readonly property string background: plasmoid.configuration.weatherIconBackground || "sky"
			readonly property var sky: panel.skyColors(panel.current ? panel.current.iconName : panel.showDaySummary ? panel.today.iconName : "")
			readonly property real radius: Math.round(width * 0.3)
			Layout.preferredWidth: (panel.compact ? Kirigami.Units.iconSizes.medium : Kirigami.Units.iconSizes.large) + Kirigami.Units.smallSpacing * 2
			Layout.preferredHeight: Layout.preferredWidth
			Rectangle {
				visible: iconTile.background === "subtle"
				anchors.fill: parent
				radius: iconTile.radius
				color: ColorUtil.setAlpha(Kirigami.Theme.textColor, appletConfig.darkTheme ? 0.1 : 0.07)
			}
			Kirigami.ShadowedRectangle {
				visible: iconTile.background === "sky"
				anchors.fill: parent
				radius: iconTile.radius
				color: iconTile.sky[1]
				shadow.size: 8
				shadow.yOffset: 2
				shadow.color: ColorUtil.setAlpha(iconTile.sky[0], appletConfig.darkTheme ? 0.5 : 0.35)
			}
			Rectangle {
				visible: iconTile.background === "sky"
				anchors.fill: parent
				radius: iconTile.radius
				gradient: Gradient {
					GradientStop { position: 0; color: iconTile.sky[0] }
					GradientStop { position: 1; color: iconTile.sky[1] }
				}
			}
			Kirigami.Icon {
				anchors.centerIn: parent
				width: iconTile.background === "none" ? parent.width : parent.width - Kirigami.Units.smallSpacing * 2
				height: width
				source: WeatherIcons.largeSource(panel.current ? panel.current.iconName : panel.showDaySummary ? panel.today.iconName : "", plasmoid.configuration.weatherIconStyle)
			}
		}
		ColumnLayout {
			Layout.fillWidth: true
			spacing: 0
			// The temperature: the panel's largest text, beside the icon.
			Kirigami.Heading {
				level: 1
				font.pointSize: appletConfig.fontPoints(Kirigami.Theme.defaultFont) * (panel.compact ? 1.4 : 1.9)
				font.weight: Font.Normal
				text: panel.current ? Shared.formatTemp(panel.current.temp)
					: panel.showDaySummary ? Shared.formatTemp(panel.today.temp.max) + " / " + Shared.formatTemp(panel.today.temp.min) : ""
			}
			PlasmaComponents3.Label {
				Layout.fillWidth: true
				elide: Text.ElideRight
				text: panel.current ? panel.current.text : panel.showDaySummary ? (panel.today.text || panel.today.description || "") : ""
				textFormat: Text.PlainText // User text: never parsed as HTML
				opacity: panel.dimOpacity
			}
			// Today: the high and the low, then the rain (when there is any), in words.
			PlasmaComponents3.Label {
				visible: !panel.compact && !!panel.today && panel.isToday
				Layout.fillWidth: true
				Layout.topMargin: 2
				elide: Text.ElideRight
				textFormat: Text.PlainText
				text: panel.today ? i18nc("high / low temperature", "High %1 · Low %2", Shared.formatTemp(panel.today.temp.max), Shared.formatTemp(panel.today.temp.min)) : ""
				opacity: panel.dimOpacity
			}
			PlasmaComponents3.Label {
				readonly property string rain: panel.today ? panel.precipitationText(panel.today.precipitation) : ""
				visible: !panel.compact && !!panel.today && panel.isToday && !!rain
				Layout.fillWidth: true
				elide: Text.ElideRight
				textFormat: Text.PlainText
				text: rain ? i18nc("precipitation during the day", "Rain: %1", rain) : ""
				opacity: panel.dimOpacity
			}
		}
		// Compact: today's range on the same row
		PlasmaComponents3.Label {
			visible: panel.compact && !!panel.today && !!panel.current
			text: panel.today ? i18nc("high / low temperature", "High %1 · Low %2", Shared.formatTemp(panel.today.temp.max), Shared.formatTemp(panel.today.temp.min)) : ""
			opacity: panel.dimOpacity
		}
	}
	// Another day: its rain (the high / low are in the heading).
	PlasmaComponents3.Label {
		readonly property string rain: panel.today ? panel.precipitationText(panel.today.precipitation) : ""
		visible: panel.showData && !panel.compact && !!panel.today && !panel.isToday && !!rain
		Layout.fillWidth: true
		Layout.topMargin: Kirigami.Units.smallSpacing
		wrapMode: Text.Wrap
		text: rain ? i18nc("precipitation during the day", "Rain: %1", rain) : ""
		opacity: panel.dimOpacity
	}
	// Past days and days beyond the forecast
	PlasmaComponents3.Label {
		visible: panel.showData && !panel.isToday && !panel.today && panel.hourly.length === 0
		Layout.fillWidth: true
		wrapMode: Text.Wrap
		text: i18n("No forecast for this day.")
		opacity: panel.dimOpacity
	}

	//--- Next hours: temperature line with rain bars, labels every 3 hours (Settings > Weather >
	// Forecast chart):
	// - simple: a line in the accent color, plain rain bars, a grey line at the current time
	// - fancy: a smooth line colored by the temperature over a soft area, the nights shaded, a dashed
	//   line at freezing, rounded rain bars, the high and the low in bold, a red line at the current time
	readonly property bool fancyChart: plasmoid.configuration.weatherChartStyle === "fancy"
	readonly property bool chartRainAmounts: plasmoid.configuration.weatherChartRainAmounts
	SectionTitle {
		visible: panel.showData && !panel.compact && panel.showHourly && panel.hourly.length > 1
		text: panel.isToday ? i18n("Next 12 hours") : i18nc("weather by hour of the shown day", "During the day")
		readonly property real rain: ForecastChart.rainTotal(hourChart.points)
		detail: panel.chartRainAmounts && rain > 0 ? i18nc("precipitation during the hours of the chart", "Rain: %1", panel.precipitationText(rain)) : ""
	}
	Item {
		id: hourChart
		visible: panel.showData && !panel.compact && panel.showHourly && points.length > 1
		Layout.fillWidth: true
		Layout.preferredHeight: Kirigami.Units.gridUnit * 7 + iconSize - Kirigami.Units.iconSizes.small

		readonly property var points: panel.hourly.slice(0, 13)
		readonly property int iconSize: plasmoid.configuration.weatherChartLargeIcons ? Kirigami.Units.iconSizes.smallMedium : Kirigami.Units.iconSizes.small
		readonly property real iconRow: iconSize + 2
		readonly property real labelRow: Math.ceil(chartFontMetrics.height) + 2
		// Plot area for the line: below the icons and temperature labels, above the hour labels.
		readonly property real plotTop: iconRow + labelRow
		readonly property real plotBottom: height - labelRow
		readonly property real minTemp: Math.min.apply(null, points.map(function(p) { return p.temp }))
		readonly property real maxTemp: Math.max.apply(null, points.map(function(p) { return p.temp }))
		readonly property real maxRain: Math.max(1, Math.max.apply(null, points.map(function(p) { return p.precipitation || 0 })))
		readonly property var rainPeaks: panel.chartRainAmounts ? ForecastChart.rainPeaks(points, 3) : []
		readonly property string units: plasmoid.configuration.weatherUnits
		// The current time: the shown day is today, and it's within the chart.
		readonly property var now: typeof timeModel !== "undefined" ? timeModel.currentTime : new Date()
		readonly property real nowIndex: panel.isToday ? ForecastChart.nowIndex(points, now.getTime()) : -1
		readonly property color nowColor: panel.fancyChart ? "#e0403a" : ColorUtil.setAlpha(Kirigami.Theme.textColor, 0.45)
		function xAt(i) {
			return points.length > 1 ? 6 + i * (width - 12) / (points.length - 1) : width / 2
		}
		function yAt(temp) {
			var range = Math.max(2, maxTemp - minTemp)
			return plotBottom - 4 - (temp - minTemp) / range * (plotBottom - plotTop - 8)
		}
		function rainHeight(rain) {
			return rain / maxRain * (plotBottom - plotTop) * 0.6
		}
		// The labeled points: every 3 hours, with the fancy chart also the high and the low.
		function isExtreme(i) {
			var t = points[i].temp
			return panel.fancyChart && maxTemp - minTemp >= 2 && (t === maxTemp || t === minTemp)
				&& points.findIndex(function(p) { return p.temp === t }) === i
		}
		function isLabeled(i) {
			// An extreme replaces the 3-hourly label next to it, so they don't overlap.
			if (i % 3 !== 0) {
				return isExtreme(i)
			}
			return isExtreme(i) || !(i > 0 && isExtreme(i - 1)) && !(i + 1 < points.length && isExtreme(i + 1))
		}
		onPointsChanged: chartCanvas.requestPaint()
		onWidthChanged: chartCanvas.requestPaint()
		onHeightChanged: chartCanvas.requestPaint()
		Connections {
			target: panel
			function onFancyChartChanged() { chartCanvas.requestPaint() }
			function onLineColorChanged() { chartCanvas.requestPaint() }
		}

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
				var fancy = panel.fancyChart
				var dark = appletConfig.darkTheme
				var xs = pts.map(function(p, i) { return hourChart.xAt(i) })
				var ys = pts.map(function(p) { return hourChart.yAt(p.temp) })
				var step = xs[1] - xs[0]

				// Nights: shaded from the top of the plot to the hour labels.
				if (fancy) {
					ctx.fillStyle = dark ? "rgba(0, 0, 0, 0.22)" : "rgba(40, 60, 140, 0.08)"
					ForecastChart.nightRanges(pts).forEach(function(range) {
						var x1 = range.from === 0 ? 0 : hourChart.xAt(range.from)
						var x2 = range.to === pts.length - 1 ? width : hourChart.xAt(range.to)
						ctx.fillRect(x1, hourChart.plotTop - 4, x2 - x1, hourChart.plotBottom - hourChart.plotTop + 4)
					})
				}

				// Rain bars
				var barWidth = Math.max(2, step * 0.5)
				if (fancy) {
					var rainGradient = ctx.createLinearGradient(0, hourChart.plotTop, 0, hourChart.plotBottom)
					rainGradient.addColorStop(0, dark ? "rgba(90, 160, 255, 0.75)" : "rgba(40, 120, 230, 0.8)")
					rainGradient.addColorStop(1, dark ? "rgba(90, 160, 255, 0.3)" : "rgba(40, 120, 230, 0.35)")
					ctx.fillStyle = rainGradient
				} else {
					ctx.fillStyle = Qt.rgba(0.2, 0.5, 0.9, dark ? 0.35 : 0.5)
				}
				for (var i = 0; i < pts.length; i++) {
					var h = hourChart.rainHeight(pts[i].precipitation || 0)
					if (h <= 0) {
						continue
					}
					var left = xs[i] - barWidth / 2
					var top = hourChart.plotBottom - h
					if (fancy) {
						var r = Math.min(barWidth / 2, h, 4)
						ctx.beginPath()
						ctx.moveTo(left, hourChart.plotBottom)
						ctx.lineTo(left, top + r)
						ctx.arcTo(left, top, left + r, top, r)
						ctx.lineTo(left + barWidth - r, top)
						ctx.arcTo(left + barWidth, top, left + barWidth, top + r, r)
						ctx.lineTo(left + barWidth, hourChart.plotBottom)
						ctx.closePath()
						ctx.fill()
					} else {
						ctx.fillRect(left, top, barWidth, h)
					}
				}

				// Freezing: a dashed line where the temperatures cross it.
				var freezing = ForecastChart.fromCelsius(0, hourChart.units)
				if (fancy && hourChart.minTemp < freezing && hourChart.maxTemp > freezing) {
					var fy = hourChart.yAt(freezing)
					ctx.strokeStyle = dark ? "rgba(120, 180, 255, 0.7)" : "rgba(40, 110, 220, 0.7)"
					ctx.lineWidth = 1
					ctx.setLineDash([4, 3])
					ctx.beginPath()
					ctx.moveTo(0, fy)
					ctx.lineTo(width, fy)
					ctx.stroke()
					ctx.setLineDash([])
				}

				// Temperature line
				var lineStyle = panel.lineColor
				if (fancy) {
					var stops = ForecastChart.temperatureStops(hourChart.minTemp, hourChart.maxTemp, hourChart.units)
					var top = hourChart.yAt(hourChart.maxTemp)
					var bottom = hourChart.yAt(hourChart.minTemp)
					lineStyle = ctx.createLinearGradient(0, top, 0, Math.max(bottom, top + 1))
					var area = ctx.createLinearGradient(0, top, 0, hourChart.plotBottom)
					stops.forEach(function(stop) {
						lineStyle.addColorStop(stop.position, stop.color)
					})
					// The area: the warmest color fading out (a blend towards the coldest one turns muddy).
					area.addColorStop(0, ColorUtil.setAlpha(stops[0].color, dark ? 0.35 : 0.18))
					area.addColorStop(1, ColorUtil.setAlpha(stops[0].color, 0))
					var segments = ForecastChart.smoothSegments(xs, ys)
					var tracePath = function() {
						ctx.moveTo(xs[0], ys[0])
						segments.forEach(function(s) {
							ctx.bezierCurveTo(s.cp1x, s.cp1y, s.cp2x, s.cp2y, s.x, s.y)
						})
					}
					ctx.beginPath()
					tracePath()
					ctx.lineTo(xs[xs.length - 1], hourChart.plotBottom)
					ctx.lineTo(xs[0], hourChart.plotBottom)
					ctx.closePath()
					ctx.fillStyle = area
					ctx.fill()
					ctx.beginPath()
					tracePath()
					ctx.lineWidth = 2.5
					ctx.lineJoin = "round"
					ctx.lineCap = "round"
					ctx.strokeStyle = lineStyle
					ctx.stroke()
				} else {
					ctx.strokeStyle = lineStyle
					ctx.lineWidth = 2
					ctx.beginPath()
					for (var j = 0; j < pts.length; j++) {
						if (j === 0) {
							ctx.moveTo(xs[j], ys[j])
						} else {
							ctx.lineTo(xs[j], ys[j])
						}
					}
					ctx.stroke()
				}

				// Points at the labels: filled (simple), rings in the line's color (fancy).
				for (var k = 0; k < pts.length; k++) {
					if (!hourChart.isLabeled(k)) {
						continue
					}
					ctx.beginPath()
					ctx.arc(xs[k], ys[k], fancy ? 3.5 : 3, 0, Math.PI * 2)
					if (fancy) {
						ctx.fillStyle = Kirigami.Theme.backgroundColor
						ctx.fill()
						ctx.lineWidth = 2
						ctx.strokeStyle = ForecastChart.colorAt(ForecastChart.toCelsius(pts[k].temp, hourChart.units))
						ctx.stroke()
					} else {
						ctx.fillStyle = lineStyle
						ctx.fill()
					}
				}
			}
		}

		// The current time: a vertical line over the plot (red with a dot on the fancy chart).
		Rectangle {
			visible: hourChart.nowIndex >= 0
			x: Math.round(hourChart.xAt(Math.max(0, hourChart.nowIndex)) - width / 2)
			y: hourChart.plotTop - 4
			width: panel.fancyChart ? 2 : 1
			height: hourChart.plotBottom - y
			color: hourChart.nowColor
			Rectangle {
				visible: panel.fancyChart
				anchors.horizontalCenter: parent.horizontalCenter
				y: -height / 2
				width: 7
				height: width
				radius: width / 2
				color: parent.color
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
					width: hourChart.iconSize
					height: width
					source: WeatherIcons.source(parent.point ? parent.point.iconName : "", plasmoid.configuration.weatherIconStyle)
					fallback: parent.point ? parent.point.iconName : ""
				}
				PlasmaComponents3.Label {
					x: Math.max(-parent.x, Math.min(-implicitWidth / 2, hourChart.width - parent.x - implicitWidth))
					y: hourChart.plotBottom + 1
					text: parent.point ? panel.timeText(parent.point.dt) : ""
					font: Kirigami.Theme.smallFont
					opacity: panel.dimOpacity
				}
			}
		}
		// The temperatures: at the labeled points, the high and the low in bold (fancy).
		Repeater {
			model: hourChart.points.length
			PlasmaComponents3.Label {
				readonly property var point: hourChart.points[index]
				visible: !!point && hourChart.isLabeled(index)
				x: Math.max(0, Math.min(hourChart.xAt(index) - implicitWidth / 2, hourChart.width - implicitWidth))
				y: hourChart.yAt(point ? point.temp : 0) - implicitHeight - 3
				text: point ? Shared.formatTemp(point.temp) : ""
				font.pointSize: Kirigami.Theme.smallFont.pointSize
				font.weight: hourChart.isExtreme(index) ? Font.Bold : Font.Normal
			}
		}
		// Rain amounts at the peaks, above their bars.
		Repeater {
			model: hourChart.rainPeaks
			PlasmaComponents3.Label {
				readonly property var point: hourChart.points[modelData]
				x: Math.max(0, Math.min(hourChart.xAt(modelData) - implicitWidth / 2, hourChart.width - implicitWidth))
				y: hourChart.plotBottom - hourChart.rainHeight(point.precipitation) - implicitHeight
				text: panel.precipitationText(point.precipitation)
				font: Kirigami.Theme.smallFont
				color: appletConfig.darkTheme ? "#8cc0ff" : "#1f6fd6"
			}
		}
	}

	//--- Next days: day, icon, high / low. With the chart's larger icons, larger here too and the
	// text to fit them.
	readonly property bool largeIcons: plasmoid.configuration.weatherChartLargeIcons
	readonly property real nextDaysFontScale: largeIcons ? 1.15 : 1
	SectionTitle {
		visible: panel.showData && !panel.compact && panel.showNextDays && panel.nextDays.length > 0
		text: i18n("Next days")
	}
	Repeater {
		model: panel.showData && !panel.compact && panel.showNextDays ? panel.nextDays.slice(0, 4) : []
		RowLayout {
			Layout.fillWidth: true
			Layout.topMargin: index > 0 ? 2 : 0
			spacing: Kirigami.Units.smallSpacing
			PlasmaComponents3.Label {
				Layout.fillWidth: true
				elide: Text.ElideRight
				text: Qt.locale().dayName(new Date(modelData.dt * 1000).getDay(), Locale.LongFormat)
				font.capitalization: Font.Capitalize
				font.pointSize: appletConfig.fontPoints(Kirigami.Theme.defaultFont) * panel.nextDaysFontScale
			}
			Kirigami.Icon {
				source: WeatherIcons.source(modelData.iconName, plasmoid.configuration.weatherIconStyle)
				fallback: modelData.iconName
				Layout.preferredWidth: panel.largeIcons ? Kirigami.Units.iconSizes.smallMedium : Kirigami.Units.iconSizes.small
				Layout.preferredHeight: Layout.preferredWidth
			}
			PlasmaComponents3.Label {
				Layout.preferredWidth: Math.round(Kirigami.Units.gridUnit * 4 * panel.nextDaysFontScale)
				horizontalAlignment: Text.AlignRight
				text: Shared.formatTemp(modelData.temp.max) + " / " + Shared.formatTemp(modelData.temp.min)
				font.pointSize: appletConfig.fontPoints(Kirigami.Theme.defaultFont) * panel.nextDaysFontScale
			}
		}
	}

	Item { Layout.fillHeight: true }
}
