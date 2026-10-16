import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "Shared.js" as Shared

// Weather beside the Today view: now, today's range, next hours, next days.
ColumnLayout {
	id: panel

	property var current: null // { temp, iconName, text }
	property var today: null // daily item
	property var hourly: [] // hourly items, from now
	property var nextDays: [] // daily items after today
	property bool isSetup: true
	property bool compact: false // One row above the grid when the popup is narrow

	spacing: Kirigami.Units.smallSpacing

	function hourText(dt) {
		return Qt.formatTime(new Date(dt * 1000), appletConfig.clock24h ? 'HH' : 'h AP')
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

	// Now
	RowLayout {
		visible: panel.isSetup && !!panel.current
		Layout.fillWidth: true
		spacing: Kirigami.Units.largeSpacing
		Kirigami.Icon {
			source: panel.current ? panel.current.iconName : ""
			Layout.preferredWidth: panel.compact ? Kirigami.Units.iconSizes.medium : Kirigami.Units.iconSizes.huge
			Layout.preferredHeight: Layout.preferredWidth
		}
		ColumnLayout {
			spacing: 0
			Kirigami.Heading {
				level: panel.compact ? 2 : 1
				text: panel.current ? Shared.formatTemp(panel.current.temp) : ""
			}
			PlasmaComponents3.Label {
				text: panel.current ? panel.current.text : ""
				opacity: 0.8
			}
		}
		Item { Layout.fillWidth: panel.compact }
		PlasmaComponents3.Label {
			visible: panel.compact && !!panel.today
			text: panel.today ? Shared.formatTemp(panel.today.temp.max) + ' / ' + Shared.formatTemp(panel.today.temp.min) : ""
			opacity: 0.8
		}
	}

	// Today's range
	PlasmaComponents3.Label {
		visible: panel.isSetup && !panel.compact && !!panel.today
		Layout.fillWidth: true
		wrapMode: Text.Wrap
		text: {
			if (!panel.today) {
				return ""
			}
			var s = i18nc("high / low temperature", "High %1 · Low %2", Shared.formatTemp(panel.today.temp.max), Shared.formatTemp(panel.today.temp.min))
			if (panel.today.precipitation > 0) {
				s += " · " + i18nc("precipitation in mm", "%1 mm", Math.round(panel.today.precipitation * 10) / 10)
			}
			return s
		}
		opacity: 0.8
	}

	// Next hours
	Kirigami.Separator {
		visible: panel.isSetup && !panel.compact && panel.hourly.length > 0
		Layout.fillWidth: true
	}
	GridLayout {
		visible: panel.isSetup && !panel.compact && panel.hourly.length > 0
		Layout.fillWidth: true
		columns: 4
		rowSpacing: Kirigami.Units.smallSpacing
		columnSpacing: Kirigami.Units.smallSpacing
		Repeater {
			model: panel.hourly.slice(0, 12)
			ColumnLayout {
				Layout.fillWidth: true
				spacing: 0
				PlasmaComponents3.Label {
					Layout.alignment: Qt.AlignHCenter
					text: panel.hourText(modelData.dt)
					font: Kirigami.Theme.smallFont
					opacity: 0.7
				}
				Kirigami.Icon {
					Layout.alignment: Qt.AlignHCenter
					source: modelData.iconName
					Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
					Layout.preferredHeight: Layout.preferredWidth
				}
				PlasmaComponents3.Label {
					Layout.alignment: Qt.AlignHCenter
					text: Shared.formatTemp(modelData.temp)
				}
			}
		}
	}

	// Next days
	Kirigami.Separator {
		visible: panel.isSetup && !panel.compact && panel.nextDays.length > 0
		Layout.fillWidth: true
	}
	Repeater {
		model: panel.isSetup && !panel.compact ? panel.nextDays.slice(0, 4) : []
		RowLayout {
			Layout.fillWidth: true
			spacing: Kirigami.Units.smallSpacing
			PlasmaComponents3.Label {
				Layout.preferredWidth: Kirigami.Units.gridUnit * 3
				text: Qt.locale().dayName(new Date(modelData.dt * 1000).getDay(), Locale.ShortFormat)
				font.capitalization: Font.Capitalize
			}
			Kirigami.Icon {
				source: modelData.iconName
				Layout.preferredWidth: Kirigami.Units.iconSizes.small
				Layout.preferredHeight: Layout.preferredWidth
			}
			Item { Layout.fillWidth: true }
			PlasmaComponents3.Label {
				text: Shared.formatTemp(modelData.temp.max)
			}
			PlasmaComponents3.Label {
				text: Shared.formatTemp(modelData.temp.min)
				opacity: 0.6
			}
		}
	}

	Item { Layout.fillHeight: true }
}
