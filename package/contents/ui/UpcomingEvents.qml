import QtQuick
import org.kde.plasma.core as PlasmaCore

import "LocaleFuncs.js" as LocaleFuncs
import "MeetingLink.js" as MeetingLink
import "./calendars"

CalendarManager {
	id: upcomingEvents

	property int upcomingEventRange: 90 // minutes
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
		// sendEventListNotification()
	}

	function isUpcomingEvent(eventItem) {
		// console.log(eventItem.startDateTime, timeModel.currentTime, eventItem.startDateTime - timeModel.currentTime, eventItem.summary)
		var dt = eventItem.startDateTime - timeModel.currentTime
		return -30 * 1000 <= dt && dt <= upcomingEventRange * 60 * 1000 // starting within 90 minutes
	}

	function isSameMinute(a, b) {
		return a.getFullYear() === b.getFullYear()
			&& a.getMonth() === b.getMonth()
			&& a.getDate() === b.getDate()
			&& a.getHours() === b.getHours()
			&& a.getMinutes() === b.getMinutes()
	}

	function getDeltaMinutes(a1, n) {
		var a2 = new Date(a1)
		a2.setMinutes(a2.getMinutes() + n)
		return a2
	}

	function shouldSendReminder(eventItem) {
		var reminderDateTime = getDeltaMinutes(timeModel.currentTime, minutesBeforeReminding)
		return isSameMinute(reminderDateTime, eventItem.startDateTime)
	}

	function isEventStarting(eventItem) {
		return isSameMinute(timeModel.currentTime, eventItem.startDateTime) // starting this minute
	}

	function isEventInProgress(eventItem) {
		return eventItem.startDateTime <= timeModel.currentTime && timeModel.currentTime < eventItem.endDateTime
	}

	function filterEvents(predicate) {
		var events = []
		for (var calendarId in eventsByCalendar) {
			var calendar = eventsByCalendar[calendarId]
			calendar.items.forEach(function(eventItem, index, calendarEventList) {
				if (predicate(eventItem)) {
					events.push(eventItem)
				}
			})
		}
		return events
	}

	function formatHeading(heading) {
		var line = ''
		line += '<font size="4"><u>'
		line += heading
		line += '</u></font>'
		return line
	}

	function formatEvent(eventItem) {
		var line = ''
		line += '<font color="' + eventItem.backgroundColor + '">■</font> '
		line += '<b>' + eventItem.summary + ':</b> '
		line += LocaleFuncs.formatEventDuration(eventItem, {
			relativeDate: timeModel.currentTime,
			clock24h: appletConfig.clock24h,
		})
		return line
	}

	function formatEventList(events, heading) {
		var lines = []
		if (events.length > 0 && heading) {
			lines.push(formatHeading(heading))
		}
		events.forEach(function(eventItem) {
			lines.push(formatEvent(eventItem))
		})
		return lines
	}

	function addEventList(lines, heading, events) {
		var newLines = formatEventList(events, heading)
		lines.push.apply(lines, newLines)
	}

	function sendEventListNotification(args) {
		args = args || {}
		var eventsStarting = []
		var eventsInProgress = []
		var upcomingEvents = []
		for (var calendarId in eventsByCalendar) {
			var calendar = eventsByCalendar[calendarId]
			calendar.items.forEach(function(eventItem, index, calendarEventList) {
				if (isEventStarting(eventItem)) {
					eventsStarting.push(eventItem)
				} else if (isEventInProgress(eventItem)) {
					eventsInProgress.push(eventItem)
				} else if (isUpcomingEvent(eventItem)) {
					upcomingEvents.push(eventItem)
				}
			})
		}

		var lines = []
		if (typeof args.showEventsStarting !== "undefined" ? args.showEventsStarting : true) {
			addEventList(lines, i18n("Events Starting"), eventsStarting)
		}
		if (typeof args.showEventInProgress !== "undefined" ? args.showEventInProgress : true) {
			addEventList(lines, i18n("Events In Progress"), eventsInProgress)
		}
		if (typeof args.showUpcomingEvent !== "undefined" ? args.showUpcomingEvent : true) {
			addEventList(lines, i18n("Upcoming Events"), upcomingEvents)
		}

		if (lines.length >= 0) {
			var summary = i18n("Calendar")
			// var summary = lines.splice(0, 1)[0] // pop first item of array
			var bodyText = lines.join('<br />')
			bodyText = bodyText

			notificationManager.notify({
				appName: i18n("Event Calendar"),
				appIcon: "view-calendar-upcoming-events",
				summary: summary,
				body: bodyText,
			})
		}
	}

	function sendEventsStartingNotification() {
		sendEventListNotification({
			showEventInProgress: false,
			showUpcomingEvent: false,
		})
	}

	// All-day events "start" at midnight and declined events don't need a reminder.
	function shouldNotify(eventItem) {
		if (eventItem.start && eventItem.start.date) {
			return false
		}
		var attendees = eventItem.attendees
		if (attendees) {
			for (var i = 0; i < attendees.length; i++) {
				if (attendees[i].self && attendees[i].responseStatus === 'declined') {
					return false
				}
			}
		}
		return true
	}

	property int snoozeMinutes: 5
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
		if (meetingLink) {
			actions.push('join,' + i18nc("%1 = Google Meet, Zoom, ...", "Join %1", meetingLink.label))
		}
		if (eventItem.htmlLink) {
			actions.push('open,' + i18n("Open in Calendar"))
		}
		if (args.snooze) {
			actions.push('snooze,' + i18np("Snooze 1 minute", "Snooze %1 minutes", upcomingEvents.snoozeMinutes))
		}

		notificationManager.notify({
			appName: i18n("Event Calendar"),
			appIcon: "view-calendar-upcoming-events",
			expireTimeout: args.expireTimeout,
			summary: args.summary,
			body: args.body,
			soundFile: args.soundFile,
			actions: actions,
		}, function(actionId) {
			if (actionId === 'join' || (actionId === 'default' && meetingLink)) {
				Qt.openUrlExternally(meetingLink.url)
			} else if ((actionId === 'open' || actionId === 'default') && eventItem.htmlLink) {
				Qt.openUrlExternally(eventItem.htmlLink)
			} else if (actionId === 'snooze') {
				var at = new Date(timeModel.currentTime)
				at.setMinutes(at.getMinutes() + upcomingEvents.snoozeMinutes)
				upcomingEvents.snoozedReminders.push({ eventItem: eventItem, at: at })
			}
		})
	}

	function sendEventReminderNotification(eventItem, minutes) {
		var deltaText = LocaleFuncs.durationShortFormat(minutes * 60)
		var meetingLink = MeetingLink.find(eventItem)
		notifyEvent(eventItem, {
			// expireTimeout: (minutes*60 - 1) * 1000, // timeout resets on hover so may last longer than event starts.
			expireTimeout: 12000,
			summary: i18nc("%1 = 15 minutes, %2 = event title", "In %1: %2", deltaText, eventItem.summary),
			body: eventNotificationBody(eventItem, meetingLink),
			soundFile: plasmoid.configuration.eventReminderSfxEnabled ? plasmoid.configuration.eventReminderSfxPath : '',
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
			expireTimeout: 12000,
			summary: summary,
			body: eventNotificationBody(eventItem, meetingLink),
			soundFile: plasmoid.configuration.eventReminderSfxEnabled ? plasmoid.configuration.eventReminderSfxPath : '',
			snooze: minutesLeft > upcomingEvents.snoozeMinutes,
		})
	}

	function sendEventStartingNotification(eventItem) {
		var meetingLink = MeetingLink.find(eventItem)
		notifyEvent(eventItem, {
			expireTimeout: 0, // Stays until dismissed so Join is still clickable.
			summary: eventItem.summary,
			body: eventNotificationBody(eventItem, meetingLink),
			soundFile: plasmoid.configuration.eventStartingSfxEnabled ? plasmoid.configuration.eventStartingSfxPath : '',
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

	function checkForEventsStarting() {
		for (var calendarId in eventsByCalendar) {
			var calendar = eventsByCalendar[calendarId]
			calendar.items.forEach(function(eventItem, index, calendarEventList) {
				if (!shouldNotify(eventItem)) {
					return
				}
				if (isEventStarting(eventItem)) {
					if (plasmoid.configuration.eventStartingNotificationEnabled) {
						sendEventStartingNotification(eventItem)
					}
				} else if (shouldSendReminder(eventItem)) {
					if (plasmoid.configuration.eventReminderNotificationEnabled) {
						sendEventReminderNotification(eventItem, minutesBeforeReminding)
					}
				}
			})
		}
		checkSnoozedReminders()
	}

	function tick() {
		checkForEventsStarting()
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
			}
		}
	}

	Connections {
		target: timeModel
		function onMinuteChanged() { upcomingEvents.tick() }
	}
}
