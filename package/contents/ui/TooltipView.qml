import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "Shared.js" as Shared

Item {
	id: tooltipContentItem

	property Item appletItem
	property int preferredTextWidth: Kirigami.Units.gridUnit * 20

	// childrenRect can still be 0 when Plasma first shows the tooltip (empty tooltip).
	// The layout's implicit size is computed reliably.
	implicitWidth: columnLayout.implicitWidth + Kirigami.Units.gridUnit
	implicitHeight: columnLayout.implicitHeight + Kirigami.Units.gridUnit
	width: implicitWidth
	height: implicitHeight

	LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
	LayoutMirroring.childrenInherit: true

	property var dataSource: timeModel.dataSource
	readonly property string timezoneTimeFormat: Qt.locale().timeFormat(Locale.ShortFormat)

	function timeForZone(zone) {
		var compactRepresentationItem = appletItem ? appletItem.compactRepresentationItem : null
		if (!compactRepresentationItem) {
			return ""
		}

		if (!dataSource.data[zone] || !dataSource.data["Local"]) {
			return "" // Time engine hasn't delivered data yet.
		}

		// get the time for the given timezone from the dataengine
		var now = dataSource.data[zone]["DateTime"]
		// get current UTC time
		var msUTC = now.getTime() + (now.getTimezoneOffset() * 60000)
		// add the dataengine TZ offset to it
		var dateTime = new Date(msUTC + (dataSource.data[zone]["Offset"] * 1000))

		var formattedTime = Qt.formatTime(dateTime, timezoneTimeFormat)

		if (dateTime.getDay() != dataSource.data["Local"]["DateTime"].getDay()) {
			formattedTime += " (" + Qt.formatDate(dateTime, Locale.ShortFormat) + ")"
		}

		return formattedTime
	}

	function nameForZone(zone) {
		if (plasmoid.configuration.displayTimezoneAsCode && dataSource.data[zone]) {
			return dataSource.data[zone]["Timezone Abbreviation"]
		}
		if (dataSource.data[zone] && dataSource.data[zone]["Timezone City"]) {
			return dataSource.data[zone]["Timezone City"].replace(/_/g, ' ')
		}
		var parts = zone.split('/')
		return parts[parts.length - 1].replace(/_/g, ' ')
	}

	ColumnLayout {
		id: columnLayout
		anchors {
			left: parent.left
			top: parent.top
			margins: Kirigami.Units.gridUnit / 2
		}
		spacing: Kirigami.Units.largeSpacing

		RowLayout {
			spacing: Kirigami.Units.largeSpacing

			Kirigami.Icon {
				id: tooltipIcon
				source: "preferences-system-time"
				Layout.alignment: Qt.AlignTop
				visible: true
				implicitWidth: Kirigami.Units.iconSizes.medium
				Layout.preferredWidth: implicitWidth
				Layout.preferredHeight: implicitWidth
			}

			ColumnLayout {
				spacing: 0

				Kirigami.Heading {
					id: tooltipMaintext
					level: 3
					Layout.minimumWidth: Math.min(implicitWidth, preferredTextWidth)
					Layout.maximumWidth: preferredTextWidth
					elide: Text.ElideRight
					// Long format has seconds, which would be stale when the clock ticks per minute.
					text: Qt.formatTime(timeModel.currentTime, Qt.locale().timeFormat(timeModel.needsSeconds ? Locale.LongFormat : Locale.ShortFormat))
				}

				PlasmaComponents3.Label {
					id: tooltipSubtext
					Layout.minimumWidth: Math.min(implicitWidth, preferredTextWidth)
					Layout.maximumWidth: preferredTextWidth
					text: Qt.formatDate(timeModel.currentTime, Qt.locale().dateFormat(Locale.LongFormat))
					opacity: 0.6
				}

				// Weather: now, and today's high / low.
				RowLayout {
					id: tooltipWeather
					readonly property var current: typeof logic !== "undefined" ? logic.currentWeatherData : null
					readonly property var today: {
						var list = typeof logic !== "undefined" && logic.dailyWeatherData ? logic.dailyWeatherData.list : null
						if (!list) {
							return null
						}
						for (var i = 0; i < list.length; i++) {
							if (Shared.isSameDate(new Date(list[i].dt * 1000), timeModel.currentTime)) {
								return list[i]
							}
						}
						return null
					}
					visible: !!current || !!today
					Layout.topMargin: Kirigami.Units.smallSpacing
					Layout.maximumWidth: preferredTextWidth
					spacing: Kirigami.Units.smallSpacing
					Kirigami.Icon {
						readonly property string iconName: tooltipWeather.current ? tooltipWeather.current.iconName : (tooltipWeather.today ? tooltipWeather.today.iconName : "")
						source: iconName ? iconName + "-symbolic" : ""
						fallback: iconName
						Layout.preferredWidth: Kirigami.Units.iconSizes.small
						Layout.preferredHeight: Layout.preferredWidth
					}
					PlasmaComponents3.Label {
						Layout.fillWidth: true
						elide: Text.ElideRight
						text: {
							var parts = []
							var c = tooltipWeather.current
							if (c && isFinite(c.temp)) {
								parts.push(Shared.formatTemp(c.temp) + (c.text ? " " + c.text : ""))
							}
							var t = tooltipWeather.today
							if (t && t.temp) {
								parts.push(i18nc("high / low temperature", "%1 / %2", Shared.formatTemp(t.temp.max), Shared.formatTemp(t.temp.min)))
								if (t.precipitation > 0) {
									var imperial = plasmoid.configuration.weatherUnits === 'imperial'
									parts.push(imperial ? i18nc("precipitation in inches", "%1 in", Math.round(t.precipitation * 100) / 100) : i18nc("precipitation in mm", "%1 mm", Math.round(t.precipitation * 10) / 10))
								}
							}
							return parts.join(" · ")
						}
					}
				}

				PlasmaComponents3.Label {
					id: tooltipNowEvent
					readonly property string eventText: typeof upcomingEvents !== "undefined" ? upcomingEvents.tooltipNowText : ""
					visible: !!eventText
					Layout.topMargin: Kirigami.Units.smallSpacing
					Layout.minimumWidth: Math.min(implicitWidth, preferredTextWidth)
					Layout.maximumWidth: preferredTextWidth
					elide: Text.ElideRight
					font.weight: Font.Bold
					text: eventText
				}

				PlasmaComponents3.Label {
					id: tooltipNextEvent
					readonly property string eventText: typeof upcomingEvents !== "undefined" ? upcomingEvents.tooltipNextText : ""
					visible: !!eventText
					Layout.topMargin: tooltipNowEvent.visible ? 0 : Kirigami.Units.smallSpacing
					Layout.minimumWidth: Math.min(implicitWidth, preferredTextWidth)
					Layout.maximumWidth: preferredTextWidth
					elide: Text.ElideRight
					text: eventText
				}
			}
		}

		GridLayout {
			id: timezoneLayout
			Layout.minimumWidth: Math.min(implicitWidth, preferredTextWidth)
			Layout.maximumWidth: preferredTextWidth
			columns: 2
			visible: timezoneRepeater.count > 0

			Repeater {
				id: timezoneRepeater
				model: {
					// The timezones need to be duplicated in the array
					// because we need their data twice - once for the name
					// and once for the time and the Repeater delegate cannot
					// be one Item with two Labels because that wouldn't work
					// in a grid then
					var timezones = []
					var data = dataSource.data
					var localOffset = data["Local"] ? data["Local"]["Offset"] : undefined
					for (var i = 0; i < plasmoid.configuration.selectedTimeZones.length; i++) {
						var timezone = plasmoid.configuration.selectedTimeZones[i]
						// Skip zones with the same offset as local time, eg: Europe/Warsaw when local is Warsaw.
						var sameAsLocal = typeof localOffset !== "undefined" && data[timezone] && data[timezone]["Offset"] === localOffset
						if (timezone != 'Local' && !sameAsLocal) {
							timezones.push(timezone)
							timezones.push(timezone)
						}
					}

					return timezones
				}

				PlasmaComponents3.Label {
					id: timezone
					Layout.alignment: index % 2 === 0 ? Qt.AlignRight : Qt.AlignLeft

					wrapMode: Text.NoWrap
					text: index % 2 == 0 ? nameForZone(modelData) : timeForZone(modelData)
					font.weight: index % 2 == 0 ? Font.Bold : Font.Normal
					elide: Text.ElideNone
					opacity: 0.6
				}
			}
		}
	}
}
