import QtQuick
import QtCore

import "./lib"
import "./EventCacheUtil.js" as EventCacheUtil

// The last loaded Google events and tasks (Google Tasks, TickTick) on disk, shown right away after
// login or a Plasma restart (and offline after a reboot) until the first fetch finishes. See
// EventCacheUtil.js for what's kept: no descriptions or task notes, no attendee e-mails, never
// tokens.
// ~/.cache/plasma-eventcalendar/events.ini: the directory is 0700, the file 0600.
// Setting eventCacheEnabled off: nothing is read or written, and the file is deleted.
QtObject {
	id: eventCache

	readonly property bool enabled: typeof plasmoid === 'undefined' || !plasmoid || !plasmoid.configuration
		|| plasmoid.configuration.eventCacheEnabled !== false
	onEnabledChanged: {
		if (enabled) {
			makeDir()
		} else {
			removeFile()
		}
	}

	property var executable: ExecUtil {}

	function localPath(url) {
		var path = String(url || '')
		return path.indexOf('file://') === 0 ? decodeURIComponent(path.slice(7)) : path
	}
	readonly property string dirPath: localPath(StandardPaths.writableLocation(StandardPaths.GenericCacheLocation)) + '/plasma-eventcalendar'
	readonly property string filePath: dirPath + '/events.ini'

	// Writes wait for the private directory (QSettings would create it with the default mode).
	property bool dirReady: false
	property string pendingText: ''

	property var settings: Settings {
		location: 'file://' + eventCache.filePath
		category: 'events'
	}

	property var saveTimer: Timer {
		interval: 3000
		onTriggered: eventCache.saveNow()
	}
	property var pendingSnapshot: null

	Component.onCompleted: {
		if (enabled) {
			makeDir()
		} else {
			removeFile() // Turned off while the widget wasn't running
		}
	}

	// Off: the file goes, with what was waiting to be written.
	function removeFile() {
		saveTimer.stop()
		pendingSnapshot = null
		pendingText = ''
		// Emptied first: the next write (switched on again) is a change QSettings writes out.
		try {
			settings.setValue('json', '')
			settings.sync()
		} catch (e) {
			logger.log('EventCache: could not empty the cache')
		}
		executable.execArgv(['rm', '-f', '--', filePath], function(cmd, exitCode, exitStatus, stdout, stderr) {
			if (exitCode !== 0) {
				logger.log('EventCache: could not delete the cache file:', exitCode)
			}
		})
	}

	function makeDir() {
		if (dirReady) {
			return
		}
		executable.execArgv(['install', '-d', '-m', '700', dirPath], function(cmd, exitCode, exitStatus, stdout, stderr) {
			if (exitCode !== 0) {
				logger.log('EventCache: could not create the cache directory:', exitCode, stderr)
				return
			}
			eventCache.dirReady = true
			if (eventCache.pendingText) {
				var text = eventCache.pendingText
				eventCache.pendingText = ''
				eventCache.write(text)
			}
		})
	}

	// { savedAt, dateMin, dateMax, calendars: { calendarId: [event] } } or null.
	// isSelected(calendarId): only calendars that are still selected.
	function load(isSelected) {
		if (!enabled) {
			return null
		}
		var text = ''
		try {
			text = settings.value('json', '')
		} catch (e) {
			return null
		}
		return EventCacheUtil.deserialize(String(text || ''), new Date(), isSelected)
	}

	// Debounced: a refresh can finish several rounds in a row.
	function scheduleSave(eventsByCalendar, dateMin, dateMax) {
		if (!enabled) {
			return
		}
		pendingSnapshot = {
			text: EventCacheUtil.serialize(eventsByCalendar, dateMin, dateMax, new Date()),
		}
		saveTimer.restart()
	}

	function saveNow() {
		if (!pendingSnapshot) {
			return
		}
		var text = pendingSnapshot.text
		pendingSnapshot = null
		if (!enabled) {
			return
		}
		if (!dirReady) {
			pendingText = text
			return
		}
		write(text)
	}

	// An account was signed out or removed: its calendars leave the file right away (and a save
	// that's waiting). accountIds: the accounts still there.
	function pruneAccounts(accountIds) {
		if (!enabled) {
			return
		}
		var now = new Date()
		if (pendingSnapshot) {
			pendingSnapshot.text = EventCacheUtil.pruneText(pendingSnapshot.text, accountIds, now)
		}
		if (pendingText) {
			pendingText = EventCacheUtil.pruneText(pendingText, accountIds, now)
		}
		var text = ''
		try {
			text = String(settings.value('json', '') || '')
		} catch (e) {
			text = ''
		}
		if (!text) {
			return
		}
		var next = EventCacheUtil.pruneText(text, accountIds, now)
		if (next === text) {
			return
		}
		if (dirReady) {
			write(next)
		} else if (!pendingText) {
			pendingText = next
		}
	}

	function write(text) {
		settings.setValue('json', text)
		settings.sync()
		// QSettings keeps an existing file's mode on later writes; the first one gets the umask.
		executable.execArgv(['chmod', '600', filePath], function() {})
	}
}
