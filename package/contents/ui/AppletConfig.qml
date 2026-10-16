import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore

import "lib"
import "lib/ColorUtil.js" as ColorUtil

QtObject {
	id: config

	readonly property bool showIconOutline: false

	// Shared look for the month and week views.
	readonly property real faintGridLineOpacity: 0.07 // Day and hour grid lines: always on, very faint
	readonly property real pastOpacity: 0.45 // Past days / ended events are dimmed in all views
	readonly property color eventBorderColor: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.2)

	property color alternateBackgroundColor: {
		var textColor = Kirigami.Theme.textColor
		var bgColor = Kirigami.Theme.buttonBackgroundColor
		if (ColorUtil.hasEnoughContrast(textColor, bgColor)) {
			return bgColor
		} else {
			// 10% of Text color should be a large enough contrast
			return ColorUtil.setAlpha(textColor, 0.1)
		}
	}

	// Meteogram
	readonly property color meteogramTextColor: Kirigami.Theme.textColor
	readonly property color meteogramScaleColor: ColorUtil.lerp(Kirigami.Theme.backgroundColor, Kirigami.Theme.textColor, 0.9)
	readonly property color meteogramPrecipitationRawColor: "#acd"
	property color meteogramPrecipitationColor: ColorUtil.setAlpha(meteogramPrecipitationRawColor, 0.6)
	property color meteogramPrecipitationTextColor: Qt.tint(meteogramTextColor, ColorUtil.setAlpha(meteogramPrecipitationRawColor, 0.3))
	property color meteogramPrecipitationTextOutlineColor: showIconOutline ? Kirigami.Theme.backgroundColor : "transparent"
	readonly property color meteogramPositiveTempColor: "#900"
	readonly property color meteogramNegativeTempColor: "#369"
	readonly property color meteogramIconColor: Kirigami.Theme.textColor

	property color agendaHoverBackground: alternateBackgroundColor
	readonly property color agendaInProgressColor: Kirigami.Theme.highlightColor

	readonly property int agendaDaySpacing: 20 * Screen.devicePixelRatio
	readonly property int agendaEventSpacing: 10 * Screen.devicePixelRatio
	property int eventIndicatorWidth: 2 * Screen.devicePixelRatio

	readonly property int agendaFontSize: Kirigami.Theme.defaultFont.pixelSize

	property int timerClockFontHeight: 40 * Screen.devicePixelRatio
	property int timerButtonWidth: 48 * Screen.devicePixelRatio

	property int meteogramIconSize: 24 * Screen.devicePixelRatio
	property int meteogramColumnWidth: 32 * Screen.devicePixelRatio // weatherIconSize = 32px (height = 24px but most icons are landscape)

	property QtObject icalCalendarList: Base64Json {
		configKey: 'icalCalendarList'
	}

	readonly property string clockFontFamily: plasmoid.configuration.clockFontFamily || Kirigami.Theme.defaultFont.family

	readonly property int lineWeight1: plasmoid.configuration.clockLineBold1 ? Font.Bold : Font.Normal
	readonly property int lineWeight2: plasmoid.configuration.clockLineBold2 ? Font.Bold : Font.Normal

	readonly property string localeTimeFormat: Qt.locale().timeFormat(Locale.ShortFormat)
	readonly property string localeDateFormat: Qt.locale().dateFormat(Locale.ShortFormat)
	readonly property string line1TimeFormat: plasmoid.configuration.clockTimeFormat1 || localeTimeFormat
	readonly property string line2TimeFormat: plasmoid.configuration.clockTimeFormat2 || localeDateFormat
	readonly property string combinedFormat: {
		if (plasmoid.configuration.clockShowLine2) {
			return line1TimeFormat + '\n' + line2TimeFormat
		} else {
			return line1TimeFormat
		}
	}
	readonly property bool clock24h: {
		var is12hour = combinedFormat.toLowerCase().indexOf('ap') >= 0
		return !is12hour
	}
}
