import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kirigamiaddons.formcard as FormCard

import ".."
import "../lib"
import "../lib/Requests.js" as Requests
import "../lib/ColorUtil.js" as ColorUtil
import "../Shared.js" as Shared
import "../code/GooglePalette.js" as GooglePalette

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
	// Configuration problem with the OAuth client (eg: a Web client without its secret), checked
	// against what's typed in the Client ID / Secret fields.
	readonly property string authConfigurationMessage: credentialAuthConfigurationMessage()
	function credentialAuthConfigurationMessage() {
		var customId = googleLoginManager.normalizedClientValue(customClientIdInput.text)
		var customSecret = googleLoginManager.normalizedClientValue(customClientSecretInput.text)
		var latestId = googleLoginManager.normalizedClientValue(page.configBridge.read("latestClientId", ""))
		var latestSecret = googleLoginManager.normalizedClientValue(page.configBridge.read("latestClientSecret", ""))
		var clientId = customId ? customId : (!useDesktopClientToggle.checked && latestId ? latestId : googleLoginManager.defaultClientId)
		var clientSecret = customId ? customSecret : (!useDesktopClientToggle.checked && latestId ? latestSecret : "")
		return googleLoginManager.authConfigurationErrorFor(clientId, clientSecret)
	}

	function syncCredentialInputs() {
		page.configBridge.write("customClientId", customClientIdInput.text)
		page.configBridge.write("customClientSecret", customClientSecretInput.text)
		googleLoginManager.refreshClientCredentials()
	}

	// Pasted authorization code or redirect URL. accountId: re-authorize that account ("" = new).
	function submitAuthorization(accountId) {
		if (!authorizationCodeInput.text) {
			startAutoLogin(accountId || "")
			return
		}
		if (autoLoginInProgress) {
			autoLoginCancelled = true
			loginAttempt++ // Its listener callback must not apply an old code
			autoLoginInProgress = false
		}
		syncCredentialInputs()
		googleLoginManager.fetchAccessToken({
			authorizationCode: authorizationCodeInput.text,
			accountId: accountId || "",
		}, function(err) {
			if (err) {
				messageWidget.err(i18n("Login failed: %1", err))
				return
			}
			authorizationCodeInput.text = ""
			messageWidget.success(i18n("Login complete."))
		})
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
		try {
			syncCredentialInputs()
			googleLoginManager.prepareAuthorization()
		} catch (e) {
			autoLoginInProgress = false
			messageWidget.err(i18n("Could not prepare Google login: %1", String(e)))
			return
		}
		var authContext = googleLoginManager.currentAuthContext()
		messageWidget.info(localRedirect
			? i18n("Waiting for browser callback...")
			: i18n("Waiting for the helper page to send the code..."))
		// Only the port and the one-time state: the client secret and PKCE verifier stay in the
		// widget (argv is visible to other processes), which exchanges the code itself.
		var cmd = [
			'python3',
			localFilePath(Qt.resolvedUrl("../../scripts/google_redirect.py")),
			'--listen_port',
			'53682',
			'--state',
			authContext.state,
		]
		debugOutput.text = "Waiting for the browser sign-in…\n"
		callbackListener.execArgv(cmd, function(cmd, exitCode, exitStatus, stdout, stderr) {
			if (attempt !== loginAttempt) {
				return // Replaced by a newer sign-in
			}
			if (autoLoginCancelled) {
				autoLoginInProgress = false
				return
			}
			autoLoginInProgress = false
			// Never show stdout: it has the authorization code.
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
			var data = null
			try {
				data = payload ? JSON.parse(payload) : null
			} catch (e) {
				data = null
			}
			if (!data) {
				messageWidget.err(i18n("Auto login failed: invalid callback data."))
				return
			}
			if (data.error) {
				messageWidget.err(i18n("Auto login failed: %1", data.error))
				return
			}
			if (!data.authorization_code) {
				messageWidget.err(i18n("Auto login failed: authorization code missing."))
				return
			}
			authorizationCodeInput.text = ""
			googleLoginManager.fetchAccessToken({
				authorizationCode: data.authorization_code,
				accountId: accountId,
			}, function(err) {
				if (err) {
					messageWidget.err(i18n("Auto login failed: %1", err))
					return
				}
				messageWidget.success(i18n("Login complete."))
			})
		})
		if (openBrowser && !Shared.openExternalUrl(googleLoginManager.authorizationCodeUrl)) {
			messageWidget.err(i18n("The desktop could not open the browser automatically. Use the login link in Advanced sign-in options instead."))
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
	CalendarEditDialog {
		id: calendarEditDialog
		loginManager: googleLoginManager
		// The widget refetches its events (new colors) once the settings are applied.
		onSaved: page.markDirty()
	}

	// Advanced sign-in (custom OAuth client, manual code): collapsed by default.
	property bool showAdvancedSignIn: false

	ColumnLayout {
		Layout.fillWidth: true
		spacing: 0

		MessageWidget {
			id: messageWidget
			Layout.fillWidth: true
			Layout.leftMargin: Kirigami.Units.largeSpacing
			Layout.rightMargin: Kirigami.Units.largeSpacing
		}

		FormCard.FormSectionText {
			visible: !googleLoginManager.isLoggedIn
			text: i18n("Sign in to show your Google calendars and task lists. Your browser opens to sign in; when access is granted the widget picks it up automatically.")
		}

		// One card per account: its calendars and task lists. All accounts sync at the same time.
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
					return (a.summaryOverride || a.summary || '').toLowerCase().localeCompare((b.summaryOverride || b.summary || '').toLowerCase())
				}) : []
				readonly property var tasklists: account ? page.sortArr(Shared.toArray(account.tasklistList), "title") : []
				readonly property bool needsRelog: googleLoginManager.accountNeedsRelog(account)
				property bool confirmRemove: false
				Layout.fillWidth: true
				spacing: 0

				// Account name, with its actions on the right.
				FormCard.FormHeader {
					title: page.accountLabel(accountSection.account, index)
					trailing: RowLayout {
						spacing: Kirigami.Units.smallSpacing
						Button {
							visible: accountSection.needsRelog
							icon.name: "view-refresh"
							text: i18n("Sign In Again")
							enabled: !page.autoLoginInProgress
							onClicked: page.startAutoLogin(accountSection.account.id)
						}
						ToolButton {
							visible: !accountSection.confirmRemove
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
				}

				FormCard.FormCard {
					FormCard.AbstractFormDelegate {
						visible: accountSection.needsRelog
						background: null
						contentItem: Kirigami.InlineMessage {
							visible: true
							type: Kirigami.MessageType.Warning
							text: accountSection.account && accountSection.account.reauthRequired
								? i18n("Google access for this account expired or was revoked. Sign in again to reconnect it (the account and its settings are kept).")
								: i18n("The widget was updated. Sign in again to keep this account in sync.")
						}
					}

					// Calendars
					FormCard.FormTextDelegate {
						text: i18n("Calendars")
						font.weight: Font.DemiBold
					}
					FormCard.FormTextDelegate {
						visible: accountSection.calendars.length === 0
						text: i18n("No calendars loaded yet. Use the reload button.")
						textItem.opacity: 0.6
					}
					Repeater {
						model: accountSection.calendars.length
						SelectionRow {
							readonly property var calendar: accountSection.calendars[index]
							Layout.fillWidth: true
							name: calendar ? (calendar.summaryOverride || calendar.summary) : ""
							swatchColor: calendar ? (page.configBridge.read("googleColorPalette", "current") !== "classic" ? GooglePalette.calendarColor(calendar) : calendar.backgroundColor) : "transparent"
							readOnly: calendar ? calendar.accessRole === "reader" : false
							checked: calendar ? page.isCalendarShown(accountSection.account, calendar) : false
							onToggled: page.setCalendarShown(accountSection.account, calendar, checked)
							// Name in the list and color can be set on any calendar; the name itself only by its owner.
							editable: !!calendar
							onEditRequested: calendarEditDialog.openFor(accountSection.account.id, calendar)
						}
					}

					// Task lists
					FormCard.FormDelegateSeparator {
						visible: accountSection.tasklists.length > 0
					}
					FormCard.FormTextDelegate {
						visible: accountSection.tasklists.length > 0
						text: i18n("Task Lists")
						font.weight: Font.DemiBold
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
		}

		// Sign in / add another account
		FormCard.FormCard {
			Layout.topMargin: Kirigami.Units.largeSpacing
			FormCard.FormButtonDelegate {
				icon.name: googleLoginManager.isLoggedIn ? "list-add-user" : "go-next"
				text: googleLoginManager.isLoggedIn ? i18n("Add Account…") : i18n("Sign in with Google…")
				description: page.autoLoginInProgress ? i18n("Waiting for the browser sign-in…") : ""
				enabled: !autoLoginInProgress && !authConfigurationMessage
				onClicked: {
					authorizationCodeInput.text = ""
					startAutoLogin("")
				}
			}
		}
		FormCard.FormSectionText {
			visible: !!authConfigurationMessage && !page.showAdvancedSignIn // Shown in Client Credentials when open
			text: authConfigurationMessage
		}

		// Advanced sign-in options (collapsed)
		FormCard.FormCard {
			Layout.topMargin: Kirigami.Units.largeSpacing
			FormCard.FormButtonDelegate {
				icon.name: page.showAdvancedSignIn ? "arrow-down" : "arrow-right"
				text: i18n("Advanced sign-in options")
				description: i18n("Your own Google OAuth client, or pasting the sign-in code by hand")
				onClicked: page.showAdvancedSignIn = !page.showAdvancedSignIn
			}
		}

		ColumnLayout {
			id: advancedSignIn
			visible: page.showAdvancedSignIn
			Layout.fillWidth: true
			spacing: 0

			FormCard.FormHeader {
				title: i18n("Client Credentials")
			}
			FormCard.FormCard {
				id: credentialsSection
				property bool credentialsReady: false
				Component.onCompleted: credentialsReady = true

				FormCard.AbstractFormDelegate {
					readonly property string message: authConfigurationMessage
						? authConfigurationMessage
						: googleLoginManager.normalizedClientValue(page.configBridge.read("customClientId", ""))
						? ""
						: page.configBridge.read("latestClientSecret", "")
							? i18n("Using a previously stored Google OAuth client for compatibility. If login still fails, add your own client ID and client secret.")
							: ""
					visible: !!message
					background: null
					contentItem: Kirigami.InlineMessage {
						visible: true
						type: Kirigami.MessageType.Warning
						text: parent ? parent.message : ""
					}
				}
				FormConfigSwitch {
					id: useDesktopClientToggle
					configKey: "useDesktopClient"
					visible: !googleLoginManager.normalizedClientValue(page.configBridge.read("customClientId", ""))
					text: i18n("Try desktop built-in client (no secret)")
					onCheckedChanged: {
						if (!credentialsSection.credentialsReady) {
							return
						}
						googleLoginManager.refreshClientCredentials()
					}
				}
				FormCard.FormDelegateSeparator {}
				FormConfigText {
					id: customClientIdInput
					label: i18n("Client ID")
					configKey: "customClientId"
					placeholderText: i18n("Optional")
					onTextChanged: {
						markDirty()
						googleLoginManager.refreshClientCredentials()
					}
				}
				FormCard.FormDelegateSeparator {}
				FormConfigText {
					id: customClientSecretInput
					label: i18n("Client Secret")
					configKey: "customClientSecret"
					placeholderText: i18n("Optional")
					echoMode: TextInput.Password
					onTextChanged: {
						markDirty()
						googleLoginManager.refreshClientCredentials()
					}
				}
			}
			FormCard.FormSectionText {
				text: i18n("Leave these empty to use the built-in client. A custom client must be a Google Cloud OAuth Desktop client, or a Web client with its secret and the redirect URI set to %1.", googleLoginManager.redirectUri)
			}
			FormCard.FormSectionText {
				text: i18n("For a custom OAuth client, publish the OAuth consent screen to Production. Google expires refresh tokens for external apps left in Testing after seven days; Workspace session controls can also require reauthorization.")
			}

			FormCard.FormHeader {
				title: i18n("Manual Sign-in")
			}
			FormCard.FormCard {
				FormCard.FormButtonDelegate {
					icon.name: "go-next"
					text: googleLoginManager.isLoggedIn ? i18n("Login (Auto) - Add Account") : i18n("Login (Auto)")
					enabled: !autoLoginInProgress && !authConfigurationMessage
					onClicked: {
						authorizationCodeInput.text = ""
						startAutoLogin("")
					}
				}
				FormCard.FormDelegateSeparator {}
				FormCard.AbstractFormDelegate {
					background: null
					contentItem: ColumnLayout {
						spacing: Kirigami.Units.smallSpacing
						LinkText {
							Layout.fillWidth: true
							text: localRedirect
								? i18n("Click Login (Auto) to open <a href=\"%1\">%2</a>. After you grant access, the browser redirects to a localhost URL. If auto-capture succeeds you can ignore the field below; otherwise copy the full URL (or just the code) and paste it.", googleLoginManager.authorizationCodeUrl, 'https://accounts.google.com/...')
								: i18n("Click Login (Auto) to open <a href=\"%1\">%2</a>. After you grant access, the browser redirects to the helper page and will try to send the code back automatically. If it fails, copy the code and paste it below.", googleLoginManager.authorizationCodeUrl, 'https://accounts.google.com/...')
							wrapMode: Text.Wrap
							onLinkActivated: function(link) {
								try {
									syncCredentialInputs()
									googleLoginManager.prepareAuthorization()
									if (!Shared.openExternalUrl(googleLoginManager.authorizationCodeUrl)) {
										messageWidget.err(i18n("The desktop could not open the browser automatically."))
									}
								} catch (e) {
									messageWidget.err(i18n("Could not prepare Google login: %1", String(e)))
								}
							}

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
							wrapMode: Text.Wrap
						}
						Label {
							Layout.fillWidth: true
							wrapMode: Text.Wrap
							opacity: 0.7
							text: localRedirect
								? i18n("If your browser shows a connection error, that's expected. Copy the URL from the address bar anyway and paste it below. If auto-capture works, you do not need to paste anything.")
								: i18n("If auto-capture fails, copy the code from the helper page and paste it below.")
						}
					}
				}
				FormCard.FormDelegateSeparator {}
				FormCard.AbstractFormDelegate {
					background: null
					contentItem: RowLayout {
						spacing: Kirigami.Units.smallSpacing
						TextField {
							id: authorizationCodeInput
							Layout.fillWidth: true
							placeholderText: i18n("Paste the authorization code or redirect URL here")
							echoMode: TextInput.Password
							Accessible.name: i18n("Google authorization code or redirect URL")
							Accessible.description: i18n("Paste the Google authorization code or the full redirect URL from the browser")
							text: ""
						}
						Button {
							text: googleLoginManager.isLoggedIn ? i18n("Add Account") : i18n("Submit")
							enabled: !authConfigurationMessage && (!autoLoginInProgress || !localRedirect || !!authorizationCodeInput.text)
							onClicked: submitAuthorization("")
						}
					}
				}
			}
		}

		// Options
		FormCard.FormHeader {
			visible: googleLoginManager.isLoggedIn
			title: i18n("Options")
		}
		FormCard.FormCard {
			visible: googleLoginManager.isLoggedIn
			FormConfigSwitch {
				configKey: 'googleHideGoalsDesc'
				text: i18n("Hide \"This event was added from Goals in Google Calendar\" description")
				onToggled: markDirty()
			}
		}

		// Debug (only with debugging enabled)
		FormCard.FormHeader {
			visible: showDebug
			title: "Debug Info (Temporary)"
		}
		FormCard.FormCard {
			visible: showDebug
			FormCard.AbstractFormDelegate {
				background: null
				contentItem: ColumnLayout {
					RowLayout {
						Button {
							text: "Test Echo"
							onClicked: {
								var cmd = ['echo', 'Hello World']
								debugOutput.text = "Running: echo Hello World\n"
								callbackListener.execArgv(cmd, function(c, code, status, out, err) {
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
								callbackListener.execArgv(cmd, function(c, code, status, out, err) {
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
			}
		}
	}

	Component.onCompleted: {
		if (page.cfg_googleRedirectMode !== "local") {
			page.configBridge.write("googleRedirectMode", "local")
		}
	}
}
