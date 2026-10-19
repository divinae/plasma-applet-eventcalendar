import QtQuick
import org.kde.plasma.core as PlasmaCore

import "LocaleFuncs.js" as LocaleFuncs
import "MeetingLink.js" as MeetingLink
import "NotifyTiming.js" as NotifyTiming
import "Invitations.js" as Invitations
import "DailyAgenda.js" as DailyAgenda
import "MeetingRules.js" as MeetingRules
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
	// Reminders set on the event itself always count; the calendar's defaults only when chosen.
	function reminderMinutesFor(eventItem) {
		if (eventItem.reminderOwn && Shared.isList(eventItem.reminderMinutes)) {
			return Shared.toArray(eventItem.reminderMinutes)
		}
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
		if (args.respond) {
			actions.push('accepted,' + i18nc("RSVP", "Yes"))
			actions.push('tentative,' + i18nc("RSVP", "Maybe"))
			actions.push('declined,' + i18nc("RSVP", "No"))
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
				meetingOpener.open(meetingLink.url)
			} else if (actionId === 'open' && eventItem.htmlLink) {
				Shared.openExternalUrl(eventItem.htmlLink)
			} else if (actionId === 'accepted' || actionId === 'tentative' || actionId === 'declined') {
				// A repeating meeting: answered for the whole series, like the invitation email.
				eventModel.respondToEvent(eventItem, actionId, !!eventItem.recurringEventId, function() {
					logic.update()
				})
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

	// eventReminderTimeout: 0 = keep until dismissed, N > 0 = N seconds, else Plasma's timeout.
	function reminderExpireTimeout() {
		var seconds = plasmoid.configuration.eventReminderTimeout
		if (seconds === 0) {
			return 0
		}
		return seconds > 0 ? seconds * 1000 : -1
	}

	function sendEventReminderNotification(eventItem, minutes) {
		var deltaText = LocaleFuncs.durationShortFormat(minutes * 60)
		var meetingLink = MeetingLink.find(eventItem)
		notifyEvent(eventItem, {
			expireTimeout: upcomingEvents.reminderExpireTimeout(),
			summary: i18nc("%1 = 15 minutes, %2 = event title", "In %1: %2", deltaText, eventItem.summary),
			body: eventNotificationBody(eventItem, meetingLink),
			soundFile: plasmoid.configuration.eventReminderSfxEnabled ? plasmoid.configuration.eventReminderSfxPath : '',
			event: 'reminder',
			snooze: true,
		})
	}

	//--- Invitations for today still to answer: notified once each (see Invitations.js).
	function checkInvitations() {
		if (!plasmoid.configuration.invitationNotificationEnabled) {
			return
		}
		var items = []
		for (var calendarId in eventsByCalendar) {
			items = items.concat(Shared.toArray(eventsByCalendar[calendarId].items))
		}
		var now = timeModel.currentTime
		var notified = Shared.toArray(plasmoid.configuration.invitationsNotified)
		var pending = Invitations.pendingToday(items, now, notified)
		if (!pending.length) {
			return
		}
		plasmoid.configuration.invitationsNotified = Invitations.markNotified(notified, pending, now)
		pending.forEach(function(eventItem) {
			logger.log('notification: invitation', eventItem.startDateTime) // No title in the log
			sendInvitationNotification(eventItem)
		})
	}

	function sendInvitationNotification(eventItem) {
		var meetingLink = MeetingLink.find(eventItem)
		var body = eventNotificationBody(eventItem, meetingLink)
		var organizer = eventItem.organizer
		if (organizer && !organizer.self && (organizer.displayName || organizer.email)) {
			body += '<br />' + i18nc("invitation, %1 = organizer", "From %1", organizer.displayName || organizer.email)
		}
		notifyEvent(eventItem, {
			event: 'invitation',
			expireTimeout: -1, // Plasma's timeout; it stays in the history to answer later
			summary: i18nc("%1 = event title", "Invitation: %1", eventItem.summary),
			body: body,
			respond: true,
		})
	}

	//--- Daily agenda: today's events once a day, at the first check at or after the set time
	// (also when the computer is turned on later). Only with synced events, else it would be empty.
	property bool eventsSynced: false
	function allEventItems() {
		var items = []
		for (var calendarId in eventsByCalendar) {
			items = items.concat(Shared.toArray(eventsByCalendar[calendarId].items))
		}
		return items
	}
	function checkDailyAgenda() {
		if (!plasmoid.configuration.dailyAgendaEnabled || !eventsSynced) {
			return
		}
		var now = timeModel.currentTime
		if (!(upcomingEvents.dateMin <= now && now <= upcomingEvents.dateMax)) {
			return // Events of another month: wait for the sync
		}
		if (!DailyAgenda.isDue(now, plasmoid.configuration.dailyAgendaTime, plasmoid.configuration.dailyAgendaDay)) {
			return
		}
		plasmoid.configuration.dailyAgendaDay = DailyAgenda.dayKey(now)
		var agenda = DailyAgenda.summarize(allEventItems(), now, 5)
		logger.log('notification: daily agenda,', agenda.count, 'events') // No titles in the log
		sendDailyAgendaNotification(agenda)
	}

	function sendDailyAgendaNotification(agenda) {
		var lines = agenda.items.map(function(item) {
			var title = Shared.escapeHtml(item.title)
			return item.allDay
				? i18nc("daily agenda, %1 = event title", "All day: %1", title)
				: Qt.formatTime(item.start, appletConfig.timeFormat) + ' ' + title
		})
		if (agenda.more > 0) {
			lines.push(i18ncp("daily agenda, more events", "+%1 more", "+%1 more", agenda.more))
		}
		notificationManager.notify({
			appName: i18n("Event Calendar"),
			appIcon: "view-calendar-day",
			event: 'dailyAgenda',
			expireTimeout: -1,
			summary: agenda.count > 0
				? i18np("Today: %1 event", "Today: %1 events", agenda.count)
				: i18n("Nothing planned today"),
			body: lines.join('<br />'),
			actions: ['agenda,' + i18n("Open Agenda")],
		}, function(actionId) {
			if (actionId === 'default' || actionId === 'agenda') {
				root.expanded = true
			}
		})
	}

	function sendSnoozedReminderNotification(eventItem) {
		var meetingLink = MeetingLink.find(eventItem)
		var minutesLeft = Math.round((eventItem.startDateTime - timeModel.currentTime) / 60000)
		var summary = minutesLeft > 0
			? i18nc("%1 = 15 minutes, %2 = event title", "In %1: %2", LocaleFuncs.durationShortFormat(minutesLeft * 60), eventItem.summary)
			: eventItem.summary
		notifyEvent(eventItem, {
			expireTimeout: upcomingEvents.reminderExpireTimeout(),
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

	//--- At a meeting's start, independent of the notifications: open its link (auto-join).
	// Keys without the calendar, so a meeting in two calendars is joined once.
	function meetingKey(eventItem) {
		return String(eventItem.id || eventItem.summary || '') + '|' + new Date(eventItem.startDateTime).getTime()
	}
	function atMeetingStart(eventItem, sent, now) {
		if (eventItem.endDateTime <= now || isMarkedEnded(eventItem)) {
			return
		}
		var key = meetingKey(eventItem)
		if (plasmoid.configuration.meetingAutoJoin && !sent[key + '|join']) {
			var meetingLink = MeetingLink.find(eventItem)
			if (MeetingRules.canAutoJoin(eventItem, !!meetingLink)) {
				sent[key + '|join'] = now
				logger.log('auto-join', eventItem.startDateTime) // No title or link in the log
				meetingOpener.open(meetingLink.url)
			}
		}
		startDoNotDisturb(eventItem, sent, now)
	}

	//--- Do Not Disturb during meetings (FocusMode.qml): at the start, and on startup / sync for a
	// meeting in progress; once per meeting (a Do Not Disturb turned off by hand stays off).
	function startDoNotDisturb(eventItem, sent, now) {
		if (!plasmoid.configuration.meetingDoNotDisturb) {
			return
		}
		var key = meetingKey(eventItem)
		if (sent[key + '|dnd'] || eventItem.endDateTime <= now || isMarkedEnded(eventItem)) {
			return
		}
		var hasLink = !!MeetingLink.find(eventItem)
		if (!MeetingRules.isDoNotDisturbMeeting(eventItem, hasLink, plasmoid.configuration.meetingDoNotDisturbAcceptedOnly)) {
			return
		}
		sent[key + '|dnd'] = now
		logger.log('do not disturb: meeting', eventItem.startDateTime, '-', eventItem.endDateTime) // No title in the log
		focusMode.startUntil(eventItem.endDateTime, key, timeModel.currentTime)
	}
	function checkMeetingsInProgress() {
		if (!plasmoid.configuration.meetingDoNotDisturb) {
			return
		}
		var now = timeModel.currentTime.getTime()
		var sent = sentNotifications
		allEventItems().forEach(function(eventItem) {
			if (isOngoing(eventItem)) {
				startDoNotDisturb(eventItem, sent, now)
			}
		})
		sentNotifications = sent
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
				var notify = shouldNotify(eventItem)
				var due = NotifyTiming.dueFor(eventItem, notify ? reminderMinutesFor(eventItem) : [], win, now)
				for (var i = 0; i < due.length; i++) {
					if (due[i].kind === 'start') {
						upcomingEvents.atMeetingStart(eventItem, sent, now)
					}
					if (!notify || sent[due[i].key]) {
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
		focusMode.endIfOwn(meetingKey(eventItem), timeModel.currentTime) // Do Not Disturb off, if the widget set it
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
			meetingOpener.open(nextEventMeetingLink.url)
		} else if (nextEvent && nextEvent.htmlLink) {
			Shared.openExternalUrl(nextEvent.htmlLink)
		}
	}

	function tick() {
		checkForEventsStarting()
		checkDailyAgenda()
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
				upcomingEvents.eventsSynced = true
				upcomingEvents.checkInvitations()
				upcomingEvents.checkDailyAgenda()
				upcomingEvents.checkMeetingsInProgress()
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
