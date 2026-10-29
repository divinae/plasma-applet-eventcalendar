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
