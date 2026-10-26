import QtQuick

import "ConfigUtils.js" as ConfigUtils
import "SafeConfig.js" as SafeConfig
import "TickTickAccountState.js" as TickTickAccountState

// TickTick accounts: config key tickTickAccounts (base64 JSON: id, label, server, projectList,
// projectIdList, see TickTickAccountState.serializeAccount). Each account's API token is in the
// system keyring only (KeyringSecret, scope ticktick-account, key token), read once on load and
// kept in memory (account.token): never in config, logs or the event cache.
// accounts is only replaced when its ids or tokens change (the widget then makes a manager per
// fetchable account again); other changes (label, projects) are made in place, with accountUpdated.
// A token the keyring couldn't read (an error, not a definite not-found) is tried again later
// (retryDelays); tokenNotFound has the accounts whose token is definitely not there.
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
	// false while tokens are read from the keyring, and while a read that failed waits to be retried.
	property bool secretsLoaded: true
	// { accountId: true }: the keyring answered it has no token for the account.
	property var tokenNotFound: ({})
	// Waits before reading tokens again after a keyring error: then every 5 minutes.
	readonly property var retryDelays: [5000, 15000, 60000, 300000]
	property int retryCount: 0
	property bool tokensLoading: false
	property bool tokensReloadPending: false
	property bool accountsLoaded: false
	// Bumped when an account changes in place, for bindings on accounts[i] (the settings page).
	property int accountsRevision: 0
	property var loadedConfigValue: null
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

	Timer {
		id: retryTimer
		repeat: false
		onTriggered: store.loadMissingTokens()
	}

	Component.onCompleted: {
		if (!configBridge) {
			configBridge = ConfigUtils.findBridge(store)
		}
		syncFromConfig()
		loadAccounts() // A no-op when the config value was loaded already (loadAccounts)
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

	function hasSameAccountIds(listA, listB) {
		if (listA.length !== listB.length) {
			return false
		}
		for (var i = 0; i < listA.length; i++) {
			if (listA[i].id !== listB[i].id || listA[i].token !== listB[i].token) {
				return false
			}
		}
		return true
	}

	// Accounts from config, keeping the tokens already read; the missing ones from the keyring.
	// The same config value isn't loaded twice (startup, the config bridge, our own serialize).
	function loadAccounts() {
		if (accountsLoaded && loadedConfigValue === accountsConfigValue) {
			return
		}
		accountsLoaded = true
		loadedConfigValue = accountsConfigValue
		var parsed = parseAccounts(accountsConfigValue)
		var next = []
		for (var i = 0; i < parsed.length; i++) {
			var account = TickTickAccountState.normalizeAccount(parsed[i], accounts)
			if (account) {
				next.push(account)
			}
		}
		if (hasSameAccountIds(accounts, next)) {
			// Same accounts and tokens: changed in place, the managers stay.
			var changed = []
			for (var j = 0; j < next.length; j++) {
				var before = JSON.stringify(TickTickAccountState.serializeAccount(accounts[j]))
				if (before !== JSON.stringify(TickTickAccountState.serializeAccount(next[j]))) {
					accounts[j] = next[j]
					changed.push(next[j].id)
				}
			}
			if (changed.length) {
				accountsRevision += 1
			}
			changed.forEach(function(accountId) { accountUpdated(accountId) })
		} else {
			accounts = next
		}
		loadMissingTokens()
	}

	// Read the tokens of the accounts without one (except definite not-founds) from the keyring.
	// When some couldn't be read, secretsLoaded stays false and it's tried again (retryDelays).
	function loadMissingTokens() {
		if (!loadTokens) {
			return
		}
		if (tokensLoading) {
			tokensReloadPending = true
			return
		}
		var missing = accounts.filter(function(account) {
			return !account.token && !tokenNotFound[account.id]
		}).map(function(account) {
			return account.id
		})
		if (!missing.length) {
			retryTimer.stop()
			retryCount = 0
			secretsLoaded = true
			return
		}
		secretsLoaded = false
		tokensLoading = true
		retryTimer.stop()
		var pending = missing.length
		var found = {}
		var notFound = []
		var failed = 0
		missing.forEach(function(accountId) {
			keyring.load(accountId, secretKey, function(err, token) {
				if (token) {
					found[accountId] = token
				} else if (err) {
					failed += 1
				} else {
					notFound.push(accountId)
				}
				pending -= 1
				if (pending > 0) {
					return
				}
				tokensLoading = false
				if (notFound.length) {
					var nextNotFound = {}
					for (var id in tokenNotFound) {
						nextNotFound[id] = true
					}
					notFound.forEach(function(notFoundId) { nextNotFound[notFoundId] = true })
					tokenNotFound = nextNotFound
				}
				applyTokens(found)
				if (failed) {
					scheduleRetry(failed)
				} else if (tokensReloadPending) {
					tokensReloadPending = false
					loadMissingTokens()
				} else {
					retryCount = 0
					secretsLoaded = true
				}
			})
		})
	}

	function scheduleRetry(failed) {
		tokensReloadPending = false
		var delay = retryDelays[Math.min(retryCount, retryDelays.length - 1)]
		retryCount += 1
		logger.log("Could not read " + failed + " TickTick token(s) from the keyring, trying again in " + Math.round(delay / 1000) + " s")
		retryTimer.interval = delay
		retryTimer.restart()
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

	// patch: saved fields (label, projectList, projectIdList); never a token. Changed in place
	// (accountUpdated): the account's manager stays.
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
		accounts[index] = TickTickAccountState.normalizeAccount(copy, [copy])
		accountsRevision += 1
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
		if (tokenNotFound[accountId]) {
			var notFound = {}
			for (var id in tokenNotFound) {
				if (id !== accountId) {
					notFound[id] = true
				}
			}
			tokenNotFound = notFound
		}
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
