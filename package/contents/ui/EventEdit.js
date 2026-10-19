.pragma library

.import "Shared.js" as Shared

// What the event editor (EventEditView.qml) sends: pure helpers, tested in tests/event_edit.test.js.

// The fields of `fields` ({ key: value }, in the order they're sent) to send for `item`: the ones
// that changed (unset and empty count as equal), or for a new event (item null) the non-empty ones.
function changedFields(item, fields) {
	var args = {}
	for (var key in fields) {
		var value = fields[key]
		if (item ? Shared.hasChanged(item[key], value) : !!value) {
			args[key] = value
		}
	}
	return args
}

// A Google start / end object changed. All-day dates compare as text, times as instants (Google
// returns dateTime with an offset, the editor sends UTC).
function dateObjChanged(oldObj, newObj) {
	oldObj = oldObj || {}
	if (newObj.date) {
		return oldObj.date !== newObj.date
	}
	return !oldObj.dateTime || new Date(oldObj.dateTime).getTime() !== new Date(newObj.dateTime).getTime()
}

// The event `item` gets other times: all day switched, or start / end (Google objects) moved.
function timesChanged(item, allDay, start, end) {
	var wasAllDay = !!(item.start && item.start.date)
	return wasAllDay !== allDay || dateObjChanged(item.start, start) || dateObjChanged(item.end, end)
}
