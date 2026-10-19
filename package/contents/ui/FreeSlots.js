.pragma library

// Find a time: busy times of people (Google freeBusy) and the free slots they have in common.
// Times are ms since the epoch; intervals are { start, end } with end exclusive.

// Per calendar id of the Google freeBusy answer: { busy: [{ start, end }], error: '' | reason }.
// An id the answer doesn't list: 'notFound'.
function parseResponse(data, ids) {
	var calendars = (data && data.calendars) || {}
	var out = {}
	for (var i = 0; i < ids.length; i++) {
		var entry = calendars[ids[i]]
		if (!entry) {
			out[ids[i]] = { busy: [], error: 'notFound' }
			continue
		}
		var errors = entry.errors || []
		if (errors.length) {
			out[ids[i]] = { busy: [], error: String(errors[0].reason || 'unknown') }
			continue
		}
		var busy = []
		var list = entry.busy || []
		for (var j = 0; j < list.length; j++) {
			var start = new Date(list[j].start).getTime()
			var end = new Date(list[j].end).getTime()
			if (!isNaN(start) && !isNaN(end) && end > start) {
				busy.push({ start: start, end: end })
			}
		}
		out[ids[i]] = { busy: merge(busy), error: '' }
	}
	return out
}

// Sorted, overlapping or touching intervals joined.
function merge(intervals) {
	var sorted = intervals.slice().sort(function(a, b) { return a.start - b.start })
	var out = []
	for (var i = 0; i < sorted.length; i++) {
		var last = out[out.length - 1]
		if (last && sorted[i].start <= last.end) {
			last.end = Math.max(last.end, sorted[i].end)
		} else {
			out.push({ start: sorted[i].start, end: sorted[i].end })
		}
	}
	return out
}

// Busy intervals clipped to [rangeStart, rangeEnd), as fractions of the range for drawing:
// [{ x, width }] in 0..1.
function blocks(busy, rangeStart, rangeEnd) {
	var length = rangeEnd - rangeStart
	var out = []
	if (length <= 0) {
		return out
	}
	for (var i = 0; i < busy.length; i++) {
		var start = Math.max(busy[i].start, rangeStart)
		var end = Math.min(busy[i].end, rangeEnd)
		if (end > start) {
			out.push({ x: (start - rangeStart) / length, width: (end - start) / length })
		}
	}
	return out
}

// Start times of free slots of `duration` in [rangeStart, rangeEnd) where nobody in `busyLists`
// (arrays of intervals) is busy, every `step` ms (aligned to the step from rangeStart), not before
// `notBefore`. At most `limit`. Returns [{ start, end }].
function freeSlots(busyLists, rangeStart, rangeEnd, duration, step, notBefore, limit) {
	var all = []
	for (var i = 0; i < busyLists.length; i++) {
		all = all.concat(busyLists[i] || [])
	}
	var busy = merge(all)
	var out = []
	if (duration <= 0 || step <= 0) {
		return out
	}
	var t = rangeStart
	if (notBefore && notBefore > t) {
		t = rangeStart + Math.ceil((notBefore - rangeStart) / step) * step
	}
	for (; t + duration <= rangeEnd && out.length < (limit || 8); t += step) {
		var end = t + duration
		var free = true
		for (var j = 0; j < busy.length; j++) {
			if (busy[j].start < end && busy[j].end > t) {
				free = false
				// Skip to the first step after this busy time.
				var next = rangeStart + Math.ceil((busy[j].end - rangeStart) / step) * step
				t = next - step
				break
			}
		}
		if (free) {
			out.push({ start: t, end: end })
		}
	}
	return out
}
