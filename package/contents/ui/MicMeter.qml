import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.private.volume

import "CameraPrefs.js" as CameraPrefs

// The camera check's sound (CameraCheckView.qml, loaded by URL only with plasma-pa, see
// PlasmaPaProbe.qml): the microphone's level while running, a warning when it's muted, and the
// microphone and speaker to use (Plasma's defaults, set as the volume applet sets them). Each has
// a test: the microphone records a few seconds and plays them back (kept in memory only, gone
// when the card closes), the speaker says its channels' names.
ColumnLayout {
	id: meter

	property bool running: false
	readonly property var source: PreferredDevice.source
	readonly property bool muted: !!source && source.muted
	spacing: Kirigami.Units.smallSpacing

	readonly property real iconSize: Kirigami.Units.iconSizes.small

	VolumeMonitor {
		id: monitor
		target: meter.running ? meter.source : null
	}

	//--- Microphone test: about 5 s recorded, then played back. Stopped and dropped when the card
	// closes or the popup does.
	readonly property int micTestSeconds: 5
	MicrophoneTest {
		id: micTest
		source: meter.source
		onRecordingFinished: playRecording()
	}
	Timer {
		id: micTestTimer
		interval: meter.micTestSeconds * 1000
		onTriggered: micTest.stopRecording()
	}
	function startMicTest() {
		if (micTest.recording || micTest.playing) {
			stopMicTest()
			return
		}
		micTest.clearRecording()
		micTest.startRecording()
		micTestTimer.restart()
	}
	function stopMicTest() {
		micTestTimer.stop()
		if (micTest.recording) {
			micTest.stopRecording()
		}
		micTest.stopPlaying()
		micTest.clearRecording()
	}
	onRunningChanged: {
		if (!running) {
			stopMicTest()
			speakerTest.queue = []
		}
	}
	Component.onDestruction: {
		micTestTimer.stop()
		micTest.cleanupStreams()
	}

	//--- Speaker test: each channel says its name (left, then right), as in Plasma's audio settings.
	SpeakerTest {
		id: speakerTest
		sink: PreferredDevice.sink
		property var queue: []
		readonly property bool busy: playingChannels.length > 0 || queue.length > 0
		function start() {
			queue = sink ? Array.prototype.slice.call(sink.rawChannels) : []
			next()
		}
		function next() {
			if (!queue.length) {
				return
			}
			var channel = queue[0]
			queue = queue.slice(1)
			testChannel(channel)
		}
		onPlayingChannelsChanged: {
			if (playingChannels.length === 0) {
				next()
			}
		}
	}

	// Microphone, its test and its level.
	RowLayout {
		Layout.fillWidth: true
		spacing: Kirigami.Units.smallSpacing
		Kirigami.Icon {
			implicitWidth: meter.iconSize
			implicitHeight: implicitWidth
			source: meter.muted ? "microphone-sensitivity-muted" : "audio-input-microphone"
		}
		DeviceCombo {
			Layout.fillWidth: true
			pulseModel: SourceModel {}
			microphones: true
		}
		PlasmaComponents3.ToolButton {
			id: micTestButton
			icon.name: micTest.recording || micTest.playing ? "media-playback-stop" : "media-record"
			enabled: !!meter.source && !meter.muted
			onClicked: meter.startMicTest()
			PlasmaComponents3.ToolTip.text: i18n("Test: record %1 seconds and play them back", meter.micTestSeconds)
			PlasmaComponents3.ToolTip.visible: hovered
			PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
		}
	}
	RowLayout {
		Layout.fillWidth: true
		Layout.leftMargin: meter.iconSize + Kirigami.Units.smallSpacing // Under the microphone's list
		Layout.rightMargin: micTestButton.width + Kirigami.Units.smallSpacing
		spacing: Kirigami.Units.smallSpacing
		Rectangle {
			Layout.fillWidth: true
			implicitHeight: Math.round(Kirigami.Units.smallSpacing * 1.5)
			radius: height / 2
			color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
			Rectangle {
				height: parent.height
				radius: parent.radius
				width: parent.width * (meter.muted ? 0 : CameraPrefs.meterLevel(monitor.volume))
				color: micTest.recording ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.positiveTextColor
				Behavior on width {
					NumberAnimation { duration: 80 }
				}
			}
		}
		PlasmaComponents3.Label {
			visible: micTest.recording || micTest.playing
			text: micTest.recording ? i18n("Recording… speak now") : i18n("Playing back…")
			font: Kirigami.Theme.smallFont
			opacity: 0.8
		}
	}
	Kirigami.InlineMessage {
		Layout.fillWidth: true
		visible: meter.muted
		type: Kirigami.MessageType.Warning
		text: i18n("The microphone is muted.")
		actions: [
			Kirigami.Action {
				icon.name: "audio-input-microphone"
				text: i18n("Unmute")
				onTriggered: meter.source.muted = false
			}
		]
	}

	// The devices: [{ text, device, isDefault }] from a PulseAudio model.
	component DeviceCombo: PlasmaComponents3.ComboBox {
		id: combo
		property var pulseModel
		property bool microphones: false
		property var devices: []
		function refresh() {
			var list = []
			for (var i = 0; i < rows.count; i++) {
				var row = rows.objectAt(i)
				if (row && row.device && (!combo.microphones || CameraPrefs.isMicrophone(row.device.name))) {
					list.push({ text: row.label, device: row.device, isDefault: row.isDefault })
				}
			}
			devices = list
		}
		Instantiator {
			id: rows
			model: combo.pulseModel
			delegate: QtObject {
				readonly property string label: model.Description || ""
				readonly property var device: model.PulseObject
				readonly property bool isDefault: !!model.Default
				onIsDefaultChanged: Qt.callLater(combo.refresh)
				onLabelChanged: Qt.callLater(combo.refresh)
			}
			onObjectAdded: Qt.callLater(combo.refresh)
			onObjectRemoved: Qt.callLater(combo.refresh)
		}
		model: devices
		textRole: "text"
		enabled: devices.length > 1
		currentIndex: {
			for (var i = 0; i < devices.length; i++) {
				if (devices[i].isDefault) {
					return i
				}
			}
			return devices.length ? 0 : -1
		}
		onActivated: function(index) {
			devices[index].device.default = true
		}
	}

	RowLayout {
		Layout.fillWidth: true
		spacing: Kirigami.Units.smallSpacing
		Kirigami.Icon {
			implicitWidth: meter.iconSize
			implicitHeight: implicitWidth
			source: "audio-speakers"
		}
		DeviceCombo {
			Layout.fillWidth: true
			pulseModel: SinkModel {}
		}
		PlasmaComponents3.ToolButton {
			icon.name: "media-playback-start"
			enabled: !!speakerTest.sink && !speakerTest.busy
			onClicked: speakerTest.start()
			PlasmaComponents3.ToolTip.text: i18n("Test: play a sound on each side")
			PlasmaComponents3.ToolTip.visible: hovered
			PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
		}
	}
}
