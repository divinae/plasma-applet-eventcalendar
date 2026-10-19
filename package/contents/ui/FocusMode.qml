import QtQuick

import "lib"
import "MeetingRules.js" as MeetingRules

// Plasma's Do Not Disturb during meetings: plasmanotifyrc [DoNotDisturb] Until, written with
// kwriteconfig6 --notify, which the notification server picks up right away; it ends by itself at
// that time. Only that key is touched. A longer Do Not Disturb isn't shortened, and ending a
// meeting early clears it only if it's still what the widget wrote for that meeting.
QtObject {
	id: focusMode

	property var executable: ExecUtil {}

	// What the widget wrote last (not kept across restarts), and for which meeting.
	property string written: ''
	property string writtenKey: ''

	readonly property var untilArgs: ['--file', 'plasmanotifyrc', '--group', 'DoNotDisturb', '--key', 'Until']

	// One read-then-write at a time, so two meetings can't overwrite each other's check.
	property var queue: []
	property bool busy: false
	function run(operation) {
		queue.push(operation)
		next()
	}
	function next() {
		if (busy || !queue.length) {
			return
		}
		var operation = queue.shift()
		busy = true
		readUntil(function(current) {
			operation(current, function() {
				busy = false
				next()
			})
		})
	}

	function readUntil(callback) {
		executable.execArgv(['kreadconfig6'].concat(untilArgs), function(cmd, exitCode, exitStatus, stdout, stderr) {
			callback(exitCode === 0 ? String(stdout || '').trim() : '')
		})
	}
	function writeUntil(value, callback) {
		executable.execArgv(['kwriteconfig6'].concat(untilArgs, [value, '--notify']), function(cmd, exitCode, exitStatus, stdout, stderr) {
			if (exitCode !== 0) {
				logger.log('do not disturb: could not write', exitCode, stderr)
			}
			callback(exitCode === 0)
		})
	}

	// Do Not Disturb until end (the meeting with this key), unless it's on until then or later.
	function startUntil(end, key, now) {
		run(function(current, done) {
			var value = MeetingRules.untilToWrite(current, end, now)
			if (!value) {
				logger.log('do not disturb: already on until', current)
				done()
				return
			}
			writeUntil(value, function(ok) {
				if (ok) {
					focusMode.written = value
					focusMode.writtenKey = key
					logger.log('do not disturb: on until', value)
				}
				done()
			})
		})
	}

	// The meeting with this key ended early: Do Not Disturb off now, if it's still the widget's.
	function endIfOwn(key, now) {
		run(function(current, done) {
			if (!key || key !== focusMode.writtenKey || !MeetingRules.isOwnUntil(current, focusMode.written)) {
				done()
				return
			}
			writeUntil(MeetingRules.formatUntil(now), function(ok) {
				if (ok) {
					focusMode.written = ''
					focusMode.writtenKey = ''
					logger.log('do not disturb: off, meeting ended')
				}
				done()
			})
		})
	}
}
