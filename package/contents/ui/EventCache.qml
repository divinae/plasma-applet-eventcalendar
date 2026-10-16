import QtQuick
import QtCore

import "./lib"
import "./EventCacheUtil.js" as EventCacheUtil

// The last loaded Google events on disk, shown right away after login or a Plasma restart (and
// offline after a reboot) until the first fetch finishes. See EventCacheUtil.js for what's kept:
// no descriptions, no attendee e-mails, never tokens.
// ~/.cache/plasma-eventcalendar/events.ini: the directory is 0700, the file 0600.
QtObject {
	id: eventCache

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
		if (!dirReady) {
			pendingText = text
			return
		}
		write(text)
	}

	function write(text) {
		settings.setValue('json', text)
		settings.sync()
		// QSettings keeps an existing file's mode on later writes; the first one gets the umask.
		executable.execArgv(['chmod', '600', filePath], function() {})
	}
}
