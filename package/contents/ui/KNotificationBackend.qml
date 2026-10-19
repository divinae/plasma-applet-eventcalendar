import QtQuick
import org.kde.notification

// KNotification side of NotificationManager, in its own file so a missing org.kde.notification
// QML module only disables notifications instead of breaking the widget.
QtObject {
	id: backend

	property Component notificationComponent: Component {
		Notification {
			autoDelete: false
		}
	}
	property Component actionComponent: Component {
		NotificationAction {}
	}
	property Component cleanupTimerComponent: Component {
		Timer {
			running: true
			interval: 60 * 60 * 1000
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

	property Component closeTimerComponent: Component {
		Timer {
			running: true
		}
	}

	// See NotificationManager.notify. answer(actionId) is called once by the manager's wrapper.
	// closeAfterMs > 0: closed by us after that time (KNotification has no per-notification
	// timeout); then it isn't kept in Plasma's history.
	function send(props, actionList, persistent, answer, closeAfterMs) {
		var n = notificationComponent.createObject(backend, {
			componentName: props.componentName,
			eventId: props.eventId,
			title: props.title,
			text: props.text,
			iconName: props.iconName,
			urgency: urgencyFor(props.urgency),
			// Persistent: stays until dismissed. Otherwise Plasma's popup timeout applies, and an
			// expired notification stays in the history.
			flags: persistent || closeAfterMs > 0 ? Notification.Persistent : Notification.CloseOnTimeout,
		})

		var actions = []
		for (var i = 0; i < actionList.length; i++) {
			var action = actionComponent.createObject(n, { label: actionList[i].label })
			action.activated.connect(answer.bind(null, actionList[i].id))
			actions.push(action)
		}
		n.actions = actions
		var defaultAction = actionComponent.createObject(n, { label: "" })
		defaultAction.activated.connect(answer.bind(null, 'default'))
		n.defaultAction = defaultAction

		// "closed" also comes when the popup times out into the history: keep the object (and its
		// actions) a while longer, then free it.
		var closeTimer = null
		if (closeAfterMs > 0) {
			closeTimer = closeTimerComponent.createObject(n, { interval: closeAfterMs })
			closeTimer.triggered.connect(function() { n.close() })
		}
		n.closed.connect(function() {
			if (closeTimer) {
				closeTimer.stop()
			}
			answer('closed')
			var cleanup = cleanupTimerComponent.createObject(n)
			cleanup.triggered.connect(function() { n.destroy() })
		})
		n.sendEvent()
	}
}
