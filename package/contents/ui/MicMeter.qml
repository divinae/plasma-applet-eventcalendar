import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.private.volume

import "lib"

import "CameraPrefs.js" as CameraPrefs

// The camera check's sound (CameraCheckView.qml, loaded by URL only with plasma-pa, see
// PlasmaPaProbe.qml), live like the volume applet's microphone test: the microphone's level while
// running, its sensitivity (input volume), a warning when it's muted, the microphone and speaker to
// use (Plasma's defaults, set as the volume applet sets them) and a speaker test that says its
// channels' names. Nothing is recorded. "Hear yourself" plays the microphone on the speaker live
// (PulseAudio / PipeWire's module-loopback through pactl, tagged so it can be found again), only
// while it's on and the card is shown.
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

	// The tests' errors, shown under the devices (and logged, without any device data).
	property string testError: ""
	function testFailed(what, message) {
		console.warn("[eventcalendar] camera check:", what, "failed:", message)
		testError = message
	}

	onRunningChanged: {
		if (!running) {
			speakerTest.queue = []
			hearSelf = false
		}
	}

	//--- Hear yourself: the microphone on the speaker, live (module-loopback). The command runs in
	// Plasma's executable engine, so switching it off still happens when the card is gone. Each run
	// first unloads the loopbacks it made (also ones left by a crash), then loads one when on.
	property bool hearSelf: false
	readonly property string loopbackTag: "eventcalendar-mic-check"
	readonly property string loopbackScript: 'for m in $(pactl list short modules | awk -v tag="$4" \'index($0, tag) {print $1}\'); do pactl unload-module "$m"; done; '
		+ '[ "$1" = on ] || exit 0; '
		+ 'exec pactl load-module module-loopback source="$2" sink="$3" latency_msec=40 source_dont_move=true sink_dont_move=true sink_input_properties=media.name="$4" source_output_properties=media.name="$4"'
	ExecUtil { id: loopbackExec }
	function updateLoopback() {
		var on = hearSelf && running && !!source && !!PreferredDevice.sink
		loopbackExec.execArgv(['sh', '-c', loopbackScript, 'sh', on ? 'on' : 'off',
			source ? String(source.name) : '', PreferredDevice.sink ? String(PreferredDevice.sink.name) : '', loopbackTag],
			function(cmd, exitCode, exitStatus, stdout, stderr) {
				if (exitCode) {
					meter.hearSelf = false
					meter.testFailed("hear yourself", i18n("Couldn't play the microphone on the speaker (pactl)."))
				}
			})
	}
	onHearSelfChanged: updateLoopback()
	onSourceChanged: if (hearSelf) Qt.callLater(updateLoopback)
	Connections {
		target: PreferredDevice
		function onSinkChanged() {
			if (meter.hearSelf) {
				Qt.callLater(meter.updateLoopback)
			}
		}
	}
	Component.onCompleted: updateLoopback() // Off: clears any left behind
	Component.onDestruction: {
		if (hearSelf) {
			hearSelf = false // Unloads it (the engine finishes the command)
		}
	}

	//--- Speaker test: each channel says its name (left, then right), as in Plasma's audio settings.
	SpeakerTest {
		id: speakerTest
		sink: PreferredDevice.sink
		property var queue: []
		readonly property bool busy: playingChannels.length > 0 || queue.length > 0
		function start() {
			console.log("[eventcalendar] camera check: speaker test, sink:", !!sink, "channels:", sink ? sink.rawChannels.length : 0)
			meter.testError = ""
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
		onShowErrorMessage: function(message) { meter.testFailed("speaker test", message) }
		onPlayingChannelsChanged: {
			if (playingChannels.length === 0) {
				next()
			}
		}
	}

	// Microphone.
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
			icon.name: "audio-headphones-symbolic"
			checkable: true
			checked: meter.hearSelf
			enabled: !!meter.source && !!PreferredDevice.sink
			onToggled: {
				meter.testError = ""
				meter.hearSelf = checked
			}
			PlasmaComponents3.ToolTip.text: i18n("Hear yourself (use headphones: speakers would whistle)")
			PlasmaComponents3.ToolTip.visible: hovered
			PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
		}
	}
	// Under the microphone's list: its level now, and its sensitivity.
	readonly property real level: meter.muted ? 0 : CameraPrefs.meterLevel(monitor.volume)
	TextMetrics {
		id: percentMetrics
		font: Kirigami.Theme.smallFont
		text: i18nc("volume percentage, the widest", "%1%", 100)
	}
	GridLayout {
		Layout.fillWidth: true
		Layout.leftMargin: meter.iconSize + Kirigami.Units.smallSpacing
		columns: 3
		columnSpacing: Kirigami.Units.smallSpacing
		rowSpacing: Kirigami.Units.smallSpacing

		PlasmaComponents3.Label {
			text: i18nc("the microphone's input level now", "Level")
			font: Kirigami.Theme.smallFont
			opacity: 0.75
		}
		Rectangle {
			Layout.fillWidth: true
			implicitHeight: Math.round(Kirigami.Units.smallSpacing * 1.5)
			radius: height / 2
			color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
			Rectangle {
				height: parent.height
				radius: parent.radius
				width: parent.width * meter.level
				color: Kirigami.Theme.positiveTextColor
				Behavior on width {
					NumberAnimation { duration: 80 }
				}
			}
		}
		PlasmaComponents3.Label {
			Layout.preferredWidth: percentMetrics.advanceWidth
			horizontalAlignment: Text.AlignRight
			text: i18nc("volume percentage", "%1%", Math.round(meter.level * 100))
			font: Kirigami.Theme.smallFont
		}

		PlasmaComponents3.Label {
			text: i18nc("the microphone's input volume", "Sensitivity")
			font: Kirigami.Theme.smallFont
			opacity: 0.75
		}
		PlasmaComponents3.Slider {
			id: sensitivity
			Layout.fillWidth: true
			from: PulseAudio.MinimalVolume
			to: PulseAudio.NormalVolume
			stepSize: PulseAudio.NormalVolume / 100
			value: meter.source ? meter.source.volume : PulseAudio.NormalVolume
			enabled: !!meter.source && meter.source.volumeWritable
			onMoved: {
				// As the volume applet: whole percents; 0 is muted.
				var volume = Math.round(value * 100 / PulseAudio.NormalVolume) * PulseAudio.NormalVolume / 100
				meter.source.volume = volume
				meter.source.muted = volume === 0
			}
		}
		PlasmaComponents3.Label {
			Layout.preferredWidth: percentMetrics.advanceWidth
			horizontalAlignment: Text.AlignRight
			text: i18nc("volume percentage", "%1%", Math.round(sensitivity.value / PulseAudio.NormalVolume * 100))
			font: Kirigami.Theme.smallFont
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
	Kirigami.InlineMessage {
		Layout.fillWidth: true
		visible: !!meter.testError
		type: Kirigami.MessageType.Error
		text: meter.testError
	}
}
