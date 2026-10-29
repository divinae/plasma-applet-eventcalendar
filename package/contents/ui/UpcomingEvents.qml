import QtQuick
import org.kde.plasma.core as PlasmaCore

import "LocaleFuncs.js" as LocaleFuncs
import "MeetingLink.js" as MeetingLink
import "NotifyTiming.js" as NotifyTiming
import "Invitations.js" as Invitations
import "DailyAgenda.js" as DailyAgenda
import "MeetingRules.js" as MeetingRules
import "Shared.js" as Shared
import "Tasks.js" as Tasks
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
	//--- Muted events (the event menu): no notifications, no clock chip, no auto-join, Do Not
	// Disturb or full-screen alert; still shown in the views. One occurrence: calendar, id, start.
	readonly property var mutedKeys: plasmoid.configuration.mutedEventKeys || []
	function muteKey(eventItem) {
		return String(eventItem.calendarId || '') + '|' + String(eventItem.id || '') + '|' + new Date(eventItem.startDateTime).getTime()
	}
	function isMuted(eventItem) {
		return !!eventItem && mutedKeys.indexOf(muteKey(eventItem)) >= 0
	}
	function setMuted(eventItem, muted) {
		var key = muteKey(eventItem)
		var dayAgo = Date.now() - 24 * 60 * 60 * 1000
		// Without this one and without those of events past a day ago.
		var keys = Array.prototype.slice.call(mutedKeys).filter(function(k) {
			return k !== key && Number(String(k).split('|').pop()) > dayAgo
		})
		if (muted) {
			keys.push(key)
		}
		plasmoid.configuration.mutedEventKeys = keys
	}

	function shouldNotify(eventItem) {
		if (isMuted(eventItem)) {
			return false
		}
		if (plasmoid.configuration.eventNotifySkipAllDay && eventItem.start && eventItem.start.date) {
			return false
		}
		return !(plasmoid.configuration.eventNotifySkipDeclined && Shared.myResponse(eventItem) === 'declined')
	}

	// Every loaded event, calendar by calendar.
	function allEventItems() {
		var items = []
		for (var calendarId in eventsByCalendar) {
			items = items.concat(Shared.toArray(eventsByCalendar[calendarId].items))
		}
		return items
	}

	// Events the panel's next meeting and tooltip can show: none of calendars hidden in the popup's
	// calendar menu (their reminders still come: it's a view filter), no tasks, no hidden declined
	// ones, only ones that would be notified.
	function viewCandidates() {
		var items = []
		for (var calendarId in eventsByCalendar) {
			if (!Shared.isHiddenCalendar(calendarId, plasmoid.configuration.hiddenCalendarIds)) {
				items = items.concat(Shared.toArray(eventsByCalendar[calendarId].items))
			}
		}
		return items.filter(function(eventItem) {
			return eventItem.kind !== 'tasks#task' && shouldNotify(eventItem)
				&& !Shared.isHiddenDeclined(eventItem, plasmoid.configuration.showDeclinedEvents)
		})
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

	// Sends a notification with Join (event starting) / RSVP / Snooze actions.
	function notifyEvent(eventItem, args) {
		var meetingLink = MeetingLink.find(eventItem)
		var actions = []
		if (plasmoid.configuration.eventNotificationActions) {
			// Join only when the meeting starts: not on a reminder (minutes before) or an invitation.
			if (meetingLink && args.event === 'eventStarting') {
				actions.push('join,' + i18nc("%1 = Google Meet, Zoom, ...", "Join %1", meetingLink.label))
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
		var items = allEventItems()
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
		var dayKey = DailyAgenda.dayKey(now)
		plasmoid.configuration.dailyAgendaDay = dayKey
		var items = allEventItems()
		var agenda = DailyAgenda.summarize(items, now, 5)
		// Today's and overdue tasks: all of them with dailyAgendaTasks, else the morning task
		// summary (checkTaskSummary), merged here so there's one notification.
		var tasks = null
		var withTasks = !!plasmoid.configuration.dailyAgendaTasks
		if (withTasks || plasmoid.configuration.taskRemindersEnabled) {
			tasks = DailyAgenda.summarizeTasks(items, now, 3, withTasks)
			plasmoid.configuration.taskSummaryDay = dayKey
		}
		logger.log('notification: daily agenda,', agenda.count, 'events,', tasks ? tasks.count : 0, 'tasks') // No titles in the log
		sendDailyAgendaNotification(agenda, tasks)
	}

	// tasks: DailyAgenda.summarizeTasks, or null.
	function sendDailyAgendaNotification(agenda, tasks) {
		var lines = agenda.items.map(function(item) {
			var title = Shared.escapeHtml(item.title)
			return item.allDay
				? i18nc("daily agenda, %1 = event title", "All day: %1", title)
				: Shared.formatTime(item.start, appletConfig.timeFormat) + ' ' + title
		})
		if (agenda.more > 0) {
			lines.push(i18ncp("daily agenda, more events", "+%1 more", "+%1 more", agenda.more))
		}
		var hasTasks = !!tasks && tasks.count > 0
		if (hasTasks && agenda.count > 0) {
			lines.push(Shared.escapeHtml(taskSummaryTitle(tasks)) + ':')
		}
		if (hasTasks) {
			lines = lines.concat(taskSummaryLines(tasks))
		}
		notificationManager.notify({
			appName: i18n("Event Calendar"),
			appIcon: "view-calendar-day",
			event: 'dailyAgenda',
			expireTimeout: -1,
			summary: agenda.count > 0 ? i18np("Today: %1 event", "Today: %1 events", agenda.count)
				: hasTasks ? taskSummaryTitle(tasks)
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
	// A full-screen alert for this meeting (main.qml shows it on every screen).
	signal meetingAlertRequested(var eventItem)

	function atMeetingStart(eventItem, sent, now) {
		if (eventItem.endDateTime <= now || isMarkedEnded(eventItem) || isMuted(eventItem)) {
			return
		}
		var key = meetingKey(eventItem)
		// Settings > Events > Meetings: a timed meeting (with a video link), not declined, not of a
		// calendar left out of the clock's countdown.
		if (plasmoid.configuration.meetingFullScreenAlert && !sent[key + '|alert']
				&& !(eventItem.start && eventItem.start.date)
				&& (!plasmoid.configuration.meetingFullScreenAlertLinkOnly || !!MeetingLink.find(eventItem))
				&& Shared.myResponse(eventItem) !== 'declined'
				&& !Shared.isHiddenCalendar(eventItem.calendarId, plasmoid.configuration.clockHiddenCalendarIds)) {
			sent[key + '|alert'] = now
			logger.log('full-screen alert', eventItem.startDateTime) // No title in the log
			upcomingEvents.meetingAlertRequested(eventItem)
		}
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
		allEventItems().forEach(function(eventItem) {
			if (Tasks.isTask(eventItem)) {
				upcomingEvents.checkTaskReminders(eventItem, win, sent, now)
				return // Not as an all-day event
			}
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
		sentNotifications = sent
		checkSnoozedReminders()
		checkSnoozedTasks()
	}

	//--- Tasks: their own reminders (a due time or TickTick reminders, see NotifyTiming), in the
	// same window and with the same sent keys as events.
	function checkTaskReminders(task, win, sent, now) {
		if (!plasmoid.configuration.taskRemindersEnabled) {
			return
		}
		var due = NotifyTiming.taskDueFor(task, win)
		for (var i = 0; i < due.length; i++) {
			if (sent[due[i].key]) {
				continue
			}
			sent[due[i].key] = now
			logger.log('notification: task reminder', due[i].minutes, 'min before', Tasks.dueDay(task), task.dueTime || '') // No title in the log
			sendTaskReminderNotification(task)
		}
	}

	// "Due today 14:00", "Overdue", ...
	function taskDueText(task) {
		var info = NotifyTiming.taskDueState(task, timeModel.currentTime.getTime())
		var due = new Date(info.due)
		var time = info.timed ? Shared.formatTime(due, appletConfig.timeFormat) : ''
		if (info.state === 'overdue') {
			return i18nc("task reminder", "Overdue")
		} else if (info.state === 'today') {
			return time ? i18nc("task reminder, %1 = time", "Due today %1", time) : i18nc("task reminder", "Due today")
		} else if (info.state === 'tomorrow') {
			return time ? i18nc("task reminder, %1 = time", "Due tomorrow %1", time) : i18nc("task reminder", "Due tomorrow")
		} else if (info.state === 'date') {
			var date = Shared.formatDate(due, Locale.ShortFormat)
			return i18nc("task reminder, %1 = date (and time)", "Due %1", time ? date + ' ' + time : date)
		}
		return ''
	}

	// Mark as done / Snooze; a click opens the task in the popup.
	function sendTaskReminderNotification(task) {
		var actions = ['done,' + i18nc("task reminder", "Mark as done")]
		if (upcomingEvents.snoozeMinutes > 0) {
			actions.push('snooze,' + i18np("Snooze 1 minute", "Snooze %1 minutes", upcomingEvents.snoozeMinutes))
		}
		notificationManager.notify({
			appName: i18n("Event Calendar"),
			appIcon: "view-task",
			event: 'taskReminder',
			expireTimeout: upcomingEvents.reminderExpireTimeout(),
			summary: task.summary || task.title || '',
			body: Shared.escapeHtml(taskDueText(task)),
			soundFile: plasmoid.configuration.eventReminderSfxEnabled ? plasmoid.configuration.eventReminderSfxPath : '',
			actions: actions,
		}, function(actionId) {
			if (actionId === 'default') {
				upcomingEvents.showInWidget(task)
			} else if (actionId === 'done') {
				var current = upcomingEvents.currentTask(task) || task
				eventModel.toggleTask(current, true, function(err) {
					if (err) {
						logger.log('task reminder: could not mark the task as done') // No title in the log
					}
				})
			} else if (actionId === 'snooze') {
				var at = new Date(timeModel.currentTime)
				at.setMinutes(at.getMinutes() + upcomingEvents.snoozeMinutes)
				upcomingEvents.snoozedTasks.push({ task: task, at: at })
			}
		})
	}

	// The loaded item of a task (after a sync the items are new objects), or null when gone.
	function currentTask(task) {
		var items = eventsByCalendar[task.calendarId] ? Shared.toArray(eventsByCalendar[task.calendarId].items) : []
		for (var i = 0; i < items.length; i++) {
			if (items[i] && items[i].id === task.id && Tasks.isTask(items[i])) {
				return items[i]
			}
		}
		return null
	}

	property var snoozedTasks: [] // [{ task, at }]
	function checkSnoozedTasks() {
		var now = timeModel.currentTime
		var remaining = []
		for (var i = 0; i < snoozedTasks.length; i++) {
			var snoozed = snoozedTasks[i]
			if (snoozed.at > now) {
				remaining.push(snoozed)
				continue
			}
			var task = currentTask(snoozed.task)
			if (task && !Tasks.isDone(task) && plasmoid.configuration.taskRemindersEnabled) {
				logger.log('notification: snoozed task reminder') // No title in the log
				sendTaskReminderNotification(task)
			}
		}
		snoozedTasks = remaining
	}

	//--- Morning summary of the tasks due today without reminders of their own, and overdue ones:
	// once a day at the daily agenda time; merged into the daily agenda when that's on.
	function checkTaskSummary() {
		if (!plasmoid.configuration.taskRemindersEnabled || plasmoid.configuration.dailyAgendaEnabled || !eventsSynced) {
			return
		}
		var now = timeModel.currentTime
		if (!(upcomingEvents.dateMin <= now && now <= upcomingEvents.dateMax)) {
			return
		}
		if (!DailyAgenda.isDue(now, plasmoid.configuration.dailyAgendaTime, plasmoid.configuration.taskSummaryDay)) {
			return
		}
		plasmoid.configuration.taskSummaryDay = DailyAgenda.dayKey(now)
		var tasks = DailyAgenda.summarizeTasks(allEventItems(), now, 3, false)
		logger.log('notification: task summary,', tasks.count, 'tasks') // No titles in the log
		if (tasks.count > 0) {
			sendTaskSummaryNotification(tasks)
		}
	}

	// "3 tasks due today", "2 overdue tasks", "3 tasks due today, 2 overdue".
	function taskSummaryTitle(tasks) {
		if (tasks.overdue === 0) {
			return i18np("%1 task due today", "%1 tasks due today", tasks.today)
		} else if (tasks.today === 0) {
			return i18np("%1 overdue task", "%1 overdue tasks", tasks.overdue)
		}
		return i18nc("%1 = 3 tasks due today, %2 = 2 overdue", "%1, %2",
			i18np("%1 task due today", "%1 tasks due today", tasks.today),
			i18ncp("tasks", "%1 overdue", "%1 overdue", tasks.overdue))
	}

	// The titles (escaped) and "+N more".
	function taskSummaryLines(tasks) {
		var lines = tasks.titles.map(function(title) {
			return Shared.escapeHtml(title)
		})
		if (tasks.more > 0) {
			lines.push(i18ncp("task summary, more tasks", "+%1 more", "+%1 more", tasks.more))
		}
		return lines
	}

	function sendTaskSummaryNotification(tasks) {
		notificationManager.notify({
			appName: i18n("Event Calendar"),
			appIcon: "view-task",
			event: 'taskReminder',
			expireTimeout: -1,
			summary: taskSummaryTitle(tasks),
			body: taskSummaryLines(tasks).join('<br />'),
		}, function(actionId) {
			if (actionId === 'default') {
				root.expanded = true
			}
		})
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
		var items = viewCandidates()
		for (var i = 0; i < items.length; i++) {
			var eventItem = items[i]
			if (isEventInProgress(eventItem) && isMarkedEnded(eventItem)) {
				continue
			}
			if (plasmoid.configuration.clockNextEventSkipAllDay && eventItem.start && eventItem.start.date) {
				continue
			}
			if (Shared.isHiddenCalendar(eventItem.calendarId, plasmoid.configuration.clockHiddenCalendarIds)) {
				continue
			}
			// Not accepted: a maybe, or an invitation not answered yet (your own events count).
			if (plasmoid.configuration.clockNextEventAcceptedOnly && Shared.isUnconfirmedResponse(Shared.myResponse(eventItem))) {
				continue
			}
			var inProgress = isEventInProgress(eventItem)
			if (!inProgress && !(now < eventItem.startDateTime && eventItem.startDateTime.getTime() <= windowEnd)) {
				continue
			}
			var hasLink = !!MeetingLink.find(eventItem)
			if (plasmoid.configuration.clockNextEventLinkOnly && !hasLink) {
				continue
			}
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
		var time = Shared.formatTime(start, appletConfig.timeFormat)
		var when
		if (days === 0) {
			when = time
		} else if (days === 1) {
			when = i18nc("%1 = time", "tomorrow %1", time)
		} else {
			when = Shared.formatDate(start, Locale.ShortFormat) + ' ' + time
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
		var items = viewCandidates()
		for (var i = 0; i < items.length; i++) {
			var eventItem = items[i]
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
		tooltipNowText = current
			? i18nc("%1 = event title, %2 = end time", "Now: %1, until %2", current.summary,
				Shared.formatTime(current.endDateTime, appletConfig.timeFormat))
			: ""
		tooltipNextText = next ? i18nc("%1 = event title, %2 = when", "Next: %1, %2", next.summary, formatTooltipStart(next, now)) : ""
		updateTooltipTasks()
	}

	// Tooltip: "3 overdue tasks", of the task lists not hidden in the popup.
	property string tooltipTasksText: ""
	function updateTooltipTasks() {
		var items = []
		for (var calendarId in eventsByCalendar) {
			if (!Shared.isHiddenCalendar(calendarId, plasmoid.configuration.hiddenCalendarIds)) {
				items = items.concat(Shared.toArray(eventsByCalendar[calendarId].items))
			}
		}
		var count = DailyAgenda.overdueTaskCount(items, timeModel.currentTime)
		tooltipTasksText = count > 0 ? i18np("%1 overdue task", "%1 overdue tasks", count) : ""
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
		checkTaskSummary()
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
				upcomingEvents.checkTaskSummary()
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
