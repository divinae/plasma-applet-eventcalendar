import QtQuick
import org.kde.plasma.components as PlasmaComponents3

import "EventCopy.js" as EventCopy
import "SeriesEdit.js" as SeriesEdit
import "Undo.js" as Undo

// Saves an event dropped by dragging (week / day and month views): moves it, with an undo offer,
// or (copy, Ctrl held at the drop) creates a copy on the same calendar (no undo: the copy can be
// deleted). An occurrence of a repeating event asks first: this event or the whole series.
// The view keeps its dropped preview until its events are refilled (and then calls abandon());
// canceled() puts the event back: no choice in the menu, saving failed, or no answer at all.
Item {
	id: eventMover

	property var eventModel
	// Nothing is saved, or saving failed: the view puts the event back.
	signal canceled()

	// start / end: Google start / end objects. menuParent, menuX, menuY: where the occurrence menu opens.
	function drop(eventItem, start, end, copy, menuParent, menuX, menuY) {
		if (copy) {
			saving(true)
			saveCopy(eventItem, start, end)
		} else if (eventItem.recurringEventId) {
			pendingDrop = { eventItem: eventItem, start: start, end: end }
			scopeMenu.chosen = false
			scopeMenu.popup(menuParent, menuX, menuY)
		} else {
			saving()
			saveMove(eventItem, start, end, false)
		}
	}
	// The drop is being saved: wait for the update (the view refills its events). Copies and
	// series moves report back: then the wait starts again, for the refill only.
	function saving(reportsBack) {
		savingReportsBack = !!reportsBack
		dropTimeout.restart()
	}
	property bool savingReportsBack: false
	function saved() {
		if (dropTimeout.running) {
			dropTimeout.restart()
		}
	}
	function saveFailed() {
		if (dropTimeout.running) {
			abandon()
			canceled()
		}
	}
	// The view dropped the drag (eg: its events were refreshed): a menu still open goes away
	// without saving.
	function abandon() {
		dropTimeout.stop()
		if (!pendingDrop) {
			return
		}
		pendingDrop = null
		scopeMenu.chosen = true // Not a cancel: the view already reset
		scopeMenu.close()
	}

	function saveCopy(eventItem, start, end) {
		var source = eventModel.getEvent(eventItem.calendarId, eventItem.id) || eventItem
		eventModel.createEventFromData(eventItem.calendarId, EventCopy.copyBody(source, start, end), function(err) {
			if (err) {
				eventMover.saveFailed()
			} else {
				eventMover.saved()
			}
		})
	}

	function saveMove(eventItem, start, end, wholeSeries) {
		var calendarId = eventItem.calendarId
		if (!wholeSeries) {
			// Undo puts the old times back, offered once the move is saved (onEventUpdated).
			moveUndo = eventModel.canRestore(calendarId) ? {
				calendarId: calendarId,
				eventId: eventItem.id,
				times: Undo.savedTimes(eventItem),
			} : null
			eventModel.setEventProperties(calendarId, eventItem.id, { start: start, end: end })
			return
		}
		moveUndo = null
		var seriesId = eventItem.recurringEventId
		var occurrenceStart = new Date(eventItem.startDateTime)
		var calendar = eventModel.getCalendarList().filter(function(c) { return c.id === calendarId })[0]
		var timeZone = (calendar && calendar.timeZone) || 'UTC'
		var seriesTimes = null // The series' times before the move, for undo.
		eventModel.updateEventFromServer(calendarId, seriesId, function(series) {
			seriesTimes = Undo.savedTimes(series)
			return SeriesEdit.shiftedTimes(series, occurrenceStart, start, end, timeZone)
		}, function() {
			eventMover.saved()
			logic.update() // The occurrences come from a refetch.
			popup.offerUndo(i18n("Event moved"), function() {
				eventModel.updateEventFromServer(calendarId, seriesId, function() {
					return seriesTimes
				}, function() {
					logic.update()
				})
			})
		}, null, function(report) {
			report()
			eventMover.saveFailed()
		})
	}

	// An occurrence waiting for the menu: { eventItem, start, end }.
	property var pendingDrop: null
	// A saved single move: { calendarId, eventId, times } until its update arrives.
	property var moveUndo: null
	function offerMoveUndo(calendarId, eventId) {
		var u = moveUndo
		if (!u || u.calendarId !== calendarId || u.eventId !== eventId) {
			return
		}
		moveUndo = null
		popup.offerUndo(i18n("Event moved"), function() {
			eventModel.setEventProperties(u.calendarId, u.eventId, u.times)
		})
	}
	Connections {
		target: eventMover.eventModel
		function onError() {
			eventMover.moveUndo = null
			// A single move doesn't report back: any error while it's saved puts it back.
			if (eventMover.pendingDrop || (dropTimeout.running && !eventMover.savingReportsBack)) {
				eventMover.abandon()
				eventMover.canceled()
			}
		}
		function onEventUpdated(calendarId, eventId, data) {
			eventMover.offerMoveUndo(calendarId, eventId)
		}
	}

	// No answer at all (eg: signed out): put the event back.
	Timer {
		id: dropTimeout
		interval: 20000
		onTriggered: eventMover.canceled()
	}

	PlasmaComponents3.Menu {
		id: scopeMenu
		property bool chosen: false
		function choose(wholeSeries) {
			chosen = true
			var d = eventMover.pendingDrop
			eventMover.pendingDrop = null
			if (d) {
				eventMover.saving(wholeSeries)
				eventMover.saveMove(d.eventItem, d.start, d.end, wholeSeries)
			}
		}
		PlasmaComponents3.MenuItem {
			text: i18n("This event")
			onTriggered: scopeMenu.choose(false)
		}
		PlasmaComponents3.MenuItem {
			text: i18n("All events in the series")
			onTriggered: scopeMenu.choose(true)
		}
		// Closed without a choice: nothing changes. (closed comes before triggered.)
		onClosed: Qt.callLater(function() {
			if (!scopeMenu.chosen) {
				eventMover.pendingDrop = null
				eventMover.canceled()
			}
		})
	}
}
