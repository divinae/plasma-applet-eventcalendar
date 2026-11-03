import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "Shared.js" as Shared
import "Moon.js" as Moon

// The Day view's moon (Moon.dayInfo, worked out here): the shown day's phase as the Weather Icons
// moon, how much of it is lit, when it rises and sets at the weather's place (when there is one),
// and the next full or new moon.
RowLayout {
	id: panel

	property date day: new Date()
	property real latitude: NaN // The weather's place; NaN: no rise and set
	property real longitude: NaN

	readonly property var info: Moon.dayInfo(day, latitude, longitude)
	readonly property real dimOpacity: appletConfig.darkTheme ? 0.75 : 0.9

	spacing: Kirigami.Units.largeSpacing

	function phaseName(key) {
		switch (key) {
		case 'new': return i18nc("moon phase", "New moon")
		case 'waxingCrescent': return i18nc("moon phase", "Waxing crescent")
		case 'firstQuarter': return i18nc("moon phase", "First quarter")
		case 'waxingGibbous': return i18nc("moon phase", "Waxing gibbous")
		case 'full': return i18nc("moon phase", "Full moon")
		case 'waningGibbous': return i18nc("moon phase", "Waning gibbous")
		case 'lastQuarter': return i18nc("moon phase", "Last quarter")
		default: return i18nc("moon phase", "Waning crescent")
		}
	}
	function timeText(date) {
		return Shared.formatTime(date, appletConfig.clock24h ? 'HH:mm' : 'h:mm AP')
	}
	readonly property string riseSetText: {
		var rs = info.riseSet
		if (!rs) {
			return ""
		} else if (rs.alwaysUp) {
			return i18nc("the moon", "Up all day")
		} else if (rs.alwaysDown) {
			return i18nc("the moon", "Down all day")
		} else if (rs.rise && rs.set) {
			return rs.rise < rs.set
				? i18nc("the moon, %1 and %2 = times", "Rises %1, sets %2", timeText(rs.rise), timeText(rs.set))
				: i18nc("the moon, %1 and %2 = times", "Sets %1, rises %2", timeText(rs.set), timeText(rs.rise))
		}
		return rs.rise ? i18nc("the moon, %1 = time", "Rises %1", timeText(rs.rise))
			: i18nc("the moon, %1 = time", "Sets %1", timeText(rs.set))
	}
	readonly property string nextText: {
		var next = info.next
		if (!next) {
			return ""
		}
		var date = Qt.locale().toString(next.at, "ddd d MMM")
		return next.key === 'full' ? i18nc("%1 = date", "Full moon %1", date) : i18nc("%1 = date", "New moon %1", date)
	}

	FontIcon {
		Layout.alignment: Qt.AlignTop
		Layout.preferredWidth: Kirigami.Units.iconSizes.large
		Layout.preferredHeight: Kirigami.Units.iconSizes.large
		source: "moon-" + panel.info.glyph
		showOutline: false
	}

	ColumnLayout {
		Layout.fillWidth: true
		spacing: 0

		PlasmaComponents3.Label {
			Layout.fillWidth: true
			elide: Text.ElideRight
			textFormat: Text.PlainText
			font.weight: Font.DemiBold
			text: panel.info.mainAt
				? i18nc("moon phase %1 at time %2", "%1 at %2", panel.phaseName(panel.info.phaseKey), panel.timeText(panel.info.mainAt))
				: panel.phaseName(panel.info.phaseKey)
		}
		PlasmaComponents3.Label {
			Layout.fillWidth: true
			elide: Text.ElideRight
			textFormat: Text.PlainText
			opacity: panel.dimOpacity
			text: i18nc("the moon, %1 = percent", "%1% lit", Math.round(panel.info.fraction * 100))
		}
		PlasmaComponents3.Label {
			Layout.fillWidth: true
			visible: !!panel.riseSetText
			elide: Text.ElideRight
			textFormat: Text.PlainText
			opacity: panel.dimOpacity
			text: panel.riseSetText
		}
		PlasmaComponents3.Label {
			Layout.fillWidth: true
			visible: !!panel.nextText
			elide: Text.ElideRight
			textFormat: Text.PlainText
			opacity: panel.dimOpacity
			text: panel.nextText
		}
	}
}
