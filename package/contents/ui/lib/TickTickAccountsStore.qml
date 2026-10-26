import QtQuick

import "ConfigUtils.js" as ConfigUtils
import "SafeConfig.js" as SafeConfig
import "TickTickAccountState.js" as TickTickAccountState

// TickTick accounts: config key tickTickAccounts (base64 JSON: id, label, server, projectList,
// projectIdList, see TickTickAccountState.serializeAccount). Each account's API token is in the
// system keyring only (KeyringSecret, scope ticktick-account, key token), read once on load and
// kept in memory (account.token): never in config, logs or the event cache.
Item {
	id: store
	visible: false

	property string accountsKey: "tickTickAccounts"
	readonly property string secretKey: "token"

	property var configBridge: null
	property bool debugEnabled: false
	// false: the tokens aren't read from the keyring (a settings page that doesn't fetch).
	property bool loadTokens: true

	property var accountsConfigValue: ""
	property var accounts: []
	property bool secretsLoaded: true
	// The accounts with a token: those the widget fetches.
	readonly property var fetchableAccounts: accounts.filter(function(account) { return !!account.token })

	signal accountUpdated(string accountId)

	Logger {
		id: logger
		name: "eventcalendar-ticktick"
		showDebug: store.debugEnabled
	}

	KeyringSecret {
		id: keyring
		scope: "ticktick-account"
		debugEnabled: store.debugEnabled
	}

	Component.onCompleted: {
		if (!configBridge) {
			configBridge = ConfigUtils.findBridge(store)
		}
		syncFromConfig()
		loadAccounts()
	}

	Connections {
		target: !configBridge && typeof plasmoid !== "undefined" && plasmoid.configuration
			? plasmoid.configuration
			: null
		function onTickTickAccountsChanged() {
			store.syncFromConfig()
		}
		function onDebuggingChanged() {
			store.syncFromConfig()
		}
	}

	onConfigBridgeChanged: {
		syncFromConfig()
		loadAccounts()
	}
	onAccountsConfigValueChanged: loadAccounts()

	function readConfig(key, fallback) {
		if (configBridge) {
			var bridged = configBridge.read(key, fallback)
			return (bridged === undefined || bridged === null) ? fallback : bridged
		}
		if (typeof plasmoid !== "undefined" && plasmoid.configuration) {
			var directValue = plasmoid.configuration[key]
			return (directValue === undefined || directValue === null) ? fallback : directValue
		}
		return fallback
	}

	function writeConfig(key, value) {
		if (configBridge) {
			configBridge.write(key, value)
			return
		}
		if (typeof plasmoid !== "undefined" && plasmoid.configuration) {
			plasmoid.configuration[key] = value
		}
	}

	function syncFromConfig() {
		debugEnabled = !!readConfig("debugging", false)
		var next = readConfig(accountsKey, "")
		if (accountsConfigValue !== next) {
			accountsConfigValue = next
		}
	}

	function parseAccounts(value) {
		if (!value) {
			return []
		}
		if (Array.isArray(value)) {
			return value
		}
		if (typeof value !== "string") {
			return []
		}
		try {
			var parsed = SafeConfig.parseBase64Json(value, [])
			return Array.isArray(parsed) ? parsed : []
		} catch (e) {
			return []
		}
	}

	// Accounts from config, keeping the tokens already read; the missing ones from the keyring.
	function loadAccounts() {
		var parsed = parseAccounts(accountsConfigValue)
		var next = []
		for (var i = 0; i < parsed.length; i++) {
			var account = TickTickAccountState.normalizeAccount(parsed[i], accounts)
			if (account) {
				next.push(account)
			}
		}
		accounts = next
		loadMissingTokens()
	}

	function loadMissingTokens() {
		if (!loadTokens) {
			return
		}
		var missing = accounts.filter(function(account) { return !account.token }).map(function(account) {
			return account.id
		})
		if (!missing.length) {
			secretsLoaded = true
			return
		}
		secretsLoaded = false
		var pending = missing.length
		var found = {}
		missing.forEach(function(accountId) {
			keyring.load(accountId, secretKey, function(err, token) {
				if (token) {
					found[accountId] = token
				}
				pending -= 1
				if (pending === 0) {
					applyTokens(found)
					secretsLoaded = true
				}
			})
		})
	}

	function applyTokens(found) {
		var changed = false
		var next = accounts.map(function(account) {
			if (found[account.id] && !account.token) {
				var copy = TickTickAccountState.normalizeAccount(account, [])
				copy.token = found[account.id]
				changed = true
				return copy
			}
			return account
		})
		if (changed) {
			accounts = next
		}
	}

	function serialize() {
		var payload = SafeConfig.serializeBase64Json(accounts.map(TickTickAccountState.serializeAccount))
		if (configBridge) {
			accountsConfigValue = payload
		}
		writeConfig(accountsKey, payload)
	}

	function getAccountIndex(accountId) {
		for (var i = 0; i < accounts.length; i++) {
			if (accounts[i].id === accountId) {
				return i
			}
		}
		return -1
	}

	function getAccount(accountId) {
		var index = getAccountIndex(accountId)
		return index >= 0 ? accounts[index] : null
	}

	// A label for a new account on server: "TickTick", then "TickTick 2", ...
	function nextLabel(server) {
		var base = TickTickAccountState.serverName(server)
		var used = {}
		accounts.forEach(function(account) { used[account.label] = true })
		if (!used[base]) {
			return base
		}
		for (var n = 2; ; n++) {
			if (!used[base + " " + n]) {
				return base + " " + n
			}
		}
	}

	// Add an account: the token goes to the keyring first, the account to config once it's there.
	// fields: { server, projectList, projectIdList, label? }. callback(err, account): always called.
	function addAccount(fields, token, callback) {
		var account = TickTickAccountState.normalizeAccount({
			id: TickTickAccountState.generateId(),
			label: fields.label || nextLabel(fields.server),
			server: fields.server,
			projectList: fields.projectList,
			projectIdList: fields.projectIdList,
		}, [])
		keyring.store(account.id, secretKey, token, function(err) {
			if (err) {
				logger.log("Could not store the TickTick token in the keyring")
				callback(err, null)
				return
			}
			account.token = token
			accounts = accounts.concat([account])
			serialize()
			callback(null, account)
		})
	}

	// patch: saved fields (label, projectList, projectIdList); never a token.
	function updateAccount(accountId, patch) {
		var index = getAccountIndex(accountId)
		if (index < 0) {
			return
		}
		var copy = TickTickAccountState.normalizeAccount(accounts[index], [accounts[index]])
		for (var key in (patch || {})) {
			if (key !== "token" && key !== "id") {
				copy[key] = patch[key]
			}
		}
		var next = accounts.slice()
		next[index] = TickTickAccountState.normalizeAccount(copy, [copy])
		accounts = next
		serialize()
		accountUpdated(accountId)
	}

	function setProjectIdList(accountId, list) {
		updateAccount(accountId, { projectIdList: list })
	}

	// Remove an account and its token from the keyring. callback(err): optional.
	function removeAccount(accountId, callback) {
		var index = getAccountIndex(accountId)
		if (index < 0) {
			if (callback) {
				callback(null)
			}
			return
		}
		var next = accounts.slice()
		next.splice(index, 1)
		accounts = next
		serialize()
		keyring.clear(accountId, secretKey, function(err) {
			if (err) {
				logger.log("Could not remove the TickTick token from the keyring")
			}
			if (callback) {
				callback(err)
			}
		})
	}
}
