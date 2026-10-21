import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore

import "lib"
import "lib/ColorUtil.js" as ColorUtil
import "Shared.js" as Shared

QtObject {
	id: config

	// Shared look for the month and week views.
	readonly property real faintGridLineOpacity: 0.07 // Day and hour grid lines: always on, very faint
	readonly property real pastOpacity: 0.6 // Past days / ended events are dimmed in all views
	// Dark theme: event colors keep their hue and saturation but get darker (like Google Calendar's
	// dark mode), so bright pastel tiles don't glare and keep light text.
	readonly property bool darkTheme: {
		var c = Kirigami.Theme.backgroundColor
		return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b < 0.5
	}
	// Settings > Views > Google event colors = "Follow the system color scheme": event colors become
	// the nearest (by hue) accent color of the Plasma color scheme; greys stay grey.
	readonly property bool systemEventPalette: plasmoid.configuration.googleColorPalette === 'system'
	readonly property var systemPalette: [
		Kirigami.Theme.negativeTextColor, // red
		Kirigami.Theme.neutralTextColor, // orange / yellow
		Kirigami.Theme.positiveTextColor, // green
		Kirigami.Theme.linkColor, // blue
		Kirigami.Theme.highlightColor, // accent
		Kirigami.Theme.visitedLinkColor, // purple
	]
	function systemColorFor(color) {
		if (color.hslSaturation < 0.15) {
			return Kirigami.Theme.disabledTextColor // Grey calendars
		}
		var best = systemPalette[0]
		var bestDistance = 2
		for (var i = 0; i < systemPalette.length; i++) {
			var candidate = Qt.color(systemPalette[i])
			if (candidate.hslSaturation < 0.15) {
				continue
			}
			var d = Math.abs(candidate.hslHue - color.hslHue)
			d = Math.min(d, 1 - d) // Hue is a circle
			if (d < bestDistance) {
				bestDistance = d
				best = candidate
			}
		}
		return best
	}
	function eventColor(c) {
		var color = Qt.color(c || Kirigami.Theme.highlightColor)
		if (systemEventPalette) {
			return systemColorFor(color) // Already made for the color scheme: no darkening
		}
		if (!darkTheme) {
			return color
		}
		// Similar lightness for all colors (about 0.36..0.48), a little of the original difference kept.
		var lightness = 0.42 + (color.hslLightness - 0.5) * 0.15
		return Qt.hsla(Math.max(0, color.hslHue), color.hslSaturation, lightness, 1)
	}
	// Event text in the month, week, day and agenda views: the theme font, scaled by a setting.
	readonly property real eventFontScale: Math.max(50, Math.min(200, plasmoid.configuration.eventFontScale || 100)) / 100
	readonly property font eventFont: scaledFont(Kirigami.Theme.defaultFont, eventFontScale)
	// The theme's small font; some setups report one that isn't smaller than the default.
	readonly property font eventSmallFont: fontPoints(Kirigami.Theme.smallFont) < fontPoints(Kirigami.Theme.defaultFont)
		? scaledFont(Kirigami.Theme.smallFont, eventFontScale)
		: scaledFont(Kirigami.Theme.defaultFont, eventFontScale * 0.85)
	// Always in points (views set font.pointSize from it); a theme font set in pixels has
	// pointSize -1, so it's converted (96 dpi: 1 px = 0.75 pt).
	function fontPoints(base) {
		return base.pointSize > 0 ? base.pointSize : base.pixelSize * 0.75
	}
	function scaledFont(base, scale) {
		return Qt.font({
			family: base.family,
			styleName: base.styleName,
			weight: base.weight,
			italic: base.italic,
			letterSpacing: base.letterSpacing,
			wordSpacing: base.wordSpacing,
			pointSize: Math.max(1, fontPoints(base) * scale),
		})
	}
	readonly property color eventBorderColor: ColorUtil.setAlpha(Kirigami.Theme.textColor, 0.2)
	// Invitations not answered yes (Shared.myResponse), like Google Calendar: an outline in the event
	// color on the background instead of a filled tile; maybe adds stripes, declined is struck through.
	// Settings > Views > Event look = "All-day filled, timed light with a color bar": timed events
	// are a light tint of their color (opaque, theme text) with a bar in the full color.
	readonly property bool barEventLook: plasmoid.configuration.eventLook === 'bar'
	// The bar's color: the event color, but pale ones (light greys, pastels) darker in a light theme,
	// so the bar, the tint and the outline stand out from the background.
	function eventBarColor(color) {
		var c = Qt.color(color)
		if (darkTheme || c.hslLightness <= 0.55) {
			return c
		}
		return Qt.hsla(Math.max(0, c.hslHue), c.hslSaturation, 0.55, 1)
	}
	// Text in the event's color (bar look, not yet answered, like Google Calendar): dark enough to
	// read on the background, or light enough in a dark theme.
	function eventColoredTextColor(color) {
		var c = Qt.color(color)
		var lightness = darkTheme ? Math.max(c.hslLightness, 0.72) : Math.min(c.hslLightness, 0.4)
		return Qt.hsla(Math.max(0, c.hslHue), c.hslSaturation, lightness, 1)
	}
	function eventTintColor(color) {
		return Qt.tint(Kirigami.Theme.backgroundColor, ColorUtil.setAlpha(color, darkTheme ? 0.38 : 0.3))
	}
	// Its outline: between the tint and the full color, so pale colors (eg: banana, graphite) still
	// stand out from the background and from tinted cells (today, weekends).
	function eventTintOutlineColor(color) {
		return Qt.tint(Kirigami.Theme.backgroundColor, ColorUtil.setAlpha(color, 0.6))
	}
	function eventFillColor(color, response) {
		return Shared.isUnconfirmedResponse(response) ? Kirigami.Theme.backgroundColor : color
	}
	function eventTextColor(color, response) {
		return Shared.isUnconfirmedResponse(response) ? Kirigami.Theme.textColor : Shared.contrastTextColor(color)
	}
	function eventOutlineColor(color, response) {
		if (response === 'declined') {
			return ColorUtil.setAlpha(color, 0.5)
		}
		return Shared.isUnconfirmedResponse(response) ? color : eventBorderColor
	}

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
	readonly property color meteogramPositiveTempColor: "#900"
	readonly property color meteogramNegativeTempColor: "#369"
	readonly property color meteogramIconColor: Kirigami.Theme.textColor

	property color agendaHoverBackground: alternateBackgroundColor
	readonly property color agendaInProgressColor: Kirigami.Theme.highlightColor

	readonly property int agendaDaySpacing: 20 * Screen.devicePixelRatio
	readonly property int agendaEventSpacing: 10 * Screen.devicePixelRatio
	property int eventIndicatorWidth: 2 * Screen.devicePixelRatio

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
	readonly property string timeFormat: clock24h ? 'HH:mm' : 'h:mm AP' // Times in the views: 09:45 / 9:45 AM
	readonly property bool clock24h: {
		var is12hour = combinedFormat.toLowerCase().indexOf('ap') >= 0
		return !is12hour
	}
}
