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

console.log('camera_prefs: ok')
