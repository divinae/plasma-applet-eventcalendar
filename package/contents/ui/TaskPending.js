.pragma library

// The task checks waiting for their save (TaskCheck), by 'calendarId:taskId' or
// 'calendarId:taskId:subtaskId': shared by every view, so a check made again while the save runs
// (the views rebuild their rows on every change) still shows what was clicked, and goes back
// when the save fails.

var pending = {} // key: { done: bool, token: number }
var listeners = [] // function(key, done), told when a key's save failed: done is what it is
var lastToken = 0

function key(item, subtaskId) {
	if (!item || !item.calendarId || !item.id) {
		return ''
	}
	return item.calendarId + ':' + item.id + (subtaskId ? ':' + subtaskId : '')
}

// -1: none; 0 / 1: unchecked / checked, being saved.
function get(key) {
	var entry = key ? pending[key] : null
	return entry ? (entry.done ? 1 : 0) : -1
}

// A save starts: returns its token for finish().
function start(key, done) {
	lastToken += 1
	if (key) {
		pending[key] = { done: !!done, token: lastToken }
	}
	return lastToken
}

// The save answered. Only the latest save of the key clears it; a failed one tells the checks
// what it is (wasDone: before the click).
function finish(key, token, failed, wasDone) {
	var entry = key ? pending[key] : null
	if (!entry || entry.token !== token) {
		return
	}
	delete pending[key]
	if (failed) {
		listeners.slice().forEach(function(listener) {
			listener(key, !!wasDone)
		})
	}
}

function listen(listener) {
	listeners.push(listener)
}

function unlisten(listener) {
	var i = listeners.indexOf(listener)
	if (i >= 0) {
		listeners.splice(i, 1)
	}
}
