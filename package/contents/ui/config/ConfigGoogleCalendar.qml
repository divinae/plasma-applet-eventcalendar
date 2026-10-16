import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import ".."
import "../lib"
import "../lib/Requests.js" as Requests
import "../lib/ColorUtil.js" as ColorUtil
import "../Shared.js" as Shared

ConfigPage {
	id: page

	SystemPalette { id: syspal }

	function markDirty() {
		if (typeof kcm !== "undefined") {
			kcm.needsSave = true
		}
	}

	function save() {
		if (typeof kcm !== "undefined") {
			kcm.needsSave = false
		}
	}

	readonly property color readablePositiveTextColor: Qt.tint(Kirigami.Theme.textColor, ColorUtil.setAlpha(Kirigami.Theme.positiveTextColor, 0.5))
	readonly property color readableNegativeTextColor: Qt.tint(Kirigami.Theme.textColor, ColorUtil.setAlpha(Kirigami.Theme.negativeTextColor, 0.5))

	function localFilePath(url) {
		var path = String(url)
		return path.indexOf("file://") === 0 ? path.slice(7) : path
	}

	function sortByKey(key, a, b){
		if (typeof a[key] === "string") {
			return a[key].toLowerCase().localeCompare(b[key].toLowerCase())
		} else if (typeof a[key] === "number") {
			return a[key] - b[key]
		} else {
			return 0
		}
	}
	function sortArr(arr, predicate) {
		if (typeof predicate === "string") { // predicate is a key
			predicate = sortByKey.bind(null, predicate)
		}
		return arr.concat().sort(predicate)
	}

	function accountLabel(account, index) {
		if (!account) {
			return i18n("Google Account")
		}
		return account.label || i18n("Google Account %1", index + 1)
	}

	//--- Calendar / task list selection, per account
	function primaryCalendarId(account) {
		var list = Shared.toArray(account.calendarList)
		for (var i = 0; i < list.length; i++) {
			if (list[i].primary) {
				return list[i].id
			}
		}
		return ''
	}
	function isCalendarShown(account, calendar) {
		var ids = Shared.toArray(account.calendarIdList)
		return ids.indexOf(calendar.id) >= 0 || (calendar.primary === true && ids.indexOf('primary') >= 0)
	}
	function setCalendarShown(account, calendar, shown) {
		// The saved list may say 'primary' instead of the primary calendar's id.
		var primaryId = primaryCalendarId(account)
		var ids = Shared.toArray(account.calendarIdList).map(function(id) {
			return id === 'primary' && primaryId ? primaryId : id
		}).filter(function(id) {
			return id !== calendar.id
		})
		if (shown) {
			ids.push(calendar.id)
		}
		googleLoginManager.setCalendarIdList(ids, account.id)
		markDirty()
	}
	function isTasklistShown(account, tasklist) {
		return Shared.toArray(account.tasklistIdList).indexOf(tasklist.id) >= 0
	}
	function setTasklistShown(account, tasklist, shown) {
		var ids = Shared.toArray(account.tasklistIdList).filter(function(id) {
			return id !== tasklist.id
		})
		if (shown) {
			ids.push(tasklist.id)
		}
		googleLoginManager.setTasklistIdList(ids, account.id)
		markDirty()
	}

	ExecUtil { id: callbackListener }

	property bool autoLoginInProgress: false
	property bool autoLoginCancelled: false
	property int loginAttempt: 0 // Callbacks of older (replaced / cancelled) sign-ins are ignored
	readonly property bool localRedirect: googleLoginManager.redirectMode === "local"
	readonly property bool showDebug: page.configBridge.read("debugging", false)

	function extractJson(text) {
		var start = text.indexOf('{')
		var end = text.lastIndexOf('}')
		if (start >= 0 && end > start) {
			return text.slice(start, end + 1)
		}
		return ""
	}
	function parseTokenInput(text) {
		if (!text) {
			return null
		}
		var trimmed = text.trim()
		if (!trimmed || trimmed[0] !== '{') {
			return null
		}
		var parsed = null
		try {
			parsed = JSON.parse(trimmed)
		} catch (e) {
			return null
		}
		if (!parsed || !parsed.access_token) {
			return null
		}
		if (!parsed.expires_in) {
			parsed.expires_in = 3600
		}
		if (!parsed.token_type) {
			parsed.token_type = "Bearer"
		}
		return parsed
	}

	function startAutoLogin(accountId, openBrowser) {
		if (autoLoginInProgress) {
			return
		}
		if (openBrowser === undefined) {
			openBrowser = true
		}
		autoLoginCancelled = false
		autoLoginInProgress = true
		var attempt = ++loginAttempt
		googleLoginManager.prepareAuthorization()
		googleLoginManager.maybeUseLegacyForLocal()
		var authContext = googleLoginManager.currentAuthContext()
		messageWidget.info(localRedirect
			? i18n("Waiting for browser callback...")
			: i18n("Waiting for the helper page to send the code..."))
		var cmd = [
			'python3',
			localFilePath(Qt.resolvedUrl("../../scripts/google_redirect.py")),
			'--client_id',
			authContext.clientId,
			'--listen_port',
			'53682',
			'--redirect_uri',
			authContext.redirectUri,
		]
		if (authContext.clientSecret) {
			cmd.push('--client_secret')
			cmd.push(authContext.clientSecret)
		}
		if (authContext.pkceVerifier) {
			cmd.push('--code_verifier')
			cmd.push(authContext.pkceVerifier)
		}
		if (authContext.state) {
			cmd.push('--state')
			cmd.push(authContext.state)
		}
		debugOutput.text = "Waiting for the browser sign-in…\n"
		// Don't log cmd or stdout: they contain the client secret, PKCE verifier and tokens.
		callbackListener.exec(cmd, function(cmd, exitCode, exitStatus, stdout, stderr) {
			if (attempt !== loginAttempt) {
				return // Replaced by a newer sign-in
			}
			if (autoLoginCancelled) {
				autoLoginInProgress = false
				return
			}
			autoLoginInProgress = false
			// Never show stdout: it has the tokens.
			debugOutput.text += "Exit: " + exitCode + "\nStderr: " + stderr + "\n"
			if (exitCode === 2) {
				messageWidget.err(i18n("Sign-in timed out. Try again."))
				return
			}
			if (exitCode !== 0) {
				console.error('google_redirect.py failed:', exitCode, stderr)
				messageWidget.err(i18n("Auto login failed. See logs for details."))
				return
			}
			var payload = extractJson(stdout || "")
			if (!payload) {
				messageWidget.err(i18n("Auto login failed: no token data received."))
				return
			}
			var data = null
			try {
				data = JSON.parse(payload)
			} catch (e) {
				messageWidget.err(i18n("Auto login failed: invalid token data."))
				return
			}
			if (data.error) {
				messageWidget.err(i18n("Auto login failed: %1", data.error))
				return
			}
			authorizationCodeInput.text = ""
			googleLoginManager.updateAccessToken(data, accountId)
			messageWidget.success(i18n("Login complete."))
			googleLoginManager.updateCalendarList()
		})
		if (openBrowser) {
			Qt.openUrlExternally(googleLoginManager.authorizationCodeUrl)
		}
	}

	GoogleLoginManager {
		id: googleLoginManager
		configBridge: page.configBridge
		redirectMode: "local"

		onError: function(err) {
			messageWidget.err(err)
		}
	}
	MessageWidget {
		id: messageWidget
	}
	Label {
		visible: !googleLoginManager.isLoggedIn
		Layout.fillWidth: true
		wrapMode: Text.Wrap
		opacity: 0.7
		text: i18n("Sign in to show your Google calendars and task lists. Your browser opens to sign in; when access is granted the widget picks it up automatically.")
	}

	// One section per account: its calendars and task lists. All accounts sync at the same time.
	Repeater {
		model: googleLoginManager.accounts ? googleLoginManager.accounts.length : 0

		ColumnLayout {
			id: accountSection
			readonly property var account: googleLoginManager.accounts[index] || null
			// Primary calendar first, then by name.
			readonly property var calendars: account ? page.sortArr(Shared.toArray(account.calendarList), function(a, b) {
				if (!!a.primary !== !!b.primary) {
					return a.primary ? -1 : 1
				}
				return (a.summary || '').toLowerCase().localeCompare((b.summary || '').toLowerCase())
			}) : []
			readonly property var tasklists: account ? page.sortArr(Shared.toArray(account.tasklistList), "title") : []
			readonly property bool needsRelog: googleLoginManager.accountNeedsRelog(account)
			property bool confirmRemove: false
			Layout.fillWidth: true
			Layout.topMargin: index > 0 ? Kirigami.Units.largeSpacing : 0
			spacing: Kirigami.Units.smallSpacing

			Kirigami.Separator {
				visible: index > 0
				Layout.fillWidth: true
				Layout.bottomMargin: Kirigami.Units.smallSpacing
			}

			// Account: name, refresh, sign in again, remove
			RowLayout {
				Layout.fillWidth: true
				spacing: Kirigami.Units.smallSpacing
				Kirigami.Icon {
					source: "user-identity"
					Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
					Layout.preferredHeight: Layout.preferredWidth
				}
				Kirigami.Heading {
					Layout.fillWidth: true
					level: 4
					elide: Text.ElideRight
					text: page.accountLabel(accountSection.account, index)
				}
				Button {
					visible: accountSection.needsRelog
					icon.name: "view-refresh"
					text: i18n("Sign In Again")
					enabled: !page.autoLoginInProgress
					onClicked: page.startAutoLogin(accountSection.account.id)
				}
				ToolButton {
					icon.name: "view-refresh"
					display: AbstractButton.IconOnly
					text: i18n("Reload calendars and task lists")
					onClicked: googleLoginManager.updateData(accountSection.account.id)
					ToolTip.text: text
					ToolTip.visible: hovered
				}
				ToolButton {
					visible: !accountSection.confirmRemove
					icon.name: "list-remove-user"
					display: AbstractButton.IconOnly
					text: i18n("Remove Account")
					onClicked: accountSection.confirmRemove = true
					ToolTip.text: text
					ToolTip.visible: hovered
				}
				Button {
					visible: accountSection.confirmRemove
					icon.name: "edit-delete"
					text: i18n("Remove")
					onClicked: googleLoginManager.removeAccount(accountSection.account.id)
				}
				Button {
					visible: accountSection.confirmRemove
					text: i18n("Cancel")
					onClicked: accountSection.confirmRemove = false
				}
			}
			MessageWidget {
				visible: accountSection.needsRelog
				closeButtonVisible: false
				messageType: MessageWidget.MessageType.Warning
				text: i18n("The widget was updated. Sign in again to keep this account in sync.")
			}

			// Calendars
			Label {
				Layout.topMargin: Kirigami.Units.smallSpacing
				text: i18n("Calendars")
				font.weight: Font.DemiBold
				opacity: 0.7
			}
			Label {
				visible: accountSection.calendars.length === 0
				text: i18n("No calendars loaded yet. Use the reload button.")
				opacity: 0.6
			}
			Repeater {
				model: accountSection.calendars.length
				SelectionRow {
					readonly property var calendar: accountSection.calendars[index]
					Layout.fillWidth: true
					name: calendar ? calendar.summary : ""
					swatchColor: calendar ? calendar.backgroundColor : "transparent"
					readOnly: calendar ? calendar.accessRole === "reader" : false
					checked: calendar ? page.isCalendarShown(accountSection.account, calendar) : false
					onToggled: page.setCalendarShown(accountSection.account, calendar, checked)
				}
			}

			// Task lists
			Label {
				visible: accountSection.tasklists.length > 0
				Layout.topMargin: Kirigami.Units.smallSpacing
				text: i18n("Task Lists")
				font.weight: Font.DemiBold
				opacity: 0.7
			}
			Repeater {
				model: accountSection.tasklists.length
				SelectionRow {
					readonly property var tasklist: accountSection.tasklists[index]
					Layout.fillWidth: true
					name: tasklist ? tasklist.title : ""
					iconSource: Qt.resolvedUrl("../../icons/google_tasks_96px.png")
					checked: tasklist ? page.isTasklistShown(accountSection.account, tasklist) : false
					onToggled: page.setTasklistShown(accountSection.account, tasklist, checked)
				}
			}
		}
	}

	RowLayout {
		Layout.topMargin: Kirigami.Units.largeSpacing
		Button {
			icon.name: googleLoginManager.isLoggedIn ? "list-add-user" : "go-next"
			text: googleLoginManager.isLoggedIn ? i18n("Add Account…") : i18n("Sign in with Google…")
			enabled: !autoLoginInProgress
			onClicked: {
				authorizationCodeInput.text = ""
				startAutoLogin("")
			}
		}
		BusyIndicator {
			visible: autoLoginInProgress
			running: visible
			Layout.preferredHeight: Kirigami.Units.iconSizes.medium
		}
	}

	// Advanced sign-in (custom OAuth client, manual code): collapsed by default.
	property bool showAdvancedSignIn: false
	ToolButton {
		Layout.topMargin: Kirigami.Units.largeSpacing
		icon.name: page.showAdvancedSignIn ? "arrow-down" : "arrow-right"
		text: i18n("Advanced sign-in options")
		onClicked: page.showAdvancedSignIn = !page.showAdvancedSignIn
	}
	ColumnLayout {
	id: advancedSignIn
	visible: page.showAdvancedSignIn
	Layout.fillWidth: true
	Layout.leftMargin: Kirigami.Units.largeSpacing

	HeaderText {
		text: i18n("Client Credentials")
		level: 3
	}
	ColumnLayout {
		Layout.fillWidth: true
		property bool credentialsReady: false
		Component.onCompleted: credentialsReady = true

		MessageWidget {
			messageType: MessageWidget.MessageType.Warning
			closeButtonVisible: false
			text: googleLoginManager.normalizedClientValue(page.configBridge.read("customClientId", ""))
				? ""
				: i18n("The built-in Google OAuth client is often blocked. Provide your own client ID (and secret if required) to enable Google sync.")
		}
		Label {
			Layout.fillWidth: true
			text: i18n("Leave these empty to use the default credentials. Custom credentials require a Google Cloud OAuth client with the redirect URI set to %1.", googleLoginManager.redirectUri)
			color: readableNegativeTextColor
			wrapMode: Text.Wrap
		}
		ConfigCheckBox {
			id: useDesktopClientToggle
			configKey: "useDesktopClient"
			visible: !googleLoginManager.normalizedClientValue(page.configBridge.read("customClientId", ""))
			text: i18n("Try desktop built-in client (no secret)")
			onCheckedChanged: {
				if (!credentialsReady) {
					return
				}
				googleLoginManager.refreshClientCredentials()
			}
		}
		RowLayout {
			Layout.fillWidth: true
			Label {
				text: i18n("Client ID")
			}
			ConfigString {
				configKey: "customClientId"
				Layout.fillWidth: true
				placeholderText: i18n("Optional")
				defaultValue: ""
				onTextChanged: {
					markDirty()
					googleLoginManager.refreshClientCredentials()
				}
			}
		}
		RowLayout {
			Layout.fillWidth: true
			Label {
				text: i18n("Client Secret")
			}
			ConfigString {
				configKey: "customClientSecret"
				Layout.fillWidth: true
				placeholderText: i18n("Optional")
				defaultValue: ""
				echoMode: TextInput.Password
				onTextChanged: {
					markDirty()
					googleLoginManager.refreshClientCredentials()
				}
			}
		}
	}

	HeaderText {
		text: i18n("Manual Sign-in")
		level: 3
	}
	Label {
		Layout.fillWidth: true
		color: readableNegativeTextColor
		wrapMode: Text.Wrap
		text: i18n("Callback: Localhost (auto capture). Helper page is shown below as a backup.")
	}

	ColumnLayout {
		Label {
			Layout.fillWidth: true
			text: googleLoginManager.isLoggedIn
				? i18n("Add another Google account")
				: i18n("To sync with Google Calendar")
			color: readableNegativeTextColor
			wrapMode: Text.Wrap
		}
		RowLayout {
			Layout.fillWidth: true
			Button {
				text: googleLoginManager.isLoggedIn ? i18n("Login (Auto) - Add Account") : i18n("Login (Auto)")
				enabled: !autoLoginInProgress
				onClicked: {
					authorizationCodeInput.text = ""
					startAutoLogin("")
				}
			}
		}
		LinkText {
			Layout.fillWidth: true
			text: localRedirect
				? i18n("Click Login (Auto) to open <a href=\"%1\">%2</a>. After you grant access, the browser redirects to a localhost URL. If auto-capture succeeds you can ignore the field below; otherwise copy the full URL (or just the code) and paste it.", googleLoginManager.authorizationCodeUrl, 'https://accounts.google.com/...')
				: i18n("Click Login (Auto) to open <a href=\"%1\">%2</a>. After you grant access, the browser redirects to the helper page and will try to send the code back automatically. If it fails, copy the code and paste it below.", googleLoginManager.authorizationCodeUrl, 'https://accounts.google.com/...')
			color: readableNegativeTextColor
			wrapMode: Text.Wrap
			onLinkActivated: function(link) {
				googleLoginManager.prepareAuthorization()
				googleLoginManager.maybeUseLegacyForLocal()
				Qt.openUrlExternally(googleLoginManager.authorizationCodeUrl)
			}

			// Tooltip
			// QQC2.ToolTip.visible: !!hoveredLink
			// QQC2.ToolTip.text: googleLoginManager.authorizationCodeUrl

			// ContextMenu
			MouseArea {
				id: contextMenuArea
				anchors.fill: parent
				acceptedButtons: Qt.RightButton
				onClicked: function(mouse) {
					if (mouse.button === Qt.RightButton) {
						var pos = contextMenuArea.mapToItem(page, mouse.x, mouse.y)
						contextMenu.popup(pos.x, pos.y)
					}
				}
				onPressAndHold: function(mouse) {
					if (mouse.source === Qt.MouseEventNotSynthesized) {
						var pos = contextMenuArea.mapToItem(page, mouse.x, mouse.y)
						contextMenu.popup(pos.x, pos.y)
					}
				}

				Menu {
					id: contextMenu
					parent: page
					MenuItem {
						text: i18n("Copy Link")
						onTriggered: clipboardHelper.copyText(googleLoginManager.authorizationCodeUrl)
					}
				}

				TextEdit {
					id: clipboardHelper
					visible: false
					function copyText(text) {
						clipboardHelper.text = text
						clipboardHelper.selectAll()
						clipboardHelper.copy()
					}
				}
			}
		}
		LinkText {
			Layout.fillWidth: true
			text: localRedirect
				? i18n("Helper page (optional): <a href=\"%1\">%1</a>", googleLoginManager.hostedRedirectUri)
				: i18n("Helper page: <a href=\"%1\">%1</a>", googleLoginManager.redirectUri)
			color: readableNegativeTextColor
			wrapMode: Text.Wrap
		}
		Label {
			Layout.fillWidth: true
			color: readableNegativeTextColor
			wrapMode: Text.Wrap
			text: i18n("If your browser shows a connection error, that's expected. Copy the URL from the address bar anyway and paste it below.")
			visible: localRedirect
		}
		Label {
			Layout.fillWidth: true
			color: readableNegativeTextColor
			wrapMode: Text.Wrap
			text: localRedirect
				? i18n("Tip: If auto-capture works, you do not need to paste anything.")
				: i18n("Tip: If auto-capture fails, copy the code from the helper page and paste it below.")
			visible: true
		}
		RowLayout {
			TextField {
				id: authorizationCodeInput
				Layout.fillWidth: true

				placeholderText: i18n("Paste the authorization code or redirect URL here")
				text: ""
			}
				Button {
					text: googleLoginManager.isLoggedIn ? i18n("Add Account") : i18n("Submit")
					enabled: !autoLoginInProgress || !localRedirect || !!authorizationCodeInput.text
					onClicked: {
						if (authorizationCodeInput.text) {
							if (autoLoginInProgress) {
								autoLoginCancelled = true
								loginAttempt++ // Its listener callback must not apply an old code
								autoLoginInProgress = false
							}
							var tokenData = parseTokenInput(authorizationCodeInput.text)
							if (tokenData) {
								googleLoginManager.updateAccessToken(tokenData)
								authorizationCodeInput.text = ""
								messageWidget.success(i18n("Token accepted."))
								return
							}
							googleLoginManager.refreshClientCredentials()
							googleLoginManager.fetchAccessToken({
								authorizationCode: authorizationCodeInput.text,
							})
					} else {
						startAutoLogin("")
					}
				}
			}
				Button {
					visible: googleLoginManager.isLoggedIn
					text: i18n("Update Selected")
					enabled: !autoLoginInProgress || !localRedirect || !!authorizationCodeInput.text
					onClicked: {
						if (authorizationCodeInput.text) {
							if (autoLoginInProgress) {
								autoLoginCancelled = true
								loginAttempt++ // Its listener callback must not apply an old code
								autoLoginInProgress = false
							}
							var tokenData = parseTokenInput(authorizationCodeInput.text)
							if (tokenData) {
								googleLoginManager.updateAccessToken(tokenData, googleLoginManager.activeAccountId)
								authorizationCodeInput.text = ""
								messageWidget.success(i18n("Token accepted."))
								return
							}
							googleLoginManager.refreshClientCredentials()
							googleLoginManager.fetchAccessToken({
								authorizationCode: authorizationCodeInput.text,
								accountId: googleLoginManager.activeAccountId,
						})
					} else {
						startAutoLogin(googleLoginManager.activeAccountId)
					}
				}
			}
		}
	}

	} // advancedSignIn

	HeaderText {
		text: i18n("Options")
		visible: googleLoginManager.isLoggedIn
	}

	ColumnLayout {
		Layout.fillWidth: true
		visible: googleLoginManager.isLoggedIn

		ConfigCheckBox {
			configKey: 'googleHideGoalsDesc'
			text: i18n("Hide \"This event was added from Goals in Google Calendar\" description")
			onClicked: markDirty()
		}
	}

	HeaderText {
		text: "Debug Info (Temporary)"
		visible: showDebug
	}
	ColumnLayout {
		Layout.fillWidth: true
		visible: showDebug
		RowLayout {
			Button {
				text: "Test Echo"
				onClicked: {
					var cmd = ['echo', 'Hello World']
					debugOutput.text = "Running: echo Hello World\n"
					callbackListener.exec(cmd, function(c, code, status, out, err) {
						debugOutput.text += "Result: " + out + " (Code: " + code + ")\n"
					})
				}
			}
			Button {
				text: "Show Python Path"
				onClicked: {
					var path = localFilePath(Qt.resolvedUrl("../../scripts/google_redirect.py"))
					debugOutput.text = "Script Path: " + path + "\n"
					var cmd = ['python3', '--version']
					callbackListener.exec(cmd, function(c, code, status, out, err) {
						debugOutput.text += "Python Version: " + out + " " + err + "\n"
					})
				}
			}
		}
		TextArea {
			id: debugOutput
			Layout.fillWidth: true
			implicitHeight: 200
			readOnly: true
			text: "Debug logs will appear here..."
			background: Rectangle {
				color: syspal.base
				border.color: syspal.mid
			}
		}
	}

	Component.onCompleted: {
		if (page.cfg_googleRedirectMode !== "local") {
			page.configBridge.write("googleRedirectMode", "local")
		}
	}
}
