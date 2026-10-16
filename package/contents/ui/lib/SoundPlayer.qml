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

	// file:// URL or path -> path
	function localPath(file) {
		var path = String(file || '').trim()
		return path.indexOf('file://') === 0 ? decodeURIComponent(path.slice(7)) : path
	}
	// An absolute path to a sound file type the players handle.
	function isPlayable(file) {
		var path = localPath(file)
		return path.indexOf('/') === 0 && /\.(wav|mp3|oga|ogg|flac)$/i.test(path)
	}

	property int playCount: 0
	function play(file) {
		var path = localPath(file)
		if (!isPlayable(path)) {
			console.warn('[eventcalendar] Not a playable sound file:', path)
			return
		}
		// ExecUtil tracks commands by their text: a unique env var keeps two plays of the same file
		// (eg: two reminders at once) apart.
		var id = 'EVENTCALENDAR_SOUND=' + (++playCount) + '-' + Date.now()
		function tryPlayer(index) {
			if (index >= players.length) {
				console.warn('[eventcalendar] Could not play sound (install pipewire, pulseaudio-utils or libcanberra-gtk3):', path)
				return
			}
			executable.execArgv(['env', id].concat(players[index], [path]), function(cmd, exitCode) {
				if (exitCode !== 0) {
					tryPlayer(index + 1)
				}
			})
		}
		tryPlayer(0)
	}
}
