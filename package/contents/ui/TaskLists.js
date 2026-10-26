.pragma library

// Task list management (Google task lists, TickTick projects): what can be done with a list, and
// an account's stored lists after a change. Pure: the managers and the views use it.

// The colors offered for a TickTick list.
var swatches = ['#ff6161', '#ffac38', '#ffd324', '#4ca1ff', '#35d870', '#6e75f4', '#bb71e6', '#8a8f99']

// Lists the user owns or can write to can be changed; shared read-only ones can't.
function isEditableRole(accessRole) {
	return !accessRole || accessRole === 'owner' || accessRole === 'writer'
}

// What can be done with a list: { rename, delete, color, clearCompleted }.
// provider: the manager's calendarManagerId ('GoogleTasks', 'TickTick'). rawId: the list's id
// without the account prefix. The TickTick Inbox can't be renamed, recolored or deleted, and its
// API lists open tasks only, so it has no "clear completed".
function capabilities(provider, rawId, accessRole) {
	var none = { rename: false, delete: false, color: false, clearCompleted: false }
	if (!isEditableRole(accessRole)) {
		return none
	}
	if (provider === 'GoogleTasks') {
		return { rename: true, delete: true, color: false, clearCompleted: true }
	}
	if (provider === 'TickTick') {
		if (String(rawId || '').indexOf('inbox') === 0) {
			return none
		}
		return { rename: true, delete: true, color: true, clearCompleted: false }
	}
	return none
}

// The access role of a TickTick project: your own have no permission, shared ones 'write' (can
// be changed) or 'read' / 'comment' (read-only).
function tickTickRole(permission) {
	return !permission ? 'owner' : permission === 'write' ? 'writer' : 'reader'
}

function hasAny(caps) {
	return !!caps && (!!caps.rename || !!caps.delete || !!caps.color || !!caps.clearCompleted)
}

// A list name as typed: trimmed, '' when blank.
function cleanTitle(text) {
	return String(text === undefined || text === null ? '' : text).replace(/\s+/g, ' ').trim()
}

// '#rrggbb' (lower case) for a color the API takes, '' for anything else.
function hexColor(color) {
	var m = /^#?([0-9a-f]{6})$/i.exec(String(color || '').trim())
	return m ? '#' + m[1].toLowerCase() : ''
}

function copyList(list) {
	return Array.isArray(list) ? list.slice() : []
}

// The stored lists after a change, as new arrays: { lists, ids }. lists: the account's lists
// ([{ id, ... }]), ids: the selected (shown) ones.

// A new list: added, and selected.
function withAdded(lists, ids, list) {
	var nextLists = copyList(lists)
	var nextIds = copyList(ids)
	if (!list || !list.id) {
		return { lists: nextLists, ids: nextIds }
	}
	var exists = nextLists.some(function(l) { return l && l.id === list.id })
	if (!exists) {
		nextLists.push(list)
	}
	if (nextIds.indexOf(list.id) < 0) {
		nextIds.push(list.id)
	}
	return { lists: nextLists, ids: nextIds }
}

// A list's fields changed (eg: { title } or { name, color }); the selection is kept.
function withChanged(lists, ids, id, patch) {
	var nextLists = copyList(lists).map(function(l) {
		if (!l || l.id !== id) {
			return l
		}
		var copy = {}
		for (var key in l) {
			copy[key] = l[key]
		}
		for (var p in (patch || {})) {
			copy[p] = patch[p]
		}
		return copy
	})
	return { lists: nextLists, ids: copyList(ids) }
}

// A deleted list: gone from the lists and the selection.
function withRemoved(lists, ids, id) {
	return {
		lists: copyList(lists).filter(function(l) { return !l || l.id !== id }),
		ids: copyList(ids).filter(function(i) { return i !== id }),
	}
}

// How many tasks of items (a list's loaded items) a delete takes with it.
function taskCount(items) {
	var seen = {}
	var count = 0
	;(items || []).forEach(function(item) {
		if (item && item.kind === 'tasks#task' && !seen[item.id]) {
			seen[item.id] = true
			count++
		}
	})
	return count
}
