import QtQuick
import org.kde.plasma.core as PlasmaCore

import "LocaleFuncs.js" as LocaleFuncs
import "MeetingLink.js" as MeetingLink
import "NotifyTiming.js" as NotifyTiming
import "Shared.js" as Shared
import "./calendars"

CalendarManager {
	id: upcomingEvents

	property int minutesBeforeReminding: plasmoid.configuration.eventReminderMinutesBefore // minutes

	onFetchingData: {
		logger.debug('upcomingEvents.onFetchingData')
	}
	onAllDataFetched: {
		logger.debug('upcomingEvents.onAllDataFetched',
			upcomingEvents.dateMin,
			timeModel.currentTime,
			upcomingEvents.dateMax
		)
	}

	// Google events carry their own reminder times (event or calendar defaults).
	function reminderMinutesFor(eventItem) {
		if (plasmoid.configuration.eventReminderUseGoogle && Shared.isList(eventItem.reminderMinutes)) {
			return Shared.toArray(eventItem.reminderMinutes)
		}
		return [minutesBeforeReminding]
	}

	function isEventInProgress(eventItem) {
		return eventItem.startDateTime <= timeModel.currentTime && timeModel.currentTime < eventItem.endDateTime
	}

	// All-day events "start" at midnight and declined events don't need a reminder.
	function shouldNotify(eventItem) {
		if (plasmoid.configuration.eventNotifySkipAllDay && eventItem.start && eventItem.start.date) {
			return false
		}
		var attendees = eventItem.attendees
		if (plasmoid.configuration.eventNotifySkipDeclined && attendees) {
			for (var i = 0; i < attendees.length; i++) {
				if (attendees[i].self && attendees[i].responseStatus === 'declined') {
					return false
				}
			}
		}
		return true
	}

	property int snoozeMinutes: plasmoid.configuration.eventReminderSnoozeMinutes // 0 = no Snooze button
	property var snoozedReminders: [] // [{ eventItem, at }]

	function eventNotificationBody(eventItem, meetingLink) {
		var bodyText = LocaleFuncs.formatEventDuration(eventItem, {
			relativeDate: timeModel.currentTime,
			clock24h: appletConfig.clock24h,
		})
		if (eventItem.location && !(meetingLink && eventItem.location.trim() === meetingLink.url)) {
			bodyText += '<br />' + eventItem.location
		}
		return bodyText
	}

	// Sends a notification with Join / Open in Calendar (/ Snooze) actions.
	function notifyEvent(eventItem, args) {
		var meetingLink = MeetingLink.find(eventItem)
		var actions = []
		if (plasmoid.configuration.eventNotificationActions) {
			if (meetingLink) {
				actions.push('join,' + i18nc("%1 = Google Meet, Zoom, ...", "Join %1", meetingLink.label))
			}
			if (eventItem.htmlLink) {
				actions.push('open,' + i18n("Open in Calendar"))
			}
		}
		if (args.snooze && upcomingEvents.snoozeMinutes > 0) {
			actions.push('snooze,' + i18np("Snooze 1 minute", "Snooze %1 minutes", upcomingEvents.snoozeMinutes))
		}

		notificationManager.notify({
			appName: i18n("Event Calendar"),
			appIcon: "view-calendar-upcoming-events",
			event: args.event,
			expireTimeout: args.expireTimeout,
			urgency: args.urgency,
			summary: args.summary,
			body: args.body,
			soundFile: args.soundFile,
			actions: actions,
		}, function(actionId) {
			if (actionId === 'default') {
				upcomingEvents.showInWidget(eventItem) // Clicking the notification itself
			} else if (actionId === 'join' && meetingLink) {
				Shared.openExternalUrl(meetingLink.url)
			} else if (actionId === 'open' && eventItem.htmlLink) {
				Shared.openExternalUrl(eventItem.htmlLink)
			} else if (actionId === 'snooze') {
				var at = new Date(timeModel.currentTime)
				at.setMinutes(at.getMinutes() + upcomingEvents.snoozeMinutes)
				upcomingEvents.snoozedReminders.push({ eventItem: eventItem, at: at })
			}
		})
	}

	// Open the popup with the event's details (the popup is created on first expand).
	function showInWidget(eventItem) {
		root.expanded = true
		Qt.callLater(function() {
			var popup = root.fullRepresentationItem
			if (popup && typeof popup.activateEvent === 'function') {
				popup.activateEvent(eventItem)
			}
		})
	}

	function sendEventReminderNotification(eventItem, minutes) {
		var deltaText = LocaleFuncs.durationShortFormat(minutes * 60)
		var meetingLink = MeetingLink.find(eventItem)
		notifyEvent(eventItem, {
			// expireTimeout: (minutes*60 - 1) * 1000, // timeout resets on hover so may last longer than event starts.
			expireTimeout: plasmoid.configuration.eventReminderTimeout === 0 ? 0 : -1, // 0 = keep until dismissed
			summary: i18nc("%1 = 15 minutes, %2 = event title", "In %1: %2", deltaText, eventItem.summary),
			body: eventNotificationBody(eventItem, meetingLink),
			soundFile: plasmoid.configuration.eventReminderSfxEnabled ? plasmoid.configuration.eventReminderSfxPath : '',
			event: 'reminder',
			snooze: true,
		})
	}

	function sendSnoozedReminderNotification(eventItem) {
		var meetingLink = MeetingLink.find(eventItem)
		var minutesLeft = Math.round((eventItem.startDateTime - timeModel.currentTime) / 60000)
		var summary = minutesLeft > 0
			? i18nc("%1 = 15 minutes, %2 = event title", "In %1: %2", LocaleFuncs.durationShortFormat(minutesLeft * 60), eventItem.summary)
			: eventItem.summary
		notifyEvent(eventItem, {
			expireTimeout: plasmoid.configuration.eventReminderTimeout === 0 ? 0 : -1,
			summary: summary,
			body: eventNotificationBody(eventItem, meetingLink),
			soundFile: plasmoid.configuration.eventReminderSfxEnabled ? plasmoid.configuration.eventReminderSfxPath : '',
			event: 'reminder',
			snooze: minutesLeft > upcomingEvents.snoozeMinutes,
		})
	}

	function sendEventStartingNotification(eventItem) {
		var meetingLink = MeetingLink.find(eventItem)
		notifyEvent(eventItem, {
			// Keep until dismissed so Join is still clickable. -1 = notification server default.
			expireTimeout: plasmoid.configuration.eventStartingPersistent ? 0 : -1,
			urgency: plasmoid.configuration.eventStartingCritical ? 'critical' : 'normal',
			summary: eventItem.summary,
			body: eventNotificationBody(eventItem, meetingLink),
			soundFile: plasmoid.configuration.eventStartingSfxEnabled ? plasmoid.configuration.eventStartingSfxPath : '',
			event: 'eventStarting',
			snooze: false,
		})
	}

	function checkSnoozedReminders() {
		var now = timeModel.currentTime
		var remaining = []
		for (var i = 0; i < snoozedReminders.length; i++) {
			var snoozed = snoozedReminders[i]
			if (snoozed.at <= now) {
				if (snoozed.eventItem.startDateTime > now) {
					sendSnoozedReminderNotification(snoozed.eventItem)
				}
				// Else: the event already started, the "starting" notification covers it.
			} else {
				remaining.push(snoozed)
			}
		}
		snoozedReminders = remaining
	}

	// Every minute since the last check (see NotifyTiming), each notification once.
	property real lastNotifyCheck: NaN
	property var sentNotifications: ({}) // key -> when sent
	function checkForEventsStarting() {
		var now = timeModel.currentTime.getTime()
		var win = NotifyTiming.checkWindow(isFinite(lastNotifyCheck) ? lastNotifyCheck : null, now, 10 * 60000)
		lastNotifyCheck = now
		var sent = NotifyTiming.pruneSent(sentNotifications, now)
		for (var calendarId in eventsByCalendar) {
			var calendar = eventsByCalendar[calendarId]
			calendar.items.forEach(function(eventItem) {
				if (!shouldNotify(eventItem)) {
					return
				}
				var due = NotifyTiming.dueFor(eventItem, reminderMinutesFor(eventItem), win, now)
				for (var i = 0; i < due.length; i++) {
					if (sent[due[i].key]) {
						continue
					}
					// Logged without the title, to tell this widget's notifications apart from others
					// (eg: Google Calendar's own in a browser).
					if (due[i].kind === 'start') {
						if (plasmoid.configuration.eventStartingNotificationEnabled) {
							sent[due[i].key] = now
							logger.log('notification: event starting', eventItem.startDateTime)
							sendEventStartingNotification(eventItem)
						}
					} else if (plasmoid.configuration.eventReminderNotificationEnabled) {
						sent[due[i].key] = now
						logger.log('notification: reminder', due[i].minutes, 'min before', eventItem.startDateTime)
						sendEventReminderNotification(eventItem, due[i].minutes)
					}
				}
			})
		}
		sentNotifications = sent
		checkSnoozedReminders()
	}

	//--- Next event (panel chip, tooltip, middle-click join)
	property var nextEvent: null
	property var nextEventMeetingLink: null
	property string nextEventTime: "" // "5m" or "" when in progress
	property bool nextEventInProgress: false
	property int nextEventMinutesUntil: 0 // Upcoming: minutes until it starts
	property int nextEventMinutesLeft: 0 // In progress: minutes until it ends
	property real nextEventProgress: 0 // In progress: 0..1 of its duration

	//--- Meetings marked as ended (they often end early, or turn out not to be needed): no progress
	// bar, chip or "Now:" line for them. Until the event's real end; not kept across restarts.
	property var endedEvents: ({}) // key -> end time (ms)
	function endedKey(eventItem) {
		return String(eventItem.calendarId || '') + '|' + String(eventItem.id || eventItem.summary || '') + '|' + new Date(eventItem.startDateTime).getTime()
	}
	function isMarkedEnded(eventItem) {
		return !!endedEvents[endedKey(eventItem)]
	}
	function markEnded(eventItem) {
		var now = timeModel.currentTime.getTime()
		var kept = {}
		for (var key in endedEvents) {
			if (endedEvents[key] > now) {
				kept[key] = endedEvents[key]
			}
		}
		kept[endedKey(eventItem)] = new Date(eventItem.endDateTime).getTime()
		endedEvents = kept
		updateNextEvent()
		updateTooltipEvents()
	}
	// In progress and not marked as ended.
	function isOngoing(eventItem) {
		return isEventInProgress(eventItem) && !isMarkedEnded(eventItem)
	}

	function updateNextEvent() {
		var now = timeModel.currentTime
		var windowEnd = now.getTime() + plasmoid.configuration.clockNextEventMinutes * 60 * 1000
		var best = null
		var bestInProgress = false
		var bestHasLink = false
		for (var calendarId in eventsByCalendar) {
			var items = eventsByCalendar[calendarId].items
			for (var i = 0; i < items.length; i++) {
				var eventItem = items[i]
				if (eventItem.kind === 'tasks#task' || !shouldNotify(eventItem)) {
					continue
				}
				if (isEventInProgress(eventItem) && isMarkedEnded(eventItem)) {
					continue
				}
				var inProgress = isEventInProgress(eventItem)
				if (!inProgress && !(now < eventItem.startDateTime && eventItem.startDateTime.getTime() <= windowEnd)) {
					continue
				}
				var hasLink = !!MeetingLink.find(eventItem)
				var better = !best
					// In progress beats upcoming. Among in progress, one with a meeting link, then the latest started.
					|| (inProgress && !bestInProgress)
					|| (inProgress && bestInProgress && (hasLink && !bestHasLink || hasLink === bestHasLink && eventItem.startDateTime > best.startDateTime))
					|| (!inProgress && !bestInProgress && eventItem.startDateTime < best.startDateTime)
				if (better) {
					best = eventItem
					bestInProgress = inProgress
					bestHasLink = hasLink
				}
			}
		}
		nextEvent = best
		nextEventMeetingLink = best ? MeetingLink.find(best) : null
		nextEventInProgress = !!best && bestInProgress
		if (best && !bestInProgress) {
			var minutes = Math.ceil((best.startDateTime - now) / 60000)
			nextEventMinutesUntil = minutes
			nextEventTime = LocaleFuncs.durationShortFormat(minutes * 60)
		} else {
			nextEventMinutesUntil = 0
			nextEventTime = ""
		}
		if (best && bestInProgress) {
			var duration = best.endDateTime - best.startDateTime
			nextEventMinutesLeft = Math.max(0, Math.ceil((best.endDateTime - now) / 60000))
			nextEventProgress = duration > 0 ? Math.min(1, Math.max(0, (now - best.startDateTime) / duration)) : 0
		} else {
			nextEventMinutesLeft = 0
			nextEventProgress = 0
		}
	}

	// Tooltip: the event in progress and the next upcoming one, without the chip's time window.
	property string tooltipNowText: ""
	property string tooltipNextText: ""

	function formatTooltipStart(eventItem, now) {
		var start = eventItem.startDateTime
		var today = Shared.startOfDay(now)
		var startDay = Shared.startOfDay(start)
		var days = Math.round((startDay - today) / (24 * 60 * 60 * 1000))
		var time = Qt.formatTime(start, appletConfig.timeFormat)
		var when
		if (days === 0) {
			when = time
		} else if (days === 1) {
			when = i18nc("%1 = time", "tomorrow %1", time)
		} else {
			when = Qt.formatDate(start, Locale.ShortFormat) + ' ' + time
		}
		var msLeft = start - now
		if (msLeft < 24 * 60 * 60 * 1000) {
			var minutesLeft = Math.ceil(msLeft / 60000)
			when += ' ' + i18nc("%1 = 3h20m", "(in %1)", LocaleFuncs.durationShortFormat(minutesLeft * 60))
		}
		return when
	}

	function updateTooltipEvents() {
		var now = timeModel.currentTime
		var current = null
		var next = null
		for (var calendarId in eventsByCalendar) {
			var items = eventsByCalendar[calendarId].items
			for (var i = 0; i < items.length; i++) {
				var eventItem = items[i]
				if (eventItem.kind === 'tasks#task' || !shouldNotify(eventItem)) {
					continue
				}
				if (isEventInProgress(eventItem)) {
					if (isMarkedEnded(eventItem)) {
						continue
					}
					if (!current || eventItem.startDateTime > current.startDateTime) {
						current = eventItem
					}
				} else if (now < eventItem.startDateTime) {
					if (!next || eventItem.startDateTime < next.startDateTime) {
						next = eventItem
					}
				}
			}
		}
		tooltipNowText = current
			? i18nc("%1 = event title, %2 = end time", "Now: %1, until %2", current.summary,
				Qt.formatTime(current.endDateTime, appletConfig.timeFormat))
			: ""
		tooltipNextText = next ? i18nc("%1 = event title, %2 = when", "Next: %1, %2", next.summary, formatTooltipStart(next, now)) : ""
	}

	function joinNextEvent() {
		if (nextEventMeetingLink) {
			Shared.openExternalUrl(nextEventMeetingLink.url)
		} else if (nextEvent && nextEvent.htmlLink) {
			Shared.openExternalUrl(nextEvent.htmlLink)
		}
	}

	function tick() {
		checkForEventsStarting()
		updateNextEvent()
		updateTooltipEvents()
	}

	Connections {
		target: eventModel
		function onAllDataFetched() {
			logger.debug('upcomingEvents eventModel.onAllDataFetched', eventModel.dateMin, timeModel.currentTime, eventModel.dateMax)
			// if data is from current month
			if (eventModel.dateMin <= timeModel.currentTime && timeModel.currentTime <= eventModel.dateMax) {
				logger.debug('syncing upcomingEvents with eventModel')
				upcomingEvents.clear()
				upcomingEvents.dateMin = eventModel.dateMin
				upcomingEvents.dateMax = eventModel.dateMax
				upcomingEvents.eventsByCalendar = eventModel.eventsByCalendar
				upcomingEvents.allDataFetched()
				upcomingEvents.updateNextEvent()
				upcomingEvents.updateTooltipEvents()
			}
		}
	}

	Connections {
		target: timeModel
		function onMinuteChanged() { upcomingEvents.tick() }
	}
}
