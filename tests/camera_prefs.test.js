// The camera check's choices (package/contents/ui/CameraPrefs.js).
const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const read = name => fs.readFileSync(path.join(__dirname, '../package/contents/ui', name), 'utf8')
	.replace(/^\.pragma library\s*$/m, '').replace(/^\.import .*$/mg, '')
const C = {}
vm.runInNewContext(read('CameraPrefs.js'), C)

const cams = [{ description: 'Integrated' }, { description: 'Logitech C920', isDefault: true }, { description: 'Virtual' }]

//--- pickIndex
assert.strictEqual(C.pickIndex(cams, 'Virtual'), 2, 'the saved one')
assert.strictEqual(C.pickIndex(cams, 'Gone'), 1, 'saved one gone: the default')
assert.strictEqual(C.pickIndex(cams, ''), 1, 'nothing saved: the default')
assert.strictEqual(C.pickIndex([{ description: 'A' }, { description: 'B' }], ''), 0, 'no default: the first')
assert.strictEqual(C.pickIndex([], 'A'), -1, 'no devices')
assert.strictEqual(C.pickIndex(null, 'A'), -1, 'no list')

//--- cameraState
assert.strictEqual(C.cameraState(0, false, ''), 'none')
assert.strictEqual(C.cameraState(2, false, 'Device busy'), 'error')
assert.strictEqual(C.cameraState(2, false, ''), 'starting')
assert.strictEqual(C.cameraState(2, true, ''), 'live')

//--- isMicrophone
assert.strictEqual(C.isMicrophone('alsa_input.usb-mic'), true)
assert.strictEqual(C.isMicrophone('alsa_output.pci.analog-stereo.monitor'), false)
assert.strictEqual(C.isMicrophone(''), true)

//--- meterLevel
assert.strictEqual(C.meterLevel(0), 0)
assert.strictEqual(C.meterLevel(-1), 0)
assert.strictEqual(C.meterLevel(0.25), 0.5)
assert.strictEqual(C.meterLevel(4), 1)
assert.strictEqual(C.meterLevel(undefined), 0)

//--- cameraName
assert.strictEqual(C.cameraName('Integrated Camera: Integrated C'), 'Integrated Camera')
assert.strictEqual(C.cameraName('Creative Live! Cam Sync V3: Cre'), 'Creative Live! Cam Sync V3')
assert.strictEqual(C.cameraName('HD Webcam: HD Webcam'), 'HD Webcam')
assert.strictEqual(C.cameraName('Logitech C920'), 'Logitech C920')
assert.strictEqual(C.cameraName('USB Camera: Rear lens'), 'USB Camera: Rear lens', 'a different second part stays')
assert.strictEqual(C.cameraName(''), '')

console.log('camera_prefs: ok')

//--- pickFormatIndex: 720p as Meet asks, not the camera's largest (its zoom crops the sensor)
{
	const live = [
		{ width: 2560, height: 1440, fps: 30, isJpeg: true },
		{ width: 1920, height: 1080, fps: 30, isJpeg: true },
		{ width: 1280, height: 720, fps: 10, isJpeg: false },
		{ width: 1280, height: 720, fps: 30, isJpeg: true },
		{ width: 1600, height: 1200, fps: 30, isJpeg: true },
		{ width: 640, height: 480, fps: 30, isJpeg: false },
	]
	assert.strictEqual(C.pickFormatIndex(live), 3, '1280x720 MJPEG at 30 fps')
	assert.strictEqual(C.pickFormatIndex([{ width: 640, height: 480, fps: 30 }, { width: 1920, height: 1080, fps: 30 }]), 0, 'none 720p: the largest up to 1280 wide')
	assert.strictEqual(C.pickFormatIndex([{ width: 1280, height: 720, fps: 60, isJpeg: false }, { width: 1280, height: 720, fps: 30, isJpeg: true }]), 1, 'up to 30 fps alike: MJPEG')
	assert.strictEqual(C.pickFormatIndex([{ width: 1920, height: 1080 }]), -1, 'only larger: the camera\'s own choice')
	assert.strictEqual(C.pickFormatIndex([]), -1)
	assert.strictEqual(C.pickFormatIndex(null), -1)
}
