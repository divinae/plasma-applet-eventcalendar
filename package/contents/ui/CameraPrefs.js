.pragma library

// The camera check (CameraCheckView.qml): which camera, microphone and speaker it starts with.

// The device to start with: the one saved (by its description: a camera's id isn't a string in
// QML), else the system default, else the first. devices: [{ description, isDefault }]; -1: none.
function pickIndex(devices, savedDescription) {
	var list = devices || []
	if (!list.length) {
		return -1
	}
	if (savedDescription) {
		for (var i = 0; i < list.length; i++) {
			if (list[i] && list[i].description === savedDescription) {
				return i
			}
		}
	}
	for (var j = 0; j < list.length; j++) {
		if (list[j] && list[j].isDefault) {
			return j
		}
	}
	return 0
}

// The camera's state for the preview: 'none' (no camera), 'error' (busy in another app, no
// permission), 'starting' (until it's running), 'live'.
function cameraState(deviceCount, active, errorText) {
	if (!deviceCount) {
		return 'none'
	}
	if (errorText) {
		return 'error'
	}
	return active ? 'live' : 'starting'
}

// Microphones worth listing: not the "monitor" of a speaker (what it plays, PulseAudio's
// <sink>.monitor sources).
function isMicrophone(name) {
	return !/\.monitor$/.test(String(name || ''))
}

// The level bar: the peak (0..1) from PipeWire made easier to read (quiet speech still moves it).
function meterLevel(peak) {
	var v = Number(peak) || 0
	if (v <= 0) {
		return 0
	}
	return Math.max(0, Math.min(1, Math.sqrt(v)))
}

// A camera's name to show. Linux cuts a camera's name at 31 characters, and many repeat themselves
// after a ": " ("Integrated Camera: Integrated C", "Creative Live! Cam Sync V3: Cre"): the part
// before it when the rest only repeats (the start of) it.
function cameraName(description) {
	var text = String(description || '').trim()
	var at = text.indexOf(': ')
	if (at <= 0) {
		return text
	}
	var name = text.slice(0, at).trim()
	var rest = text.slice(at + 2).trim()
	if (!rest || name.indexOf(rest) === 0 || rest.indexOf(name) === 0) {
		return name
	}
	return text
}

// The camera's format for the check, as video calls ask for it (Google Meet: 720p): the largest
// at most 1280 wide, 16:9 first, then the highest frame rate, compressed (MJPEG: isJpeg) before
// raw. Not the largest the camera has: a camera that zooms in its own firmware (its zoom button,
// eg: Creative Live! Cam) crops its sensor for a smaller picture, and at its full size it has
// nothing to crop, so the zoom did nothing here while it worked in Meet. formats: [{ width,
// height, fps, isJpeg }]; the index of the one to use, -1 for none (the camera's own choice).
function pickFormatIndex(formats) {
	var best = -1
	var bestKey = null
	;(formats || []).forEach(function(f, i) {
		if (!f || !(f.width > 0) || !(f.height > 0) || f.width > 1280) {
			return
		}
		var wide = Math.abs(f.width / f.height - 16 / 9) < 0.02 ? 1 : 0
		var key = [wide, f.width * f.height, Math.min(f.fps || 0, 30), f.isJpeg ? 1 : 0]
		var better = !bestKey
		for (var k = 0; !better && k < key.length; k++) {
			if (key[k] !== bestKey[k]) {
				better = key[k] > bestKey[k]
				break
			}
		}
		if (better) {
			best = i
			bestKey = key
		}
	})
	return best
}
