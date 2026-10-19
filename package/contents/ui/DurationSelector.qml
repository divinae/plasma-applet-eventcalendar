import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3

Flow {
	id: durationSelector

	property alias startDateTime: startTimeSelector.dateTime
	property alias endDateTime: endTimeSelector.dateTime

	property bool showTime: false

	spacing: 0

	DateTimeSelector {
		id: startTimeSelector
		enabled: durationSelector.enabled
		showTime: durationSelector.showTime
		dateFirst: true

		onDateTimeShifted: {
			endTimeSelector.dateTime = new Date(endTimeSelector.dateTime.valueOf() + deltaDateTime)
		}
	}
	PlasmaComponents3.Label {
		text: ' ' + i18n("to") + ' '
		font.weight: Font.Bold
		verticalAlignment: Text.AlignVCenter
		height: startTimeSelector.implicitHeight
	}
	DateTimeSelector {
		id: endTimeSelector
		enabled: durationSelector.enabled
		showTime: durationSelector.showTime
		dateFirst: false
	}
}
