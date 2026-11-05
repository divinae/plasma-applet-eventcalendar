import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as Plasma5Support

Item {
	id: timeModel
	property string timezone: "Local"
	// Set by the time engine each minute, or with seconds shown by secondTimer (updateCurrentTime).
	property var currentTime: new Date()
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

	signal minuteChanged()
	signal dateChanged()
	signal loaded()

	// Each minute (on the minute): the current time without seconds shown, and the tooltip's other
	// time zones (no seconds there).
	Plasma5Support.DataSource {
		id: dataSource
		engine: "time"
		connectedSources: timeModel.allTimezones
		interval: 60000
		intervalAlignment: Plasma5Support.Types.AlignToMinute
		onNewData: function(sourceName, data) {
			if (sourceName === 'Local' && !timeModel.needsSeconds && !timeModel.testing) {
				timeModel.currentTime = new Date()
				timeModel.tick()
			}
		}
	}

	// Seconds shown: each tick aimed at the start of the next second, so the seconds change with the
	// system clock (a fixed 1000 ms poll kept the phase it started with: up to a second late). Qt's
	// coarse timers can fire a little early, just before the boundary: then it only aims again.
	// From ALikesToCode's fork (their commits 18b9570b, f7368445).
	// Started and stopped here only (restart() re-aims it): not a running binding, which restart breaks.
	Timer {
		id: secondTimer
		repeat: true
		interval: 1000
		onTriggered: timeModel.updateCurrentTime()
	}
	function followSeconds() {
		if (needsSeconds && !testing) {
			updateCurrentTime() // Now, and aimed at the next second
		} else {
			secondTimer.stop()
			if (!testing) {
				currentTime = new Date() // The engine's next update is up to a minute away
				tick()
			}
		}
	}
	onNeedsSecondsChanged: followSeconds()
	function updateCurrentTime() {
		var now = new Date()
		// Restarted: a new interval on a running timer counts only from its next start
		secondTimer.interval = Math.max(5, 1000 - now.getMilliseconds())
		secondTimer.restart()
		if (ready && Math.floor(now.getTime() / 1000) === Math.floor(currentTime.getTime() / 1000)) {
			return
		}
		currentTime = now
		tick()
	}


	property bool ready: false
	property int lastMinute: -1
	property int lastDate: -1
	function tick() {
		if (!ready) {
			ready = true
			loaded()
		}
		var currentMinute = currentTime.getMinutes()
		if (currentMinute !== lastMinute) {
			minuteChanged()
			var currentDate = currentTime.getDate()
			if (currentDate !== lastDate) {
				dateChanged()
				lastDate = currentDate
			}
			lastMinute = currentMinute
		}
	}


	property bool testing: false
	Component.onCompleted: {
		if (needsSeconds && !testing) {
			updateCurrentTime()
		}
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
