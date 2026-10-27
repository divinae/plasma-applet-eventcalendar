import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "Shared.js" as Shared
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
		return Qt.formatTime(new Date(dt * 1000), appletConfig.clock24h ? 'HH:mm' : 'h AP')
	}
	function precipitationText(mm) {
		return mm > 0 ? i18nc("precipitation in mm", "%1 mm", Math.round(mm * 10) / 10) : ""
	}

	// The section name, underlined: a line below it, then the section's content.
	component SectionTitle: ColumnLayout {
		property alias text: titleLabel.text
		Layout.fillWidth: true
		Layout.topMargin: Kirigami.Units.largeSpacing * 2
		Layout.bottomMargin: Kirigami.Units.smallSpacing
		spacing: Kirigami.Units.smallSpacing
		PlasmaComponents3.Label {
			id: titleLabel
			Layout.fillWidth: true
			textFormat: Text.PlainText
			// Above the text below it: larger and bolder, not dimmed.
			font.weight: Font.DemiBold
			font.pointSize: appletConfig.fontPoints(Kirigami.Theme.defaultFont) * 1.1
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
		// The colored icon on a small sky (blue by day, indigo at night, grey for fog, …) with a
		// soft shadow: light icons (clouds) vanish on a light card otherwise.
		Item {
			id: iconTile
			readonly property var sky: panel.skyColors(panel.current ? panel.current.iconName : panel.showDaySummary ? panel.today.iconName : "")
			readonly property real radius: Math.round(width * 0.3)
			Layout.preferredWidth: (panel.compact ? Kirigami.Units.iconSizes.medium : Kirigami.Units.iconSizes.large) + Kirigami.Units.smallSpacing * 2
			Layout.preferredHeight: Layout.preferredWidth
			Kirigami.ShadowedRectangle {
				anchors.fill: parent
				radius: iconTile.radius
				color: iconTile.sky[1]
				shadow.size: 8
				shadow.yOffset: 2
				shadow.color: ColorUtil.setAlpha(iconTile.sky[0], appletConfig.darkTheme ? 0.5 : 0.35)
			}
			Rectangle {
				anchors.fill: parent
				radius: iconTile.radius
				gradient: Gradient {
					GradientStop { position: 0; color: iconTile.sky[0] }
					GradientStop { position: 1; color: iconTile.sky[1] }
				}
			}
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
				ctx.fillStyle = Qt.rgba(0.2, 0.5, 0.9, appletConfig.darkTheme ? 0.35 : 0.5)
				for (var i = 0; i < pts.length; i++) {
					var rain = pts[i].precipitation || 0
					if (rain > 0) {
						var h = rain / hourChart.maxRain * (hourChart.plotBottom - hourChart.plotTop) * 0.6
						ctx.fillRect(hourChart.xAt(i) - barWidth / 2, hourChart.plotBottom - h, barWidth, h)
					}
				}
				// Temperature line
				ctx.strokeStyle = panel.lineColor
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
				ctx.fillStyle = panel.lineColor
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
					opacity: panel.dimOpacity
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
			Layout.topMargin: index > 0 ? 2 : 0
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
