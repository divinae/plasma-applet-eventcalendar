import QtQuick

import "GlancePublisher.js" as GlancePublisher
import "MeetingLink.js" as MeetingLink
import "Shared.js" as Shared
import "./lib"

// Shares today's and tomorrow's events with Glance, the panel widget, over D-Bus: Glance owns
// com.dv.glance /Calendar and listens; this pushes with gdbus when the events change and every
// 5 minutes (Glance may have started later). Without Glance the call just fails, and only the
// heartbeat tries again. Off with "Share events with Glance".
QtObject {
	id: publisher

	required property var upcomingEvents
	required property var eventModel
	// The weather (Logic's current, the widget's weatherByDay) when Event Calendar shows it
	property var logic: null
	property var weatherByDay: null
	property bool enabled: plasmoid.configuration.glanceShareEvents === true // Off by default

	// The last call reached Glance: changes go out at once; otherwise only the heartbeat tries
	property bool glanceSeen: true
	property bool busy: false
	property bool pending: false // A change while a call ran: sent once it's done

	property ExecUtil exec: ExecUtil {}

	function calendarNames() {
		var names = {}
		var list = eventModel.getCalendarList()
		for (var i = 0; i < list.length; i++) {
			if (list[i] && list[i].id) {
				names[list[i].id] = list[i].summary || list[i].name || ''
			}
		}
		return names
	}

	function collect(nowMs) {
		var names = calendarNames()
		var items = []
		var byCalendar = upcomingEvents.eventsByCalendar || {}
		for (var calendarId in byCalendar) {
			if (Shared.isHiddenCalendar(calendarId, plasmoid.configuration.hiddenCalendarIds)) {
				continue
			}
			var list = Shared.toArray(byCalendar[calendarId].items)
			for (var i = 0; i < list.length; i++) {
				var eventItem = list[i]
				var summary = Shared.attendeeSummary(eventItem.attendees)
				var item = GlancePublisher.plain(eventItem, MeetingLink.find(eventItem),
					Shared.myResponse(eventItem), summary.guestCount, names[eventItem.calendarId || calendarId],
					eventItem.calendarId || calendarId)
				if (item) {
					// Marked as ended (it ended early): it ends then, for Glance too
					var endedAt = upcomingEvents.markedEndedAt(eventItem)
					if (endedAt > 0 && endedAt < item.end) {
						item.end = Math.max(item.start, endedAt)
					}
					items.push(item)
				}
			}
		}
		return GlancePublisher.select(items, nowMs)
	}

	function currentWeather(nowMs) {
		if (!logic) {
			return null
		}
		var today = weatherByDay ? weatherByDay[Shared.dayKey(new Date(nowMs))] || null : null
		return GlancePublisher.weather(logic.currentWeatherData, today, plasmoid.configuration.weatherUnits)
	}

	function publish() {
		if (!enabled) {
			return
		}
		if (busy) {
			pending = true
			return
		}
		var now = Date.now()
		busy = true
		exec.execArgv([
			"gdbus", "call", "--session",
			"--dest", "com.dv.glance",
			"--object-path", "/Calendar",
			"--method", "com.dv.glance.Calendar.Publish",
			"1", String(plasmoid.id), GlancePublisher.payload(collect(now), now, currentWeather(now)),
		], function(cmd, exitCode) {
			publisher.busy = false
			publisher.glanceSeen = exitCode === 0
			if (publisher.pending) {
				publisher.pending = false
				publisher.changed()
			}
		})
	}

	// A burst of changes (a fetch round, an edit) goes out once
	property Timer debounce: Timer {
		interval: 2000
		onTriggered: publisher.publish()
	}
	function changed() {
		if (enabled && glanceSeen) {
			debounce.restart()
		}
	}

	property Timer heartbeat: Timer {
		interval: 5 * 60 * 1000
		repeat: true
		running: publisher.enabled
		triggeredOnStart: true
		onTriggered: publisher.publish()
	}

	property Connections onEvents: Connections {
		target: publisher.upcomingEvents
		function onAllDataFetched() { publisher.changed() }
		function onEventAdded() { publisher.changed() }
		function onEventRemoved() { publisher.changed() }
		function onEventUpdated() { publisher.changed() }
		function onEndedEventsChanged() { if (publisher.glanceSeen) publisher.publish() } // At once: a meeting just ended
	}

	property Connections onWeather: Connections {
		target: publisher.logic
		function onCurrentWeatherDataChanged() { publisher.changed() }
		function onDailyWeatherDataChanged() { publisher.changed() }
	}

	onEnabledChanged: if (enabled) changed()
}
