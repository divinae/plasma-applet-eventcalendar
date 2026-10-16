import QtQuick
import QtCore
import org.kde.notification

import "./lib"

// Desktop notifications through KNotification: no helper process, actions handled in QML.
//
// notify({ summary, body, appName, appIcon, event, urgency, expireTimeout, soundFile, actions }, callback)
// - event: notifyrc event id (reminder, eventStarting, eventChanged, timer, syncProblem); each can be
//   configured in System Settings > Notifications > Event Calendar.
// - expireTimeout: ms; 0 = keep until dismissed, > 0 = close after that long, -1 / unset = server default.
// - urgency: 'low' | 'normal' | 'critical'.
// - actions: ["id,Label", ...].
// callback(actionId) once: an action id, 'default' (the notification was clicked) or 'closed'.
QtObject {
	id: notificationManager

	property var executable: ExecUtil {}

	// Our notifyrc is copied to ~/.local/share/knotifications6 (a plasmoid package can't install it).
	// KNotification sends nothing for a component it can't resolve, so until it's there the generic
	// workspace event is used, with the app name in the title.
	property bool ownComponent: false
	readonly property string notifyrcSource: localFilePath(Qt.resolvedUrl("../knotifications/eventcalendar.notifyrc"))
	readonly property string notifyrcTarget: localFilePath(StandardPaths.writableLocation(StandardPaths.GenericDataLocation)) + "/knotifications6/eventcalendar.notifyrc"

	function localFilePath(url) {
		var path = String(url)
		return path.indexOf("file://") === 0 ? decodeURIComponent(path.slice(7)) : path
	}

	Component.onCompleted: {
		executable.execArgv(['install', '-D', '-m', '644', notifyrcSource, notifyrcTarget], function(cmd, exitCode, exitStatus, stdout, stderr) {
			if (exitCode === 0) {
				notificationManager.ownComponent = true
			} else {
				logger.log('Could not install eventcalendar.notifyrc:', exitCode, stderr)
			}
		})
	}

	property Component notificationComponent: Component {
		Notification {
			autoDelete: false // Destroyed after "closed", once the callback ran
		}
	}
	property Component actionComponent: Component {
		NotificationAction {}
	}
	property Component closeTimerComponent: Component {
		Timer {
			running: true
		}
	}

	function urgencyFor(name) {
		switch (name) {
			case 'low': return Notification.LowUrgency
			case 'critical': return Notification.CriticalUrgency
			case 'normal': return Notification.NormalUrgency
			default: return Notification.DefaultUrgency
		}
	}

	function notify(args, callback) {
		logger.debugJSON('NotificationManager.notify', args.event, args.summary)
		var answered = false
		function answer(actionId) {
			if (answered) {
				return
			}
			answered = true
			if (typeof callback === 'function') {
				callback(actionId)
			}
		}

		var title = args.summary || ""
		if (!ownComponent && args.appName) {
			title = args.appName + " · " + title // Shown under "System Notifications" otherwise
		}
		var flags = args.expireTimeout === 0 ? Notification.Persistent : Notification.CloseOnTimeout
		var n = notificationComponent.createObject(notificationManager, {
			componentName: ownComponent ? "eventcalendar" : "plasma_workspace",
			eventId: ownComponent ? (args.event || "eventChanged") : "notification",
			title: title,
			text: args.body || "",
			iconName: args.appIcon || "view-calendar",
			urgency: urgencyFor(args.urgency),
			flags: flags,
		})

		var actions = []
		var list = args.actions || []
		for (var i = 0; i < list.length; i++) {
			var parts = String(list[i]).split(',')
			var actionId = parts.shift()
			var action = actionComponent.createObject(n, { label: parts.join(',') })
			action.activated.connect(answer.bind(null, actionId))
			actions.push(action)
		}
		n.actions = actions
		var defaultAction = actionComponent.createObject(n, { label: "" })
		defaultAction.activated.connect(answer.bind(null, 'default'))
		n.defaultAction = defaultAction

		// "closed" also follows an action: answer() only reports the first.
		n.closed.connect(function() {
			answer('closed')
			Qt.callLater(function() { n.destroy() })
		})
		if (args.expireTimeout > 0) {
			var closeTimer = closeTimerComponent.createObject(n, { interval: args.expireTimeout })
			closeTimer.triggered.connect(function() { n.close() })
		}

		var sound = args.sound || args.soundFile
		if (sound) {
			playSound(sound)
		}
		n.sendEvent()
	}

	// The notification's own sound is set per event in System Settings; this plays the file picked
	// in the widget's settings.
	property var soundPlayer: SoundPlayer {}
	function playSound(file) {
		soundPlayer.play(file)
	}
}
