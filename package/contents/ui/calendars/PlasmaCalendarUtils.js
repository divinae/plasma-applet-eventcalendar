.pragma library

// https://github.com/KDE/plasma-framework/blob/master/src/declarativeimports/calendar/eventpluginsmanager.h
// https://github.com/KDE/plasma-framework/blob/master/src/declarativeimports/calendar/eventpluginsmanager.cpp

var DEFAULT_PLUGIN_FILENAMES = [
	'holidaysevents.so',
	'pimevents.so',
]

// A missing plugin is reported once per plasmashell run, and not at all for the defaults (eg:
// pimevents.so is on by default but needs kdepim-addons, which many systems don't have).
var warnedMissingPlugins = {}
function warnMissingPlugin(pluginFilename) {
	if (warnedMissingPlugins[pluginFilename] || DEFAULT_PLUGIN_FILENAMES.indexOf(pluginFilename) >= 0) {
		return
	}
	warnedMissingPlugins[pluginFilename] = true
	console.log('[eventcalendar] Plasma calendar plugin not installed:', pluginFilename)
}

function toArray(listLike) {
	if (!listLike) {
		return []
	}
	if (Array.isArray(listLike)) {
		return listLike
	}
	if (typeof listLike === 'string') {
		if (!listLike) {
			return []
		}
		return [listLike]
	}
	if (typeof listLike.length === 'number') {
		var array = []
		for (var i = 0; i < listLike.length; i++) {
			array.push(listLike[i])
		}
		return array
	}
	return []
}

// The Akonadi collections of a PimCalendarsModel (kdepim-addons' pimevents plugin):
// [{ id, name, checked }], checked: shown in the Plasma calendars (the plugin's own selection,
// [PIMEventsPlugin] calendars= in plasmashellrc). Accounts (resources) are left out.
// Current versions: a flat list with the roles collectionId (UserRole + 1), name, enabled (false:
// an account) and checked. Older ones: a tree with a { id, enabled } object in UserRole + 1.
var PIM_ROLE_ID = 1, PIM_ROLE_NAME = 2, PIM_ROLE_ENABLED = 3, PIM_ROLE_CHECKED = 4
function pimCalendarRows(model, userRole, displayRole) {
	var rows = []
	if (!model) {
		return rows
	}
	function push(index) {
		var data = model.data(index, userRole + PIM_ROLE_ID)
		if (data && typeof data === 'object') {
			rows.push({
				id: String(data.id),
				name: String(model.data(index, displayRole) || ''),
				checked: !!data.enabled,
			})
		} else if (data !== undefined && data !== null && model.data(index, userRole + PIM_ROLE_ENABLED) !== false) {
			rows.push({
				id: String(data),
				name: String(model.data(index, userRole + PIM_ROLE_NAME) || model.data(index, displayRole) || ''),
				checked: !!model.data(index, userRole + PIM_ROLE_CHECKED),
			})
		}
	}
	// A tree under the accounts (Akonadi's EntityTreeModel): calendars can be folders in folders.
	function walk(parent, depth) {
		var count = parent ? model.rowCount(parent) : model.rowCount()
		for (var i = 0; i < count; i++) {
			var index = parent ? model.index(i, 0, parent) : model.index(i, 0)
			push(index)
			if (depth < 8 && model.hasChildren(index)) {
				walk(index, depth + 1)
			}
		}
	}
	walk(null, 0)
	return rows
}

function getPluginFilename(pluginPath) {
	if (!pluginPath || typeof pluginPath !== 'string') {
		return ''
	}
	var lastSlash = pluginPath.lastIndexOf('/')
	if (lastSlash === -1) {
		return pluginPath
	}
	return pluginPath.substr(lastSlash + 1)
}

// Whether pluginList (enabledCalendarPlugins) has the plugin named stem ("pimevents").
function hasPlugin(pluginList, stem) {
	return toArray(pluginList).some(function(plugin) {
		return getPluginStem(plugin) === stem
	})
}

function getPluginStem(pluginRef) {
	var pluginFilename = getPluginFilename(pluginRef)
	if (!pluginFilename) {
		return ''
	}
	if (pluginFilename.substr(-3) === '.so') {
		return pluginFilename.substr(0, pluginFilename.length - 3)
	}
	return pluginFilename
}

function getStoredPluginFilename(pluginRef) {
	var pluginStem = getPluginStem(pluginRef)
	if (!pluginStem) {
		return ''
	}
	return pluginStem + '.so'
}

// enabledCalendarPlugins as another (broken) Plasma 6 port may have left it: one character per
// entry ("h", "o", "l", ...: the characters joined back are the comma-separated list it was), or
// several plugins in one entry ("holidaysevents.so,pimevents.so"). Returns the plugin filenames,
// one-letter names (never a plugin) left out; a sound list comes back the same.
function repairPluginList(pluginList) {
	var entries = toArray(pluginList).map(function(entry) {
		return String(entry)
	})
	var oneCharacterEach = entries.length > 1 && entries.every(function(entry) {
		return entry.length === 1
	})
	if (oneCharacterEach) {
		entries = [entries.join('')]
	}
	var split = []
	entries.forEach(function(entry) {
		entry.split(',').forEach(function(part) {
			part = part.trim()
			if (part) {
				split.push(part)
			}
		})
	})
	return pluginPathToFilenameList(split).filter(function(filename) {
		return getPluginStem(filename).length > 1
	})
}

function pluginPathToFilenameList(pluginPathList) {
	var pluginFilenameList = []
	pluginPathList = toArray(pluginPathList)
	for (var i = 0; i < pluginPathList.length; i++) {
		var pluginFilename = getStoredPluginFilename(pluginPathList[i])
		if (!pluginFilename) {
			continue
		}
		if (pluginFilenameList.indexOf(pluginFilename) == -1) {
			pluginFilenameList.push(pluginFilename)
		}
	}
	return pluginFilenameList
}

function getModelRoleValue(eventPluginsManager, rowIndex, roleName) {
	if (!eventPluginsManager || !eventPluginsManager.model || typeof eventPluginsManager.model.get !== 'function') {
		return ''
	}
	try {
		var roleValue = eventPluginsManager.model.get(rowIndex, roleName)
		if (typeof roleValue !== 'undefined' && roleValue !== null && roleValue !== '') {
			return roleValue
		}
	} catch (e) {
	}
	try {
		var rowData = eventPluginsManager.model.get(rowIndex)
		if (rowData && typeof rowData === 'object' && typeof rowData[roleName] !== 'undefined') {
			return rowData[roleName]
		}
	} catch (e) {
	}
	return ''
}

function getPluginRuntimeIdentifier(eventPluginsManager, pluginFilenameA) {
	if (!eventPluginsManager || !eventPluginsManager.model || typeof eventPluginsManager.model.rowCount !== 'function') {
		return null
	}
	var pluginStemA = getPluginStem(pluginFilenameA)
	var sawPluginPath = false
	for (var i = 0; i < eventPluginsManager.model.rowCount(); i++) {
		var pluginId = getModelRoleValue(eventPluginsManager, i, 'pluginId')
		if (pluginId && pluginStemA == getPluginStem(pluginId)) {
			return pluginId
		}

		var pluginPath = getModelRoleValue(eventPluginsManager, i, 'pluginPath')
		if (pluginPath) {
			sawPluginPath = true
		}
		if (!pluginPath) {
			continue
		}
		if (pluginStemA == getPluginStem(pluginPath)) {
			return pluginPath
		}
	}

	// Plasma 6 switched enabledPlugins to plugin ids instead of full paths.
	// Fall back to the plugin stem when the manager model does not expose pluginPath.
	if (pluginStemA && !sawPluginPath) {
		return pluginStemA
	}

	// Plugin not installed or the manager model has not populated yet.
	return null
}

function getModelPluginFilename(eventPluginsManager, rowIndex, rowData) {
	if (rowData) {
		if (rowData.pluginId) {
			return getStoredPluginFilename(rowData.pluginId)
		}
		if (rowData.pluginPath) {
			return getStoredPluginFilename(rowData.pluginPath)
		}
	}

	var pluginId = getModelRoleValue(eventPluginsManager, rowIndex, 'pluginId')
	if (pluginId) {
		return getStoredPluginFilename(pluginId)
	}

	return getStoredPluginFilename(getModelRoleValue(eventPluginsManager, rowIndex, 'pluginPath'))
}

function pluginFilenameToPathList(eventPluginsManager, pluginFilenameList) {
	var pluginPathList = []
	pluginFilenameList = toArray(pluginFilenameList)
	for (var i = 0; i < pluginFilenameList.length; i++) {
		var pluginFilename = pluginFilenameList[i]
		if (!pluginFilename) {
			continue
		}
		var pluginRuntimeIdentifier = getPluginRuntimeIdentifier(eventPluginsManager, pluginFilename)
		if (!pluginRuntimeIdentifier) {
			warnMissingPlugin(pluginFilename)
			continue
		}
		if (pluginPathList.indexOf(pluginRuntimeIdentifier) == -1) {
			pluginPathList.push(pluginRuntimeIdentifier)
		}
	}
	return pluginPathList
}

function normalizePluginFilenameList(pluginFilenameList) {
	var normalizedList = []
	pluginFilenameList = toArray(pluginFilenameList)
	for (var i = 0; i < pluginFilenameList.length; i++) {
		var pluginFilename = pluginFilenameList[i]
		if (!pluginFilename || typeof pluginFilename !== 'string') {
			continue
		}
		if (normalizedList.indexOf(pluginFilename) === -1) {
			normalizedList.push(pluginFilename)
		}
	}
	return normalizedList
}

function getDefaultPluginFilenameList(eventPluginsManager) {
	var defaultPluginFilenameList = []
	for (var i = 0; i < DEFAULT_PLUGIN_FILENAMES.length; i++) {
		var pluginFilename = DEFAULT_PLUGIN_FILENAMES[i]
		if (eventPluginsManager && !getPluginRuntimeIdentifier(eventPluginsManager, pluginFilename)) {
			continue
		}
		defaultPluginFilenameList.push(pluginFilename)
	}
	return defaultPluginFilenameList
}

function getEffectivePluginFilenameList(eventPluginsManager, pluginFilenameList, allowEmpty) {
	var normalizedPluginFilenameList = normalizePluginFilenameList(pluginFilenameList)
	if (normalizedPluginFilenameList.length > 0 || allowEmpty) {
		return normalizedPluginFilenameList
	}
	return getDefaultPluginFilenameList(eventPluginsManager)
}

function populateEnabledPluginsByFilename(eventPluginsManager, pluginFilenameList, allowEmpty) {
	var pluginPathList = pluginFilenameToPathList(
		eventPluginsManager,
		getEffectivePluginFilenameList(eventPluginsManager, pluginFilenameList, allowEmpty)
	)
	eventPluginsManager.populateEnabledPluginsList(pluginPathList)
}

function setEnabledPluginsByFilename(eventPluginsManager, pluginFilenameList, allowEmpty) {
	var pluginPathList = pluginFilenameToPathList(
		eventPluginsManager,
		getEffectivePluginFilenameList(eventPluginsManager, pluginFilenameList, allowEmpty)
	)
	eventPluginsManager.enabledPlugins = pluginPathList
}

//--- Akonadi events by color
// The PIM events plugin tells an event's color, not its calendar: the color stands in for it.
// "#RRGGBB" or "#AARRGGBB" (a QColor as a string) -> "rrggbb", "" without one.
function colorKey(color) {
	var m = /^#(?:[0-9a-f]{2})?([0-9a-f]{6})$/i.exec(String(color || ""))
	return m ? m[1].toLowerCase() : ""
}

// The events' calendars named idPrefix + a color key, as [{ id, color, count, titles }], with their
// first titleCount different titles. By color: each keeps its place as the events change.
function colorCalendars(events, idPrefix, titleCount) {
	var byId = {}
	var list = []
	;(events || []).forEach(function(event) {
		var id = String(event.calendarId || "")
		if (id.indexOf(idPrefix) !== 0) {
			return
		}
		var group = byId[id]
		if (!group) {
			group = byId[id] = { id: id, color: "#" + id.substr(idPrefix.length), count: 0, titles: [] }
			list.push(group)
		}
		group.count++
		var title = String(event.summary || "").trim()
		if (title && group.titles.length < titleCount && group.titles.indexOf(title) < 0) {
			group.titles.push(title)
		}
	})
	return list.sort(function(a, b) {
		return a.id < b.id ? -1 : a.id > b.id ? 1 : 0
	})
}

// Akonadi's database, read with psql when it's PostgreSQL and psql is
// installed: the script lines that run one SELECT, its rows as "column|column" lines; nothing
// otherwise.
function akonadiPsqlLines(sql) {
	return [
		'rc="${XDG_CONFIG_HOME:-$HOME/.config}/akonadi/akonadiserverrc"',
		'if [ -f "$rc" ] && command -v psql >/dev/null && grep -q "^Driver=QPSQL" "$rc"; then',
		// Host (the socket directory) and the database name of the [QPSQL] section.
		'host=$(awk -F= \'/^\\[/{s=($0=="[QPSQL]")} s&&$1=="Host"{print substr($0,6);exit}\' "$rc")',
		'name=$(awk -F= \'/^\\[/{s=($0=="[QPSQL]")} s&&$1=="Name"{print substr($0,6);exit}\' "$rc")',
		'timeout 5 psql ${host:+-h "$host"} -d "${name:-akonadi}" -At -c "' + sql + '" 2>/dev/null',
		'fi',
	]
}

// The Akonadi calendars' colors (the collectioncolor attribute) are only in Akonadi's database
// (akonadiPsqlLines); without it nothing (the colors and names then come from the events). Lines
// "collection id|#aarrggbb".
function akonadiColorsLines() {
	return akonadiPsqlLines("SELECT collectionid, convert_from(value, 'UTF8') FROM collectionattributetable WHERE convert_from(type, 'UTF8') = 'collectioncolor'")
}

// The collections of Akonadi's Google resources, with the account of each: lines
// "account|resource|email" from the resources' settings, "collection|id|resource|remote id" from the
// database (a calendar's remote id is its Google calendar id).
function akonadiGoogleCollectionsLines() {
	return [
		'for f in "${XDG_CONFIG_HOME:-$HOME/.config}"/akonadi_google_resource_*rc; do',
		'r=${f##*/}; [ -f "$f" ] && sed -n "s/^Account=/account|${r%rc}|/p" "$f"',
		'done',
	].concat(akonadiPsqlLines("SELECT 'collection', c.id, r.name, c.remoteid FROM collectiontable c JOIN resourcetable r ON r.id = c.resourceid WHERE r.name LIKE 'akonadi_google_resource_%'"))
}
// Both: the colors' lines and the collections' lines in one output.
function akonadiCalendarsCommand() {
	return ['sh', '-c', akonadiColorsLines().concat(akonadiGoogleCollectionsLines(), ['exit 0']).join('\n')]
}
// The widget's Google accounts (GoogleAccountsStore.accounts) for akonadiMirroredCollections:
// { "email": ["calendar id", ...] }, the email being the primary calendar's id, in lower case. Only
// the calendars shown in the widget (calendarIdList, "primary" as the primary's id): Akonadi's copy
// of one left out here stays (its events come from nowhere else).
function googleCalendarIdsByAccount(accounts) {
	var calendarIds = {}
	;(accounts || []).forEach(function(account) {
		var list = account && account.calendarList ? Array.prototype.slice.call(account.calendarList) : []
		var primary = list.filter(function(calendar) { return calendar && calendar.primary })[0]
		if (primary && primary.id) {
			var shown = account.calendarIdList ? Array.prototype.slice.call(account.calendarIdList) : []
			calendarIds[String(primary.id).toLowerCase()] = shown.map(function(id) {
				return id === 'primary' ? primary.id : id
			})
		}
	})
	return calendarIds
}
// The collection ids of the Google calendars that Akonadi syncs for an account also signed in to
// in the widget: { "collection id": true }. calendarIds: { "email": ["calendar id", ...] }, the
// emails in lower case.
function akonadiMirroredCollections(stdout, calendarIds) {
	var accounts = {}
	var collections = []
	String(stdout || '').split('\n').forEach(function(line) {
		var fields = line.trim().split('|')
		if (fields[0] === 'account' && fields.length >= 3) {
			accounts[fields[1]] = fields.slice(2).join('|').trim().toLowerCase()
		} else if (fields[0] === 'collection' && fields.length >= 4) {
			collections.push({ id: fields[1], resource: fields[2], remoteId: fields.slice(3).join('|') })
		}
	})
	var mirrored = {}
	collections.forEach(function(collection) {
		var ids = (calendarIds || {})[accounts[collection.resource]]
		if (ids && ids.indexOf(collection.remoteId) >= 0) {
			mirrored[collection.id] = true
		}
	})
	return mirrored
}
// The command's output as { "collection id": "#rrggbb" }.
function parseAkonadiColors(stdout) {
	var colors = {}
	String(stdout || '').split('\n').forEach(function(line) {
		var m = /^(\d+)\|(#[0-9a-f]{6,8})\s*$/i.exec(line)
		if (m) {
			colors[m[1]] = '#' + colorKey(m[2])
		}
	})
	return colors
}
// The color keys that only mirrored calendars (akonadiMirroredCollections) among the shown ones
// (pimCalendarRows, checked) have: { key: true }. Their events are the signed-in account's.
function mirroredColorKeys(rows, colors, mirrored) {
	var mirroredKeys = {}
	var otherKeys = {}
	;(rows || []).forEach(function(row) {
		var key = row.checked ? colorKey((colors || {})[row.id]) : ''
		if (key) {
			if ((mirrored || {})[row.id]) {
				mirroredKeys[key] = true
			} else {
				otherKeys[key] = true
			}
		}
	})
	Object.keys(otherKeys).forEach(function(key) {
		delete mirroredKeys[key]
	})
	return mirroredKeys
}

// Color key -> the names of the shown calendars (pimCalendarRows, checked) in that color.
function namesByColor(rows, colors) {
	var names = {}
	;(rows || []).forEach(function(row) {
		var key = row.checked ? colorKey(colors[row.id]) : ''
		if (key) {
			names[key] = (names[key] || []).concat(row.name)
		}
	})
	return names
}
