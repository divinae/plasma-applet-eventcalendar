import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as Plasma5Support

Item {
	id: timeModel
	property string timezone: "Local"
	property var currentTime: dataSource.data[timezone] ? dataSource.data[timezone]["DateTime"] : new Date() // Engine data arrives after startup.
	property alias dataSource: dataSource
	property var allTimezones: {
		var timezones = plasmoid.configuration.selectedTimeZones.toString()
		if (timezones.length > 0) {
			timezones = timezones.split(',')
		} else {
			timezones = []
		}
		if (timezones.indexOf('Local') === -1) {
			timezones.push('Local')
		}
		return timezones
	}

	// Tick once a minute unless a displayed clock format shows seconds.
	readonly property bool needsSeconds: {
		var formats = appletConfig.line1TimeFormat
		if (plasmoid.configuration.clockShowLine2) {
			formats += appletConfig.line2TimeFormat
		}
		// Drop quoted literals, eg: 'sec'.
		return /s/.test(formats.replace(/'[^']*'/g, ''))
	}

	signal secondChanged()
	signal minuteChanged()
	signal dateChanged()
	signal loaded()

	Plasma5Support.DataSource {
		id: dataSource
		engine: "time"
		connectedSources: timeModel.allTimezones
		interval: timeModel.needsSeconds ? 1000 : 60000
		intervalAlignment: timeModel.needsSeconds ? Plasma5Support.Types.NoAlignment : Plasma5Support.Types.AlignToMinute
		onNewData: function(sourceName, data) {
			if (sourceName === 'Local') {
				timeModel.tick()
			}
		}
	}

	property bool ready: false
	property int lastMinute: -1
	property int lastDate: -1
	function tick() {
		if (!ready) {
			ready = true
			loaded()
		}
		secondChanged()
		var currentMinute = currentTime.getMinutes()
		if (currentMinute != lastMinute) {
			minuteChanged()
			var currentDate = currentTime.getDate()
			if (currentDate != lastDate) {
				dateChanged()
				lastDate = currentDate
			}
			lastMinute = currentMinute
		}
	}


	property bool testing: false
	Component.onCompleted: {
		if (testing) {
			currentTime = new Date(2016, 1, 2, 23, 59, 55)
			timeModel.loaded()
		}
	}

	Timer {
		running: testing
		repeat: true
		interval: 1000
		onTriggered: {
			currentTime.setSeconds(currentTime.getSeconds() + 1)
			timeModel.currentTimeChanged()
			timeModel.tick()
		}
	}
}
