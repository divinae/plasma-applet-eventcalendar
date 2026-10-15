import QtQuick

import "./lib"

QtObject {
	id: notificationManager

	property var executable: ExecUtil { id: executable }

	function localFilePath(url) {
		var path = String(url)
		return path.indexOf("file://") === 0 ? path.slice(7) : path
	}

	function notifyWithNotifySend(args, callback) {
		var cmd = ['notify-send']
		if (args.appName) {
			cmd.push('-a', args.appName)
		}
		if (args.appIcon) {
			cmd.push('-i', args.appIcon)
		}
		if (typeof args.expireTimeout !== 'undefined') {
			cmd.push('-t', args.expireTimeout)
		}
		if (args.urgency) {
			cmd.push('-u', args.urgency)
		}
		var sanitizedSummary = executable.sanitizeString(args.summary)
		var sanitizedBody = executable.sanitizeString(args.body)
		cmd.push(sanitizedSummary)
		cmd.push(sanitizedBody)
		executable.exec(cmd, function(cmd, exitCode, exitStatus, stdout, stderr) {
			if (exitCode !== 0) {
				logger.log('notify-send failed', exitCode, stderr)
			}
			if (typeof callback === 'function') {
				callback('')
			}
		})
	}

	function notify(args, callback) {
		logger.debugJSON('NotificationMananger.notify', args)
		args.sound = args.sound || args.soundFile

		var cmd = [
			'python3',
			localFilePath(Qt.resolvedUrl("../scripts/notification.py")),
		]
		if (args.appName) {
			cmd.push('--app-name', args.appName)
		}
		if (args.appIcon) {
			cmd.push('--icon', args.appIcon)
		}
		if (args.sound) {
			cmd.push('--sound', args.sound)
			if (args.loop) {
				cmd.push('--loop', args.loop)
			}
		}
		if (typeof args.expireTimeout !== 'undefined') {
			cmd.push('--timeout', args.expireTimeout)
		}
		if (args.urgency) {
			cmd.push('--urgency', args.urgency)
		}
		if (args.actions) {
			for (var i = 0; i < args.actions.length; i++) {
				var action = args.actions[i]
				cmd.push('--action', action)
			}
		}
		cmd.push('--metadata', '' + Date.now())
		var sanitizedSummary = executable.sanitizeString(args.summary)
		var sanitizedBody = executable.sanitizeString(args.body)
		cmd.push(sanitizedSummary)
		cmd.push(sanitizedBody)
		executable.exec(cmd, function(cmd, exitCode, exitStatus, stdout, stderr) {
			if (exitCode !== 0) {
				logger.log('notification.py failed, falling back to notify-send', exitCode, stderr)
				notifyWithNotifySend(args, callback)
				return
			}
			// First line only: the script reports one action, but be safe if it prints more.
			var actionId = String(stdout || '').split('\n')[0].trim()
			if (typeof callback === 'function') {
				callback(actionId)
			}
		})
	}
}
