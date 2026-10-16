import QtQuick

// Plays a sound file with the first player that works: PipeWire, PulseAudio, then libcanberra.
// (QtMultimedia isn't used: importing it crashed plasmashell on some distros.)
QtObject {
	id: soundPlayer

	property var executable: ExecUtil {}
	readonly property var players: [
		['pw-play'],
		['paplay'],
		['canberra-gtk-play', '-f'],
	]

	function localPath(file) {
		var path = String(file || '').trim()
		return path.indexOf('file://') === 0 ? decodeURIComponent(path.slice(7)) : path
	}

	function play(file) {
		var path = localPath(file)
		if (path.indexOf('/') !== 0) {
			return
		}
		function tryPlayer(index) {
			if (index >= players.length) {
				console.warn('[eventcalendar] Could not play sound', path)
				return
			}
			executable.execArgv(players[index].concat([path]), function(cmd, exitCode) {
				if (exitCode !== 0) {
					tryPlayer(index + 1)
				}
			})
		}
		tryPlayer(0)
	}
}
