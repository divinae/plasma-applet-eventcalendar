import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "Shared.js" as Shared

// Weather beside the Today view, in labeled sections: Now, Next hours, Next days.
ColumnLayout {
	id: panel

	property var current: null // { temp, iconName, text }
	property var today: null // daily item
	property var hourly: [] // hourly items, from now
	property var nextDays: [] // daily items after today
	property bool isSetup: true
	property string locationName: ""
	property bool compact: false // One row above the grid when the popup is narrow

	spacing: Kirigami.Units.smallSpacing

	function timeText(dt) {
		return Qt.formatTime(new Date(dt * 1000), appletConfig.clock24h ? 'HH:mm' : 'h AP')
	}
	function precipitationText(mm) {
		return mm > 0 ? i18nc("precipitation in mm", "%1 mm", Math.round(mm * 10) / 10) : ""
	}

	component SectionTitle: PlasmaComponents3.Label {
		Layout.fillWidth: true
		Layout.topMargin: Kirigami.Units.largeSpacing
		font.weight: Font.DemiBold
		opacity: 0.7
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

	// Location
	PlasmaComponents3.Label {
		visible: panel.isSetup && !panel.compact && !!panel.locationName
		Layout.fillWidth: true
		elide: Text.ElideRight
		text: panel.locationName
		font.weight: Font.Bold
	}

	//--- Now
	SectionTitle {
		visible: panel.isSetup && !panel.compact && !!panel.current
		Layout.topMargin: 0
		text: i18nc("current weather", "Now")
	}
	RowLayout {
		visible: panel.isSetup && !!panel.current
		Layout.fillWidth: true
		spacing: Kirigami.Units.largeSpacing
		Kirigami.Icon {
			source: panel.current ? panel.current.iconName : ""
			Layout.preferredWidth: panel.compact ? Kirigami.Units.iconSizes.medium : Kirigami.Units.iconSizes.large
			Layout.preferredHeight: Layout.preferredWidth
		}
		ColumnLayout {
			Layout.fillWidth: true
			spacing: 0
			Kirigami.Heading {
				level: 2
				text: panel.current ? Shared.formatTemp(panel.current.temp) : ""
			}
			PlasmaComponents3.Label {
				Layout.fillWidth: true
				elide: Text.ElideRight
				text: panel.current ? panel.current.text : ""
				opacity: 0.8
			}
		}
		// Compact: today's range on the same row
		PlasmaComponents3.Label {
			visible: panel.compact && !!panel.today
			text: panel.today ? i18nc("high / low temperature", "High %1 · Low %2", Shared.formatTemp(panel.today.temp.max), Shared.formatTemp(panel.today.temp.min)) : ""
			opacity: 0.8
		}
	}
	PlasmaComponents3.Label {
		visible: panel.isSetup && !panel.compact && !!panel.today
		Layout.fillWidth: true
		wrapMode: Text.Wrap
		text: {
			if (!panel.today) {
				return ""
			}
			var s = i18nc("today's high / low temperature", "Today: high %1, low %2", Shared.formatTemp(panel.today.temp.max), Shared.formatTemp(panel.today.temp.min))
			var rain = panel.precipitationText(panel.today.precipitation)
			return rain ? s + ", " + i18nc("precipitation", "rain %1", rain) : s
		}
		opacity: 0.8
	}

	//--- Next hours: time, icon, temperature, precipitation
	SectionTitle {
		visible: panel.isSetup && !panel.compact && panel.hourly.length > 1
		text: i18n("Next hours")
	}
	Repeater {
		model: panel.isSetup && !panel.compact ? panel.hourly.slice(1, 7) : []
		RowLayout {
			Layout.fillWidth: true
			spacing: Kirigami.Units.smallSpacing
			PlasmaComponents3.Label {
				Layout.preferredWidth: Kirigami.Units.gridUnit * 3
				text: panel.timeText(modelData.dt)
				opacity: 0.7
			}
			Kirigami.Icon {
				source: modelData.iconName
				Layout.preferredWidth: Kirigami.Units.iconSizes.small
				Layout.preferredHeight: Layout.preferredWidth
			}
			PlasmaComponents3.Label {
				Layout.preferredWidth: Kirigami.Units.gridUnit * 2
				horizontalAlignment: Text.AlignRight
				text: Shared.formatTemp(modelData.temp)
			}
			PlasmaComponents3.Label {
				Layout.fillWidth: true
				horizontalAlignment: Text.AlignRight
				text: panel.precipitationText(modelData.precipitation)
				font: Kirigami.Theme.smallFont
				opacity: 0.7
			}
		}
	}

	//--- Next days: day, icon, high / low
	SectionTitle {
		visible: panel.isSetup && !panel.compact && panel.nextDays.length > 0
		text: i18n("Next days")
	}
	Repeater {
		model: panel.isSetup && !panel.compact ? panel.nextDays.slice(0, 4) : []
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
				source: modelData.iconName
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
