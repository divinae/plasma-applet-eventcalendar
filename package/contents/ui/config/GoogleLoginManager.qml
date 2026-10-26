import QtQuick

import "../lib"
import "../calendars"
import "../lib/GoogleOAuthConfig.js" as GoogleOAuthConfig
import "../lib/Pkce.js" as Pkce
import "../lib/ConfigUtils.js" as ConfigUtils
import "../lib/Requests.js" as Requests

Item {
	id: session

	Logger {
		id: logger
		name: "eventcalendar"
		showDebug: readConfig("debugging", false)
	}

	GoogleAccountsStore {
		id: accountsStore
		configBridge: session.configBridge
	}

	property var accounts: []
	property string activeAccountId: accountsStore.activeAccountId
	property var activeAccount: null

	readonly property bool isLoggedIn: accounts && accounts.length > 0
	readonly property bool needsRelog: accountNeedsRelog(activeAccount)

	property var calendarList: []
	property var calendarIdList: []
	property var tasklistList: []
	property var tasklistIdList: []

	property string localRedirectUri: "http://127.0.0.1:53682/"
	property string hostedRedirectUri: "https://alikestocode.github.io/plasma-applet-eventcalendar/"
	property string redirectMode: "local"
	function normalizedRedirectMode(mode) {
		return mode === "hosted" ? "hosted" : "local"
	}
	readonly property string redirectUri: normalizedRedirectMode(redirectMode) === "hosted"
		? hostedRedirectUri
		: localRedirectUri
	property string defaultClientId: "352447874752-sej1ldpd6piqgovtpog0dr91tb4sq5q3.apps.googleusercontent.com"
	property var configBridge: null
	function normalizedClientValue(value) {
		return value ? value.trim() : ""
	}
	property string effectiveClientId: ""
	property string effectiveClientSecret: ""
	property string pkceVerifier: ""
	property string pkceChallenge: ""
	property string authState: ""
	property var pendingAuthContext: null

	Connections {
		target: accountsStore
		function onAccountsChanged() {
			session.accounts = accountsStore.accounts.slice(0)
			session.refreshActiveAccount()
		}
		function onAccountUpdated(accountId) {
			session.accounts = accountsStore.accounts.slice(0)
			if (accountId === session.activeAccountId) {
				session.refreshActiveAccount()
			}
		}
		function onActiveAccountIdChanged() {
			session.refreshActiveAccount(accountsStore.activeAccountId)
		}
	}

	Component.onCompleted: {
		if (!configBridge) {
			configBridge = ConfigUtils.findBridge(session)
		}
		session.accounts = accountsStore.accounts.slice(0)
		migrateDefaultClientIfNeeded()
		refreshActiveAccount()
		refreshClientCredentials()
		ensurePkce()
	}

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
			if (typeof kcm !== "undefined") {
				kcm.needsSave = true
			}
		}
	}

	function refreshActiveAccount() {
		var targetAccountId = arguments.length > 0 ? arguments[0] : activeAccountId
		activeAccount = accountsStore.getAccount(targetAccountId)
		// Only assign when the content changed, so saving a checkbox (or a token refresh)
		// doesn't rebuild lists bound to these properties.
		function assignIfChanged(key, value) {
			if (JSON.stringify(session[key]) !== JSON.stringify(value)) {
				session[key] = value
			}
		}
		assignIfChanged('calendarIdList', activeAccount ? activeAccount.calendarIdList || [] : [])
		assignIfChanged('tasklistIdList', activeAccount ? activeAccount.tasklistIdList || [] : [])
		assignIfChanged('calendarList', activeAccount ? activeAccount.calendarList || [] : [])
		assignIfChanged('tasklistList', activeAccount ? activeAccount.tasklistList || [] : [])
	}

	onActiveAccountIdChanged: refreshActiveAccount(activeAccountId)

	function refreshClientCredentials() {
		migrateDefaultClientIfNeeded()
		var useDesktopClient = readConfig("useDesktopClient", false)
		var customId = normalizedClientValue(readConfig("customClientId", ""))
		var customSecret = normalizedClientValue(readConfig("customClientSecret", ""))
		var latestId = normalizedClientValue(readConfig("latestClientId", ""))
		var latestSecret = normalizedClientValue(readConfig("latestClientSecret", ""))
		if (customId) {
			effectiveClientId = customId
			effectiveClientSecret = customSecret
		} else if (!useDesktopClient && latestId) {
			effectiveClientId = latestId
			effectiveClientSecret = latestSecret
		} else {
			effectiveClientId = defaultClientId
			effectiveClientSecret = ""
		}
	}

	function migrateDefaultClientIfNeeded() {
		var customId = normalizedClientValue(readConfig("customClientId", ""))
		if (customId) {
			return
		}
		var latestId = normalizedClientValue(readConfig("latestClientId", ""))
		var latestSecret = normalizedClientValue(readConfig("latestClientSecret", ""))
		if (!latestId) {
			writeConfig("latestClientId", defaultClientId)
			latestId = defaultClientId
		}
		if (latestSecret) {
			if (readConfig("useDesktopClient", false) !== false) {
				writeConfig("useDesktopClient", false)
			}
		} else if (readConfig("useDesktopClient", false) !== true) {
			writeConfig("useDesktopClient", true)
		}
	}

	function ensurePkce() {
		if (!pkceVerifier || !pkceChallenge) {
			resetPkce()
		}
	}

	function resetPkce() {
		pkceVerifier = Pkce.generateVerifier()
		pkceChallenge = Pkce.challengeFromVerifier(pkceVerifier)
	}
	function generateAuthState() {
		return Pkce.generateOpaqueToken(32)
	}
	function ensureAuthState() {
		if (!authState) {
			authState = generateAuthState()
		}
	}
	function resetAuthState() {
		authState = generateAuthState()
	}
	function redirectUriForMode(mode) {
		return normalizedRedirectMode(mode) === "hosted" ? hostedRedirectUri : localRedirectUri
	}
	function buildAuthContext(modeOverride) {
		var mode = typeof modeOverride === "string" ? modeOverride : redirectMode
		var usePkce = !effectiveClientSecret
		return {
			clientId: effectiveClientId,
			clientSecret: effectiveClientSecret,
			redirectUri: redirectUriForMode(mode),
			pkceVerifier: usePkce ? pkceVerifier : "",
			pkceChallenge: usePkce ? pkceChallenge : "",
			state: authState,
		}
	}
	function currentAuthContext() {
		return pendingAuthContext || buildAuthContext()
	}
	function prepareAuthorization() {
		refreshClientCredentials()
		var configError = authConfigurationError()
		if (configError) {
			error(configError)
			throw new Error(configError)
		}
		var mode = normalizedRedirectMode(redirectMode)
		if (!effectiveClientSecret) {
			resetPkce()
		} else {
			pkceVerifier = ""
			pkceChallenge = ""
		}
		resetAuthState()
		pendingAuthContext = buildAuthContext(mode)
	}
	function authConfigurationError() {
		return authConfigurationErrorFor(effectiveClientId, effectiveClientSecret)
	}
	function authConfigurationErrorFor(clientId, clientSecret) {
		return GoogleOAuthConfig.authConfigurationError(clientId, clientSecret, defaultClientId)
	}
	function clearAuthorizationContext() {
		authState = ""
		pendingAuthContext = null
	}
	function clientIdSuffix(clientId) {
		var value = clientId ? String(clientId) : ""
		return value.length > 12 ? value.slice(-12) : value
	}
	function summarizeTokenResponse(parsed, ctx, accountId, existingAccount) {
		return {
			accountId: accountId || "",
			clientIdSuffix: clientIdSuffix(ctx && ctx.clientId),
			redirectUri: ctx && ctx.redirectUri ? ctx.redirectUri : "",
			usingPkce: !!(ctx && ctx.pkceVerifier),
			hasClientSecret: !!(ctx && ctx.clientSecret),
			existingAccountId: existingAccount && existingAccount.id ? existingAccount.id : "",
			existingAccountHasRefreshToken: !!(existingAccount && existingAccount.refreshToken),
			hasAccessToken: !!(parsed && parsed.access_token),
			hasRefreshToken: !!(parsed && parsed.refresh_token),
			tokenType: parsed && parsed.token_type ? parsed.token_type : "",
			expiresIn: parsed && parsed.expires_in ? parsed.expires_in : 0,
			scope: parsed && parsed.scope ? parsed.scope : "",
			error: parsed && parsed.error ? parsed.error : "",
			errorDescription: parsed && parsed.error_description ? parsed.error_description : "",
		}
	}
	function buildAuthorizationUrl(ctx) {
		var url = 'https://accounts.google.com/o/oauth2/v2/auth'
		url += '?scope=' + encodeURIComponent('https://www.googleapis.com/auth/calendar https://www.googleapis.com/auth/tasks')
		url += '&response_type=code'
		url += '&redirect_uri=' + encodeURIComponent(ctx.redirectUri)
		url += '&access_type=offline'
		url += '&prompt=consent'
		url += '&client_id=' + encodeURIComponent(ctx.clientId)
		if (ctx.state) {
			url += '&state=' + encodeURIComponent(ctx.state)
		}
		if (ctx.pkceChallenge) {
			url += '&code_challenge=' + encodeURIComponent(ctx.pkceChallenge)
			url += '&code_challenge_method=S256'
		}
		return url
	}

	//--- Signals
	signal newAccessToken()
	signal sessionReset()
	signal error(string err)

	//---
	readonly property string authorizationCodeUrl: {
		return buildAuthorizationUrl(currentAuthContext())
	}

	function setActiveAccountId(accountId) {
		accountsStore.setActiveAccountId(accountId)
	}

	function setCalendarIdList(list, accountId) {
		var targetId = accountId || activeAccountId
		if (targetId) {
			accountsStore.updateAccount(targetId, {
				calendarIdList: list,
				calendarSelectionInitialized: true,
			})
		}
	}

	function setTasklistIdList(list, accountId) {
		var targetId = accountId || activeAccountId
		if (targetId) {
			accountsStore.updateAccount(targetId, { tasklistIdList: list })
		}
	}

	// The account must sign in again: Google revoked the grant, or it was signed in with another
	// OAuth client / PKCE setting than the current one. Same rules as Logic.currentErrorMessage:
	// secret-based accounts refresh with their own stored client secret, so they're fine.
	function accountNeedsRelog(account) {
		if (!account) {
			return false
		}
		if (account.reauthRequired) {
			return true
		}
		if (account.sessionUsesPkce === false || (account.sessionUsesPkce === undefined && account.sessionClientSecret)) {
			return false
		}
		if (account.sessionClientId && account.sessionClientId != effectiveClientId) {
			return true
		}
		if (account.sessionUsesPkce === true && !!effectiveClientSecret) {
			return true
		}
		return false
	}

	function removeAccount(accountId) {
		logout(accountId)
	}

	function extractAuthorizationCode(input) {
		if (!input) {
			return ""
		}
		var trimmed = input.trim()
		var match = /[?&]code=([^&]+)/.exec(trimmed)
		if (match && match[1]) {
			return decodeURIComponent(match[1].replace(/\+/g, ' '))
		}
		return trimmed
	}

	function describeAuthError(ctx, data, fallbackErr) {
		var errorDescription = data && data.error_description
			? String(data.error_description)
			: ""
		if (data && data.error === "invalid_request"
			&& errorDescription.toLowerCase().indexOf("client_secret is missing") !== -1
		) {
			if (!ctx.clientSecret && ctx.clientId === defaultClientId) {
				return "Google rejected the built-in login because this client now requires a client secret. Add your own Google OAuth client ID and client secret, or switch back to a previously stored secret-based client."
			}
			return errorDescription
		}
		if (errorDescription) {
			return errorDescription
		}
		if (data && data.error && data.error.message) {
			return String(data.error.message)
		}
		if (data && data.error) {
			return String(data.error)
		}
		return fallbackErr || "Google authentication failed."
	}

	function fetchAccessToken(args, callback) {
		var ctx = currentAuthContext()
		var authCode = extractAuthorizationCode(args.authorizationCode)
		var existingAccount = args.accountId ? accountsStore.getAccount(args.accountId) : null
		if (!authCode) {
			handleError('Invalid Google Authorization Code', null)
			if (typeof callback === "function") {
				callback('Invalid Google Authorization Code')
			}
			return
		}
		var url = 'https://oauth2.googleapis.com/token'
		if (!ctx.pkceVerifier && !ctx.clientSecret) {
			handleError('Missing PKCE verifier. Start login from the widget and try again.', null)
			if (typeof callback === "function") {
				callback('Missing PKCE verifier. Start login from the widget and try again.')
			}
			return
		}
		var payload = {
			client_id: ctx.clientId,
			code: authCode,
			grant_type: 'authorization_code',
			redirect_uri: ctx.redirectUri,
		}
		if (ctx.clientSecret) {
			payload.client_secret = ctx.clientSecret
		}
		if (ctx.pkceVerifier) {
			payload.code_verifier = ctx.pkceVerifier
		}
		logger.debugJSON("fetchAccessToken.request", {
			accountId: args.accountId || "",
			clientIdSuffix: clientIdSuffix(ctx.clientId),
			redirectUri: ctx.redirectUri,
			usingPkce: !!ctx.pkceVerifier,
			hasClientSecret: !!ctx.clientSecret,
			existingAccountId: existingAccount && existingAccount.id ? existingAccount.id : "",
			existingAccountHasRefreshToken: !!(existingAccount && existingAccount.refreshToken),
		})
		Requests.post({
			url: url,
			data: payload,
		}, function(err, data, xhr) {
			var parsed = null
			if (data) {
				try {
					parsed = JSON.parse(data)
				} catch (e) {
					parsed = null
				}
			}
			logger.debugJSON("fetchAccessToken.responseSummary", {
				status: xhr ? xhr.status : 0,
				err: err || "",
				summary: summarizeTokenResponse(parsed, ctx, args.accountId, existingAccount),
			})
			if (err) {
				var requestError = describeAuthError(ctx, parsed, err)
				handleError(requestError, null)
				if (typeof callback === "function") {
					callback(requestError)
				}
				return
			}
			if (!parsed) {
				handleError('Error parsing /oauth2/v4/token data as JSON', null)
				if (typeof callback === "function") {
					callback('Error parsing token response.')
				}
				return
			}
			if (parsed && parsed.error) {
				var parsedError = describeAuthError(ctx, parsed, err)
				handleError(parsedError, null)
				if (typeof callback === "function") {
					callback(parsedError)
				}
				return
			}
			var canReuseRefreshToken = !!(existingAccount
				&& existingAccount.refreshToken
				&& !existingAccount.reauthRequired)
			if (!parsed.refresh_token && !canReuseRefreshToken) {
				logger.debugJSON("fetchAccessToken.missingRefreshToken", summarizeTokenResponse(parsed, ctx, args.accountId, existingAccount))
				var refreshTokenError = existingAccount && existingAccount.reauthRequired
					? "Google login completed, but no replacement refresh token was returned. Revoke the app's Google access and reconnect this account."
					: "Google login completed, but no refresh token was returned. Revoke the app's Google access and login again."
				handleError(refreshTokenError, null)
				if (typeof callback === "function") {
					callback(refreshTokenError)
				}
				return
			}

			// Ready
			updateAccessToken(parsed, args.accountId, function(updateErr) {
				if (typeof callback === "function") {
					callback(updateErr || null, updateErr ? null : parsed)
				}
			})
		})
	}

	function resolveLoginTargetAccount(accountId, callback) {
		var existingAccount = accountId ? accountsStore.getAccount(accountId) : null
		if (existingAccount) {
			callback({
				account: existingAccount,
				targetId: existingAccount.id,
				createdAccount: false,
				reusedDeadAccount: false,
			})
			return
		}
		accountsStore.findReusableAccount(function(reusableId) {
			if (reusableId) {
				callback({
					account: accountsStore.getAccount(reusableId),
					targetId: reusableId,
					createdAccount: false,
					reusedDeadAccount: true,
				})
				return
			}
			var created = accountsStore.addAccount({
				label: '',
				skipDefaultCalendarSelection: true,
				skipSerialize: true,
				skipSetActive: true,
			})
			callback({
				account: created,
				targetId: created.id,
				createdAccount: true,
				reusedDeadAccount: false,
			})
		})
	}

	function updateAccessToken(data, accountId, callback) {
		resolveLoginTargetAccount(accountId, function(target) {
			var account = target.account
			var patch = {
				sessionClientId: effectiveClientId,
				sessionClientSecret: effectiveClientSecret,
				sessionUsesPkce: !effectiveClientSecret,
				reauthRequired: false,
				reauthReason: '',
				accessToken: data.access_token,
				accessTokenType: data.token_type,
				accessTokenExpiresAt: Date.now() + data.expires_in * 1000,
				refreshToken: data.refresh_token || (account && account.refreshToken) || '',
			}
			if (target.reusedDeadAccount) {
				patch.label = ''
				patch.calendarList = []
				patch.calendarIdList = []
				patch.calendarSelectionInitialized = false
				patch.tasklistList = []
				patch.tasklistIdList = []
			}
			logger.debugJSON("updateAccessToken", {
				requestedAccountId: accountId || "",
				targetId: target.targetId,
				createdAccount: target.createdAccount,
				reusedDeadAccount: target.reusedDeadAccount,
				clientIdSuffix: clientIdSuffix(effectiveClientId),
				sessionUsesPkce: !effectiveClientSecret,
				hasAccessToken: !!data.access_token,
				hasRefreshToken: !!data.refresh_token,
				reusedExistingRefreshToken: !data.refresh_token && !!(account && account.refreshToken),
			})
			accountsStore.updateAccount(target.targetId, patch, function(updateErr) {
				if (updateErr) {
					if (target.createdAccount) {
						accountsStore.removeAccount(target.targetId)
					}
					var saveError = "Could not save Google refresh token. Check that Secret Service or KWallet is available, then login again."
					handleError(saveError, null)
					if (typeof callback === "function") {
						callback(updateErr)
					}
					return
				}
				accountsStore.setActiveAccountId(target.targetId)
				accountsStore.pruneReusableAccounts(target.targetId)
				newAccessToken()
				clearAuthorizationContext()
				if (typeof callback === "function") {
					callback(null, target.targetId)
				}
			})
		})
	}

	onNewAccessToken: Qt.callLater(updateData)

	function updateData(accountId) {
		updateCalendarList(accountId)
		updateTasklistList(accountId)
	}

	// callback (optional): called once the new list is stored, or on an error.
	function updateCalendarList(accountId, callback) {
		var done = typeof callback === "function" ? callback : function() {}
		var account = accountId ? accountsStore.getAccount(accountId) : activeAccount
		logger.debug('updateCalendarList', account ? account.id : null)
		if (!account) {
			return done()
		}
		withAccountToken(account.id, function(tokenErr, accessToken) {
			if (tokenErr) {
				handleError(tokenErr, null)
				return done()
			}
			fetchCalendarListInto(account.id, accessToken, done)
		})
	}

	function fetchCalendarListInto(accountId, accessToken, done) {
		fetchGCalCalendars({
			accessToken: accessToken,
		}, function(err, data, xhr) {
			if (err || data.error) {
				handleError(err, data)
				return done()
			}
			var account = accountsStore.getAccount(accountId)
			if (!account) {
				return done()
			}
			var label = accountsStore.deriveLabelFromCalendars(data.items)
			accountsStore.applyCalendarList(account.id, data.items, label && !account.label ? { label: label } : null, function() {
				done()
			})
		})
	}

	function fetchGCalCalendars(args, callback) {
		var url = 'https://www.googleapis.com/calendar/v3/users/me/calendarList'
		Requests.getJSON({
			url: url,
			headers: {
				"Authorization": "Bearer " + args.accessToken,
			}
		}, function(err, data, xhr) {
			if (!err && data && data.error) {
				return callback('fetchGCalCalendars error', data, xhr)
			}
			logger.debugJSON('fetchGCalCalendars.responseSummary', {
				status: xhr ? xhr.status : 0,
				err: err || "",
				count: data && data.items ? data.items.length : 0,
			})
			callback(err, data, xhr)
		})
	}

	function updateTasklistList(accountId) {
		var account = accountId ? accountsStore.getAccount(accountId) : activeAccount
		logger.debug('updateTasklistList', account ? account.id : null)
		if (!account) {
			return
		}
		// A token error is shown by updateCalendarList already.
		withAccountToken(account.id, function(tokenErr, accessToken) {
			if (tokenErr) {
				return
			}
			fetchGoogleTasklistList({
				accessToken: accessToken,
			}, function(err, data, xhr) {
				if (err || data.error) {
					logger.log('updateTasklistList error', err)
					return
				}
				accountsStore.updateAccount(account.id, { tasklistList: data.items })
			})
		})
	}

	function fetchGoogleTasklistList(args, callback) {
		var url = 'https://www.googleapis.com/tasks/v1/users/@me/lists'
		Requests.getJSON({
			url: url,
			headers: {
				"Authorization": "Bearer " + args.accessToken,
			}
		}, function(err, data, xhr) {
			if (!err && data && data.error) {
				return callback('fetchGoogleTasklistList error', data, xhr)
			}
			logger.debugJSON('fetchGoogleTasklistList.responseSummary', {
				status: xhr ? xhr.status : 0,
				err: err || "",
				count: data && data.items ? data.items.length : 0,
			})
			callback(err, data, xhr)
		})
	}

	function logout(accountId) {
		var targetId = accountId || activeAccountId
		if (!targetId) {
			return
		}
		accountsStore.removeAccount(targetId)

		var lastCalendarId = readConfig("agendaNewEventLastCalendarId", "")
		if (lastCalendarId.indexOf(targetId + '::') === 0) {
			writeConfig("agendaNewEventLastCalendarId", "")
		}
		sessionReset()
	}

	//--- Access tokens aren't saved, so the settings refresh them with the account's refresh token.
	Component {
		id: apiSessionComponent
		GoogleApiSession {}
	}
	property var apiSessions: ({})
	// The accounts store, for managers that change an account (eg: its task lists).
	readonly property var store: accountsStore
	// The account's API session (GoogleApiSession), made once.
	function apiSessionFor(accountId) {
		var apiSession = apiSessions[accountId]
		if (!apiSession) {
			apiSession = apiSessionComponent.createObject(session, {
				accountsStore: accountsStore,
				accountId: accountId,
			})
			apiSessions[accountId] = apiSession
		}
		return apiSession
	}
	function withAccountToken(accountId, callback) {
		var apiSession = apiSessionFor(accountId)
		apiSession.checkAccessToken(function(err) {
			var account = accountsStore.getAccount(accountId)
			if (!err && !(account && account.accessToken)) {
				err = i18n("Not signed in to this Google account. Sign in again.")
			}
			callback(err || null, err ? '' : account.accessToken)
		})
	}

	//--- Editing a calendar: its name and color
	// The user owns it and it isn't their main calendar (which is named after them).
	function canRenameCalendar(calendar) {
		return !!calendar && calendar.accessRole === 'owner' && !calendar.primary
	}

	// Black or white text, whichever reads better on the color.
	function foregroundColorFor(hex) {
		var m = /^#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(hex || '')
		if (!m) {
			return '#ffffff'
		}
		var luma = 0.299 * parseInt(m[1], 16) + 0.587 * parseInt(m[2], 16) + 0.114 * parseInt(m[3], 16)
		return luma > 160 ? '#1d1d1d' : '#ffffff'
	}

	// Google APIs take PATCH as a POST with an override header (QML's XMLHttpRequest may not
	// send a PATCH body). Only the given fields change; null clears one.
	function patchJSON(url, accessToken, data, callback) {
		Requests.postJSON({
			url: url,
			headers: {
				"Authorization": "Bearer " + accessToken,
				"X-HTTP-Method-Override": "PATCH",
			},
			data: data,
		}, function(err, responseData, xhr) {
			if (!err && responseData && responseData.error) {
				err = 'patch error'
			}
			logger.debugJSON('patchJSON.responseSummary', {
				status: xhr ? xhr.status : 0,
				err: err ? String(err) : "",
			})
			callback(err, responseData, xhr)
		})
	}

	// https://developers.google.com/calendar/api/v3/reference/calendarList/patch
	function patchCalendarListEntry(accessToken, calendarId, fields, callback) {
		var url = 'https://www.googleapis.com/calendar/v3/users/me/calendarList/'
		url += encodeURIComponent(calendarId)
		url += '?colorRgbFormat=true'
		patchJSON(url, accessToken, fields, callback)
	}

	// https://developers.google.com/calendar/api/v3/reference/calendars/patch
	function patchCalendar(accessToken, calendarId, fields, callback) {
		var url = 'https://www.googleapis.com/calendar/v3/calendars/'
		url += encodeURIComponent(calendarId)
		patchJSON(url, accessToken, fields, callback)
	}

	// The requests needed to save the dialog's { name, color } for a calendar list entry.
	// Unchanged values send nothing. Returns [{ kind: 'calendar' | 'calendarList', fields }].
	function calendarChangeRequests(calendar, changes) {
		var requests = []
		var listFields = {}
		var currentName = calendar.summaryOverride || calendar.summary || ''
		var name = typeof changes.name === 'string' ? changes.name.trim() : currentName
		if (name && name !== currentName) {
			if (canRenameCalendar(calendar)) {
				requests.push({ kind: 'calendar', fields: { summary: name } })
				if (calendar.summaryOverride) {
					listFields.summaryOverride = null
				}
			} else if (name === calendar.summary) {
				listFields.summaryOverride = null
			} else {
				listFields.summaryOverride = name
			}
		} else if (!name && calendar.summaryOverride) {
			// An emptied field goes back to the calendar's own name.
			listFields.summaryOverride = null
		}
		var color = String(changes.color || '').toLowerCase()
		if (color && color !== String(calendar.backgroundColor || '').toLowerCase()) {
			listFields.backgroundColor = color
			listFields.foregroundColor = foregroundColorFor(color)
		}
		if (Object.keys(listFields).length) {
			requests.push({ kind: 'calendarList', fields: listFields })
		}
		return requests
	}

	// changes: { name, color }. callback(err): err is a message for the user.
	function saveCalendarChanges(accountId, calendar, changes, callback) {
		var requests = calendarChangeRequests(calendar, changes)
		if (!requests.length) {
			callback(null)
			return
		}
		withAccountToken(accountId, function(tokenErr, accessToken) {
			if (tokenErr) {
				callback(String(tokenErr))
				return
			}
			var i = 0
			function next(err, data) {
				if (err) {
					var message = data && data.error && data.error.message
						? data.error.message + (data.error.code ? ' (' + data.error.code + ')' : '')
						: String(err)
					callback(i18n("Could not save the calendar: %1", message))
					// Some requests may have gone through.
					updateCalendarList(accountId)
					return
				}
				if (i >= requests.length) {
					updateCalendarList(accountId, function() {
						callback(null)
					})
					return
				}
				var request = requests[i++]
				if (request.kind === 'calendar') {
					patchCalendar(accessToken, calendar.id, request.fields, next)
				} else {
					patchCalendarListEntry(accessToken, calendar.id, request.fields, next)
				}
			}
			next(null)
		})
	}

	// https://developers.google.com/calendar/v3/errors
	function handleError(err, data) {
		if (data && data.error && data.error_description) {
			var errorMessage = '' + data.error + ' (' + data.error_description + ')'
			session.error(errorMessage)
			clearAuthorizationContext()
		} else if (data && data.error && data.error.message && typeof data.error.code !== "undefined") {
			var errorMessage = '' + data.error.message + ' (' + data.error.code + ')'
			session.error(errorMessage)
			clearAuthorizationContext()
		} else if (err) {
			session.error(err)
			clearAuthorizationContext()
		}
	}
}
