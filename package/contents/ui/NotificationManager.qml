import QtQuick
import QtCore

import "./lib"
import "./NotificationState.js" as NotificationState

// Desktop notifications through KNotification (KNotificationBackend.qml): no helper process,
// actions handled in QML.
//
// notify({ summary, body, appName, appIcon, event, urgency, expireTimeout, soundFile, actions }, callback)
// - event: notifyrc event id (reminder, eventStarting, invitation, dailyAgenda, taskReminder, timer, syncProblem); each can be
//   configured in System Settings > Notifications > Event Calendar.
// - expireTimeout: 0 = keep until dismissed; > 0 = closed after that many ms; else (-1) Plasma's
//   popup timeout.
// - urgency: 'low' | 'normal' | 'critical'.
// - actions: ["id,Label", ...].
// callback(actionId) once: an action id, 'default' (the notification was clicked) or 'closed'.
QtObject {
	id: notificationManager

	property var executable: ExecUtil {}
	property var soundPlayer: SoundPlayer {}

	property var backend: null
	Component.onCompleted: {
		var component = Qt.createComponent("KNotificationBackend.qml")
		if (component.status === Component.Ready) {
			backend = component.createObject(notificationManager)
		} else {
			console.warn('[eventcalendar] Notifications disabled: the KNotifications QML module (org.kde.notification) is missing.', component.errorString())
		}
		installNotifyrc()
	}

	// Our notifyrc is copied to ~/.local/share/knotifications6 (a plasmoid package can't install it),
	// once per plasmashell start and only written when it changed. KNotification sends nothing for
	// a component it can't resolve, so until then the generic workspace event is used, with the app
	// name in the title.
	property bool ownComponent: NotificationState.notifyrcInstalled
	readonly property string notifyrcSource: soundPlayer.localPath(Qt.resolvedUrl("../knotifications/eventcalendar.notifyrc"))
	readonly property string notifyrcTarget: soundPlayer.localPath(StandardPaths.writableLocation(StandardPaths.GenericDataLocation)) + "/knotifications6/eventcalendar.notifyrc"
	function installNotifyrc() {
		if (NotificationState.notifyrcInstalled || NotificationState.notifyrcInstalling) {
			return
		}
		NotificationState.notifyrcInstalling = true
		executable.execArgv(['install', '-C', '-D', '-m', '644', notifyrcSource, notifyrcTarget], function(cmd, exitCode, exitStatus, stdout, stderr) {
			NotificationState.notifyrcInstalling = false
			if (exitCode === 0) {
				NotificationState.notifyrcInstalled = true
				notificationManager.ownComponent = true
			} else {
				logger.log('Could not install eventcalendar.notifyrc:', exitCode, stderr)
			}
		})
	}

	function notify(args, callback) {
		logger.debug('NotificationManager.notify', args.event) // No event titles in logs
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

		var sound = args.sound || args.soundFile
		if (sound) {
			soundPlayer.play(sound)
		}
		if (!backend) {
			return
		}

		var own = ownComponent || NotificationState.notifyrcInstalled
		var title = args.summary || ""
		if (!own && args.appName) {
			title = args.appName + " · " + title // Shown under "System Notifications" otherwise
		}
		var actionList = (args.actions || []).map(function(entry) {
			var parts = String(entry).split(',')
			var id = parts.shift()
			return { id: id, label: parts.join(',') }
		})
		backend.send({
			componentName: own ? "eventcalendar" : "plasma_workspace",
			eventId: own ? (args.event || "reminder") : "notification",
			title: title,
			text: args.body || "",
			iconName: args.appIcon || "view-calendar",
			urgency: args.urgency,
		}, actionList, args.expireTimeout === 0, answer, args.expireTimeout > 0 ? args.expireTimeout : 0)
	}
}
