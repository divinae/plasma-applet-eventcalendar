import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore

import "ForecastChart.js" as ForecastChart
import "Shared.js" as Shared
import "WeatherIcons.js" as WeatherIcons
import "lib/ColorUtil.js" as ColorUtil
import "./weather/WeatherApi.js" as WeatherApi

Item {
	id: meteogramView
	width: 400
	height: 100
	property bool clock24h: appletConfig.clock24h
	property int visibleDuration: 9
	property alias xAxisScale: graph.xAxisScale
	property int xAxisLabelEvery: 1
	property alias rainUnits: graph.rainUnits

	property bool populated: false

	// Settings > Weather > Forecast chart > Style, like the Weather panel's chart: "fancy" draws a smooth
	// line colored by the temperature over a soft area, the nights shaded, a dashed line at freezing,
	// rounded rain bars with the amounts at their peaks, the high and the low in bold, on a round scale.
	readonly property bool fancy: plasmoid.configuration.weatherChartStyle === "fancy"
	onFancyChanged: {
		graph.updateScale()
		graph.update()
	}

	onClock24hChanged: {
		graph.gridData = formatXAxisLabels(graph.gridData)
		graph.update()
	}

	onVisibleDurationChanged: {
		graph.update()
	}

	Rectangle {
		visible: typeof root === 'undefined'
		color: Kirigami.Theme.backgroundColor
		anchors.fill: parent
	}

	Connections {
		target: appletConfig
		function onMeteogramTextColorChanged() { graph.update() }
		function onMeteogramScaleColorChanged() { graph.update() }
		function onMeteogramPositiveTempColorChanged() { graph.update() }
		function onMeteogramNegativeTempColorChanged() { graph.update() }
		function onMeteogramPrecipitationRawColorChanged() { graph.update() }
	}

	Item {
		id: graph
		anchors.fill: parent

		property int xAxisLabelHeight: 20
		property int xAxisMin: 0
		property int xAxisMax: 10
		property double xAxisScale: 0.333333333333 // 3 lines per data point
		property int yAxisLabelWidth: 30
		property int yAxisMin: -10
		property int yAxisMax: 20
		property int yAxisScale: 2
		property int yAxisScaleCount: 4
		property double yAxisRainMinScale: 2
		property double yAxisRainMax: 2
		property bool showYAxisRainMax: true
		property string rainUnits: 'mm'

		property double freezingPoint: {
			if (plasmoid.configuration.weatherUnits === "kelvin") {
				return 273.15 // https://en.wikipedia.org/wiki/Kelvin
			} else if (plasmoid.configuration.weatherUnits === "imperial") {
				return 32 // https://en.wikipedia.org/wiki/Fahrenheit
			} else { // "metric"
				return 0
			}
		}

		property int gridX: yAxisLabelWidth
		property int gridX2: width
		property int gridWidth: gridX2 - gridX
		property int gridY: 5
		property int gridY2: height - xAxisLabelHeight
		property int gridHeight: gridY2 - gridY

		property var gridData: []
		property var yData: []

		onGridDataChanged: {
			xAxisMax = Math.max(1, gridData.length - 1)
			updateScale()
		}

		function updateScale() {

			yData = []
			var yDataMin = 0
			var yDataMax = 1
			yAxisRainMax = yAxisRainMinScale
			for (var i = 0; i < gridData.length; i++) {
				var y = gridData[i].y
				yData.push(y)
				if (i === 0 || y < yDataMin) {
					yDataMin = y
				}
				if (i === 0 || y > yDataMax) {
					yDataMax = y
				}
				if (rainUnits === 'mm') {
					if (gridData[i].precipitation > yAxisRainMax) {
						yAxisRainMax = Math.ceil(gridData[i].precipitation)
					}
				}
			}
			if (rainUnits === '%') {
				yAxisRainMax = 100
			}

			if (meteogramView.fancy) {
				// A round step (1, 2, 5, 10, 20, ...) and the scale's ends on it: the highest and the
				// lowest temperature within the labeled lines.
				var step = niceStep((yDataMax - yDataMin) / (yAxisScaleCount + 1))
				yAxisScale = step
				yAxisMin = Math.floor(yDataMin / step) * step
				yAxisMax = Math.max(yAxisMin + step, Math.ceil(yDataMax / step) * step)
				return
			}
			yAxisScale = Math.ceil((yDataMax-yDataMin) / (yAxisScaleCount))
			yAxisMin = Math.floor(yDataMin)
			yAxisMax = Math.ceil(yDataMax)
		}
		function niceStep(rough) {
			var magnitude = Math.pow(10, Math.floor(Math.log(Math.max(1, rough)) / Math.LN10))
			var steps = [1, 2, 5, 10]
			for (var i = 0; i < steps.length; i++) {
				if (steps[i] * magnitude >= rough) {
					return steps[i] * magnitude
				}
			}
			return 10 * magnitude
		}

		function iconsInRange(gData, s, e) {
			var out = [];
			for (var i = Math.max(0, s); i <= e && i < gData.length; i++) {
				out.push(gData[i].weatherIcon)
			}
			return out
		}

		function getAggregatedIcon(gData, s, e) {
			return WeatherApi.getMostSevereIcon(iconsInRange(gData, s, e))
		}

		function updateGridItemAreas() {
			var areas = [];
			// Skip the first gridItem since it's area starts at the edge of the grid.
			for (var i = 1; i < gridData.length; i++) {
				var a = graph.gridPoint(i-2, graph.yAxisMin)
				var b = graph.gridPoint(i-1, graph.yAxisMin)
				var area = {}
				area.areaX = a.x
				area.areaY = a.y
				area.areaWidth = b.x - a.x
				area.areaHeight = graph.gridHeight
				area.gridItem = gridData[i]
				if (area.areaWidth <= appletConfig.meteogramColumnWidth) {
					// Show icon representing 3 hours.
					area.showIcon = (i-1) % 3 === 1 // .X..X..X.
					area.aggregratedIcon = getAggregatedIcon(gridData, i-1, i+1)
				} else {
					area.showIcon = true
					area.aggregratedIcon = area.gridItem.weatherIcon
				}
				areas.push(area)
			}
			var signature = JSON.stringify(areas)
			if (signature === lastGridItemAreasSignature) {
				return
			}
			lastGridItemAreasSignature = signature
			gridDataAreas.model = areas
		}
		property string lastGridItemAreasSignature: ""

		function gridPoint(x, y) {
			return {
				x: (x - xAxisMin) / (xAxisMax - xAxisMin) * gridWidth + gridX,
				y: gridHeight - (y - yAxisMin) / (yAxisMax - yAxisMin) * gridHeight + gridY,
			}
		}

		function update() {
			gridCanvas.requestPaint()
		}

		Item {
			id: layers
			anchors.fill: parent

			Canvas {
				id: gridCanvas
				anchors.fill: parent
				// Painted on a thread of its own, not the GUI thread in the layout: a hang in QPainter
				// must not freeze Plasma (#3).
				renderStrategy: Canvas.Threaded
				canvasSize.width: parent.width
				canvasSize.height: parent.height
				contextType: '2d'

				function drawLine(x1, y1, x2, y2) {
					var p1 = graph.gridPoint(x1, y1)
					var p2 = graph.gridPoint(x2, y2)
					context.moveTo(p1.x, p1.y)
					context.lineTo(p2.x, p2.y)
					context.stroke()
				}

				// https://stackoverflow.com/questions/7054272/how-to-draw-smooth-curve-through-n-points-using-javascript-html5-canvas
				function drawCurve(path) {
					if (path.length < 3) return

					var gridPath = []
					for (var i = 0; i < path.length; i++) {
						var item = path[i]
						var p = graph.gridPoint(item.x, item.y)
						gridPath.push(p)
					}

					context.beginPath()
					context.moveTo(gridPath[0].x, gridPath[0].y)

					// curve from 1 .. n-2
					for (var i = 1; i < path.length - 2; i++) {
						var xc = (gridPath[i].x + gridPath[i+1].x) / 2
						var yc = (gridPath[i].y + gridPath[i+1].y) / 2
						
						context.quadraticCurveTo(gridPath[i].x, gridPath[i].y, xc, yc)
					}
					var n = path.length-1
					context.quadraticCurveTo(gridPath[n-1].x, gridPath[n-1].y, gridPath[n].x, gridPath[n].y)

					context.stroke()
				}

				function paintFancy(ctx) {
					var data = graph.gridData
					var dark = appletConfig.darkTheme
					var units = plasmoid.configuration.weatherUnits
					var textColor = appletConfig.meteogramTextColor
					var xs = data.map(function(item, i) { return graph.gridPoint(i, graph.yAxisMin).x })
					var ys = data.map(function(item) { return graph.gridPoint(0, item.y).y })
					var temps = data.map(function(item) { return item.y })
					var minTemp = Math.min.apply(null, temps)
					var maxTemp = Math.max.apply(null, temps)
					// The rain of an hour is drawn between its point and the one before.
					var points = data.map(function(item, i) {
						return { iconName: item.weatherIcon, precipitation: i > 0 ? item.precipitation || 0 : 0 }
					})

					// Nights
					ctx.fillStyle = dark ? "rgba(0, 0, 0, 0.22)" : "rgba(40, 60, 140, 0.08)"
					ForecastChart.nightRanges(points).forEach(function(range) {
						var x1 = range.from === 0 ? graph.gridX : graph.gridPoint(range.from, 0).x
						var x2 = range.to === data.length - 1 ? graph.gridX2 : graph.gridPoint(range.to, 0).x
						ctx.fillRect(x1, graph.gridY, x2 - x1, graph.gridHeight)
					})

					// The scale: faint lines, the temperatures on the left, the hours below
					ctx.font = "12px \"" + Kirigami.Theme.defaultFont.family + "\""
					ctx.lineWidth = 1
					ctx.strokeStyle = ColorUtil.setAlpha(textColor, dark ? 0.14 : 0.12)
					ctx.fillStyle = ColorUtil.setAlpha(textColor, 0.7)
					ctx.textAlign = 'end'
					// Lines closer than a label's height: every other one labeled, from the top.
					var lineSpacing = graph.gridHeight * graph.yAxisScale / (graph.yAxisMax - graph.yAxisMin)
					var labelEvery = lineSpacing < 16 ? 2 : 1
					for (var y = graph.yAxisMin; y <= graph.yAxisMax; y += graph.yAxisScale) {
						var py = Math.round(graph.gridPoint(0, y).y) + 0.5
						ctx.beginPath()
						ctx.moveTo(graph.gridX, py)
						ctx.lineTo(graph.gridX2, py)
						ctx.stroke()
						if (Math.round((graph.yAxisMax - y) / graph.yAxisScale) % labelEvery === 0) {
							ctx.fillText(y + '°', graph.gridX - 3, Math.max(10, py + 4))
						}
					}
					ctx.textAlign = 'center'
					for (var h = 0; h < data.length; h++) {
						if (data[h].xLabel) {
							ctx.fillText(data[h].xLabel, xs[h], graph.gridY2 + 14)
						}
					}

					// Rain bars, rounded, at most 70 % of the height (room for the amounts)
					var rainTop = graph.gridY + 14
					var rainGradient = ctx.createLinearGradient(0, rainTop, 0, graph.gridY2)
					rainGradient.addColorStop(0, dark ? "rgba(90, 160, 255, 0.75)" : "rgba(40, 120, 230, 0.8)")
					rainGradient.addColorStop(1, dark ? "rgba(90, 160, 255, 0.3)" : "rgba(40, 120, 230, 0.35)")
					ctx.fillStyle = rainGradient
					var barTops = []
					var areaWidth = xs[1] - xs[0]
					for (var i = 1; i < data.length; i++) {
						var rain = points[i].precipitation
						if (!rain) {
							continue
						}
						var barHeight = Math.min(rain, graph.yAxisRainMax) / graph.yAxisRainMax * (graph.gridY2 - rainTop) * 0.7
						var barWidth = Math.max(2, areaWidth * 0.7)
						var left = (xs[i - 1] + xs[i]) / 2 - barWidth / 2
						var top = graph.gridY2 - barHeight
						var r = Math.min(barWidth / 2, barHeight, 4)
						ctx.beginPath()
						ctx.moveTo(left, graph.gridY2)
						ctx.lineTo(left, top + r)
						ctx.arcTo(left, top, left + r, top, r)
						ctx.lineTo(left + barWidth - r, top)
						ctx.arcTo(left + barWidth, top, left + barWidth, top + r, r)
						ctx.lineTo(left + barWidth, graph.gridY2)
						ctx.closePath()
						ctx.fill()
						barTops[i] = top
					}

					// Freezing: dashed, where the temperatures cross it
					if (minTemp < graph.freezingPoint && maxTemp > graph.freezingPoint) {
						var fy = graph.gridPoint(0, graph.freezingPoint).y
						ctx.strokeStyle = dark ? "rgba(120, 180, 255, 0.7)" : "rgba(40, 110, 220, 0.7)"
						ctx.setLineDash([4, 3])
						ctx.beginPath()
						ctx.moveTo(graph.gridX, fy)
						ctx.lineTo(graph.gridX2, fy)
						ctx.stroke()
						ctx.setLineDash([])
					}

					// Temperature: a smooth line in the temperatures' colors over the warmest one fading out
					var stops = ForecastChart.temperatureStops(minTemp, maxTemp, units)
					var lineTop = graph.gridPoint(0, maxTemp).y
					var lineBottom = graph.gridPoint(0, minTemp).y
					var lineStyle = ctx.createLinearGradient(0, lineTop, 0, Math.max(lineBottom, lineTop + 1))
					stops.forEach(function(stop) {
						lineStyle.addColorStop(stop.position, stop.color)
					})
					var area = ctx.createLinearGradient(0, lineTop, 0, graph.gridY2)
					area.addColorStop(0, ColorUtil.setAlpha(stops[0].color, dark ? 0.35 : 0.18))
					area.addColorStop(1, ColorUtil.setAlpha(stops[0].color, 0))
					var segments = ForecastChart.smoothSegments(xs, ys)
					function tracePath() {
						ctx.moveTo(xs[0], ys[0])
						segments.forEach(function(s) {
							ctx.bezierCurveTo(s.cp1x, s.cp1y, s.cp2x, s.cp2y, s.x, s.y)
						})
					}
					ctx.beginPath()
					tracePath()
					ctx.lineTo(xs[xs.length - 1], graph.gridY2)
					ctx.lineTo(xs[0], graph.gridY2)
					ctx.closePath()
					ctx.fillStyle = area
					ctx.fill()
					ctx.beginPath()
					tracePath()
					ctx.lineWidth = 3
					ctx.lineJoin = "round"
					ctx.lineCap = "round"
					ctx.strokeStyle = lineStyle
					ctx.stroke()

					// The high and the low: a ring, the temperature in bold (the low below the line when
					// there's room)
					if (maxTemp - minTemp >= 2) {
						ctx.font = "bold 12px \"" + Kirigami.Theme.defaultFont.family + "\""
						ctx.textAlign = 'left'
						;[temps.indexOf(maxTemp), temps.indexOf(minTemp)].forEach(function(k, nth) {
							ctx.beginPath()
							ctx.arc(xs[k], ys[k], 4, 0, Math.PI * 2)
							ctx.fillStyle = Kirigami.Theme.backgroundColor
							ctx.fill()
							ctx.lineWidth = 2
							ctx.strokeStyle = ForecastChart.colorAt(ForecastChart.toCelsius(temps[k], units))
							ctx.stroke()
							var label = Shared.formatTemp(temps[k])
							var labelWidth = ctx.measureText(label).width
							var below = nth === 1 && ys[k] + 20 <= graph.gridY2
							ctx.fillStyle = textColor
							ctx.fillText(label,
								Math.max(graph.gridX + 2, Math.min(xs[k] - labelWidth / 2, graph.gridX2 - labelWidth)),
								below ? ys[k] + 18 : Math.max(12, ys[k] - 8))
						})
					}

					// Rain amounts at the peaks, above their bars, far enough apart not to overlap
					ctx.font = "12px \"" + Kirigami.Theme.defaultFont.family + "\""
					ctx.textAlign = 'center'
					ctx.fillStyle = String(Kirigami.Theme.linkColor)
					var gap = Math.max(1, Math.ceil(36 / Math.max(1, areaWidth)))
					ForecastChart.rainPeaks(points, gap, graph.rainUnits === 'mm' ? 0.3 : 0).forEach(function(k) {
						var rain = points[k].precipitation
						var label = formatPrecipitation(rain)
						var labelWidth = ctx.measureText(label).width
						var cx = (xs[k - 1] + xs[k]) / 2
						ctx.fillText(label,
							Math.max(graph.gridX + labelWidth / 2, Math.min(cx, graph.gridX2 - labelWidth / 2)),
							Math.max(12, barTops[k] - 4))
					})
				}

				onPaint: {
					if (!context) {
						var ctx = gridCanvas.getContext("2d")
					}
					if (!context) return
					context.reset()
					if (graph.gridData.length < 2) return
					if (graph.yAxisMin === graph.yAxisMax) return
					if (meteogramView.fancy) {
						paintFancy(context)
						Qt.callLater(graph.updateGridItemAreas)
						return
					}

					// rain
					graph.showYAxisRainMax = false
					var gridDataAreaWidth = 0
					for (var i = 1; i < graph.gridData.length; i++) {
						var item = graph.gridData[i]
						if (item.precipitation) {
							graph.showYAxisRainMax = true
							var rainY = Math.min(item.precipitation, graph.yAxisRainMax) / graph.yAxisRainMax
							var a = graph.gridPoint(i-1, graph.yAxisMin)
							var b = graph.gridPoint(i, graph.yAxisMin)
							var h = rainY * graph.gridHeight
							gridDataAreaWidth = b.x-a.x
							context.fillStyle = appletConfig.meteogramPrecipitationColor
							context.fillRect(a.x, a.y, gridDataAreaWidth, -h)
						}
					}

					// yAxis scale
					for (var y = graph.yAxisMin; y <= graph.yAxisMax; y += graph.yAxisScale) {
						context.strokeStyle = appletConfig.meteogramScaleColor
						context.lineWidth = 1
						drawLine(graph.xAxisMin, y, graph.xAxisMax, y)

						// yAxis label: temp
						var p = graph.gridPoint(graph.xAxisMin, y)
						context.fillStyle = appletConfig.meteogramTextColor
						context.font = "12px \"" + Kirigami.Theme.defaultFont.family + "\""
						context.textAlign = 'end'
						var labelText = y + '°'
						context.fillText(labelText, p.x - 2, p.y + 6)
					}

					// xAxis scale
					for (var x = graph.xAxisMin; x <= graph.xAxisMax; x += graph.xAxisScale) {
						context.strokeStyle = appletConfig.meteogramScaleColor
						context.lineWidth = 1
						drawLine(x, graph.yAxisMin, x, graph.yAxisMax)
					}
					for (var i = 0; i < graph.gridData.length; i++) {
						var item = graph.gridData[i]
						var p = graph.gridPoint(i, graph.yAxisMin)

						context.fillStyle = appletConfig.meteogramTextColor
						context.font = "12px \"" + Kirigami.Theme.defaultFont.family + "\""
						context.textAlign = 'center'

						if (item.xLabel) {
							context.fillText(item.xLabel, p.x, p.y + 12 + 2)
						}
					}

					// temp
					context.lineWidth = 3
					var path = []
					var pathMinY
					var pathMaxY
					for (var i = 0; i < graph.gridData.length; i++) {
						var item = graph.gridData[i]
						path.push({ x: i, y: item.y })
						if (i === 0 || item.y < pathMinY) pathMinY = item.y
						if (i === 0 || item.y > pathMaxY) pathMaxY = item.y
					}
					
					var pZeroY = graph.gridPoint(0, graph.freezingPoint).y
					var pMaxY = graph.gridPoint(0, pathMinY).y // y axis gets flipped
					var pMinY = graph.gridPoint(0, pathMaxY).y // y axis gets flipped
					var height = pMaxY - pMinY
					var pZeroYRatio = (pZeroY-pMinY) / height
					if (pZeroYRatio <= 0) {
						context.strokeStyle = appletConfig.meteogramNegativeTempColor
					} else if (pZeroYRatio >= 1) {
						context.strokeStyle = appletConfig.meteogramPositiveTempColor
					} else {
						var gradient = context.createLinearGradient(0, pMinY, 0, pMaxY)
						gradient.addColorStop(pZeroYRatio-0.0001, appletConfig.meteogramPositiveTempColor)
						gradient.addColorStop(pZeroYRatio, appletConfig.meteogramNegativeTempColor)
						context.strokeStyle = gradient
					}
					drawCurve(path)

					// yAxis label: precipitation
					var lastLabelText = ''
					var lastLabelVisible = false
					var lastLabelStaggered = false
					for (var i = 1; i < graph.gridData.length; i++) {
						var item = graph.gridData[i]
						if (item.precipitation && (
							(graph.rainUnits === 'mm' && item.precipitation > 0.3)
							|| (graph.rainUnits === '%')
						)) {
							var labelText = formatPrecipitation(item.precipitation)

							if (labelText === lastLabelText) {
								lastLabelText = labelText
								lastLabelVisible = false
								lastLabelStaggered = false
								continue
							}

							context.fillStyle = appletConfig.meteogramPrecipitationTextColor
							context.font = "12px \"" + Kirigami.Theme.defaultFont.family + "\""

							var labelWidth = context.measureText(labelText).width
							var p
							// If there isn't enough room
							if (gridDataAreaWidth < labelWidth) { // left align using previous point
								p = graph.gridPoint(i-1, graph.yAxisMin)
								context.textAlign = 'left'
							} else { // otherwise right align
								p = graph.gridPoint(i, graph.yAxisMin)
								context.textAlign = 'end'
							}

							var pY = graph.gridY + 6

							// Stagger the labels so they don't overlap.
							if (gridDataAreaWidth < labelWidth && lastLabelVisible && !lastLabelStaggered) {
								pY += 12 // 12px
								lastLabelStaggered = true
							} else {
								lastLabelStaggered = false
							}
							lastLabelVisible = true
							lastLabelText = labelText

							context.fillText(labelText, p.x, pY)
						} else {
							lastLabelText = ''
							lastLabelVisible = false
							lastLabelStaggered = false
						}
					}

					// Area. Deferred and skipped when unchanged, so repaints (eg: resizing)
					// don't recreate every area delegate.
					Qt.callLater(graph.updateGridItemAreas)
				}

			}

			Repeater {
				id: gridDataAreas
				anchors.fill: parent
				model: ListModel {}

				delegate: Rectangle {
					x: modelData.areaX+modelData.areaWidth
					y: modelData.areaY-modelData.areaHeight
					width: modelData.areaWidth
					height: modelData.areaHeight
					color: "transparent"

					PlasmaCore.ToolTipArea {
						id: tooltip
						anchors.fill: parent
						icon: WeatherIcons.largeSource(modelData.gridItem.weatherIcon, plasmoid.configuration.weatherIconStyle)
						mainText: modelData.gridItem.tooltipMainText
						subText: modelData.gridItem.tooltipSubText
						location: PlasmaCore.Types.BottomEdge
					}

					// Yr icons (Settings > Weather > Icons) or the fancy chart: the icons of that setting.
					// Otherwise the Weather Icons font, as before (it also has the few without an icon:
					// wi-tornado, wi-dust, ... from Weather Canada).
					readonly property bool styledIcon: (meteogramView.fancy || plasmoid.configuration.weatherIconStyle === "yr")
						&& /^weather-/.test(modelData.aggregratedIcon || "")
					Kirigami.Icon {
						visible: modelData.showIcon && parent.styledIcon
						anchors.centerIn: parent
						width: appletConfig.meteogramIconSize
						height: width
						source: parent.styledIcon ? WeatherIcons.source(modelData.aggregratedIcon, plasmoid.configuration.weatherIconStyle) : ""
						fallback: parent.styledIcon ? modelData.aggregratedIcon : ""
						color: appletConfig.meteogramIconColor
						opacity: tooltip.containsMouse ? 0.1 : 1
					}
					FontIcon {
						id: weatherIcon
						visible: modelData.showIcon && !parent.styledIcon
						anchors.centerIn: parent
						color: appletConfig.meteogramIconColor
						source: modelData.aggregratedIcon
						height: appletConfig.meteogramIconSize
						opacity: tooltip.containsMouse ? 0.1 : 1
						showOutline: false
					}
				}
			}

		}
	}

	Component.onCompleted: {
		graph.update()
	}

	function parseWeatherForecast(currentWeatherData, data) {
		var gData = []

		function parseHourlyWeatherItem(item) {
			var tooltipSubText = item.description
			if (item.precipitation) {
				tooltipSubText += ' (' + formatPrecipitation(item.precipitation) + ')'
			}
			tooltipSubText += '<br>' + item.temp + '°'

			return {
				y: item.temp,
				xTimestamp: item.dt * 1000,
				precipitation: item.precipitation,
				tooltipMainText: new Date(item.dt * 1000),
				tooltipSubText: tooltipSubText,
				weatherIcon: item.iconName || 'question',
			}
		}

		if (currentWeatherData) {
			gData.push(parseHourlyWeatherItem(currentWeatherData))
		} else {
			if (data.list.length > 0) {
				gData.push({
					y: data.list[0].temp,
					xTimestamp: Date.now(),
					precipitation: 0,
				})
			}
		}

		for (var i = 0; i < data.list.length; i++) {
			var item = data.list[i]
			gData.push(parseHourlyWeatherItem(item))
		}

		// Only forcast next _ hours
		gData = gData.slice(0, Math.max(3, Math.ceil(meteogramView.visibleDuration * meteogramView.xAxisScale) + 1))

		// Format xAxis Labels
		gData = formatXAxisLabels(gData)

		graph.gridData = gData
		graph.update()
		meteogramView.populated = true
	}

	function formatXAxisLabels(gData) {
		for (var i = 0; i < gData.length; i++) {
			var firstOrLast = i === 0 || i === gData.length-1
			var labelSkipped = i % Math.ceil(meteogramView.xAxisLabelEvery) !== 0
			if (!firstOrLast && !labelSkipped) {
				var date = new Date(gData[i].xTimestamp)
				var hour = date.getHours()
				var label = ''
				if (clock24h) {
					label += hour
				} else {
					// 12 hour clock
					// (3am = 3) (11pm = 11p)
					label += hour % 12 === 0 ? 12 : hour % 12
					label += (hour < 12 ? '' : 'p')
				}
				gData[i].xLabel = label
			} else {
				gData[i].xLabel = ''
			}
		}
		return gData
	}

	function formatDecimal(x, afterDecimal) {
		return x >= 1 ? Math.round(x) : x.toFixed(afterDecimal)
	}
	function formatPrecipitation(value) {
		var valueText = formatDecimal(value, 1)
		if (graph.rainUnits === 'mm') {
			// xgettext:no-c-format
			return i18n("%1mm", valueText)
		} else { // rainUnits == '%'
			return i18n('%1%', valueText) // Not translated as we use ''
		}
	}
}
