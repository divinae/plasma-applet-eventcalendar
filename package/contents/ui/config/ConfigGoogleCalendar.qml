import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kirigamiaddons.formcard as FormCard

import ".."
import "../lib"
import "../ScriptPath.js" as ScriptPath
import "../Shared.js" as Shared
import "../code/GooglePalette.js" as GooglePalette
import "../calendars/PlasmaCalendarUtils.js" as PlasmaCalendarUtils

ConfigPage {
	id: page

	function markDirty() {
		if (typeof kcm !== "undefined") {
			kcm.needsSave = true
		}
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

	//--- Calendar selection, per account (task lists: the Tasks page)
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

	ExecUtil { id: callbackListener }

	//--- Google accounts KDE PIM (Akonadi) syncs: their events also come in, read-only, through the
	// PIM events plugin of the Plasma calendars (Events page). The widget shows an event signed in
	// to here as well only once (see PlasmaCalendarEventState.pimDuplicates).
	ExecUtil { id: akonadiReader }
	property var akonadiGoogleAccounts: [] // Email addresses
	readonly property bool pimEventsEnabled: PlasmaCalendarUtils.hasPlugin(page.configBridge.read("enabledCalendarPlugins", []), "pimevents")
	readonly property var directGoogleAccounts: Shared.toArray(googleLoginManager.accounts).map(function(account) {
		return primaryCalendarId(account).toLowerCase()
	}).filter(function(email) {
		return !!email
	})
	readonly property var akonadiOnlyAccounts: akonadiGoogleAccounts.filter(function(email) {
		return directGoogleAccounts.indexOf(email.toLowerCase()) < 0
	})
	function loadAkonadiGoogleAccounts() {
		// The Account= of each Google resource that is still set up (has its agent config).
		var script = 'cd "${XDG_CONFIG_HOME:-$HOME/.config}" || exit 0; '
			+ 'for f in akonadi_google_resource_*rc; do '
			+ '[ -f "akonadi/agent_config_${f%rc}" ] && sed -n "s/^Account=//p" "$f"; '
			+ 'done; exit 0'
		akonadiReader.execArgv(['sh', '-c', script], function(cmd, exitCode, exitStatus, stdout, stderr) {
			page.akonadiGoogleAccounts = String(stdout || "").split("\n").map(function(line) {
				return line.trim()
			}).filter(function(email, i, list) {
				return !!email && list.indexOf(email) === i
			})
		})
	}
	Component.onCompleted: {
		loadAkonadiGoogleAccounts()
		loadAkonadiColors()
		updateShownPimCalendars() // The model may be filled already: no reset or insert comes then
	}

	// The Akonadi calendars the widget shows (the pimevents plugin's own selection), read-only here.
	property var pimCalendarsModel: {
		try { // kdepim-addons is optional
			return Qt.createQmlObject("import org.kde.plasma.PimCalendars; PimCalendarsModel {}", page)
		} catch (e) {
			return null
		}
	}
	property var shownPimCalendars: []
	// Their colors, from Akonadi's database (PlasmaCalendarUtils.akonadiColorsCommand): none when
	// it can't be read.
	ExecUtil { id: akonadiColorReader }
	property var akonadiColors: ({})
	function loadAkonadiColors() {
		akonadiColorReader.execArgv(PlasmaCalendarUtils.akonadiColorsCommand(), function(cmd, exitCode, exitStatus, stdout) {
			page.akonadiColors = PlasmaCalendarUtils.parseAkonadiColors(stdout)
		})
	}
	function updateShownPimCalendars() {
		shownPimCalendars = PlasmaCalendarUtils.pimCalendarRows(pimCalendarsModel, Qt.UserRole, Qt.DisplayRole).filter(function(row) {
			return row.checked
		})
	}
	Connections { // Akonadi fills the model asynchronously
		target: page.pimCalendarsModel
		function onModelReset() { page.updateShownPimCalendars() }
		function onRowsInserted() { page.updateShownPimCalendars() }
		function onRowsRemoved() { page.updateShownPimCalendars() }
		function onDataChanged() { page.updateShownPimCalendars() }
	}
	onPimCalendarsModelChanged: updateShownPimCalendars()

	property bool autoLoginInProgress: false
	property bool autoLoginCancelled: false
	property int loginAttempt: 0 // Callbacks of older (replaced / cancelled) sign-ins are ignored

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
		messageWidget.info(i18n("Waiting for browser callback..."))
		// Only the port and the one-time state: the client secret and PKCE verifier stay in the
		// widget (argv is visible to other processes), which exchanges the code itself.
		var cmd = [
			'python3',
			ScriptPath.scriptPath("google_redirect.py"),
			'--listen_port',
			'53682',
			'--state',
			authContext.state,
		]
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
		FormCard.FormSectionText {
			visible: page.pimEventsEnabled && page.akonadiGoogleAccounts.length > 0
			text: page.akonadiOnlyAccounts.length > 0
				? i18nc("%1 = email addresses", "KDE PIM (Akonadi) already brings in the Google calendars of %1, read-only. Sign in here as well to answer invitations, edit and delete events and join meetings from the widget. Events of an account synced both ways are shown once, from the sign-in here.",
					page.akonadiOnlyAccounts.join(i18nc("separator of names in a list", ", ")))
				: i18nc("%1 = email addresses", "Also synced by KDE PIM (Akonadi): %1. Their events are shown once, from the sign-in here, where they can be answered and edited.",
					page.akonadiGoogleAccounts.join(i18nc("separator of names in a list", ", ")))
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
							swatchColor: calendar ? GooglePalette.displayCalendarColor(calendar, page.configBridge.read("googleColorPalette", "current")) : "transparent"
							readOnly: calendar ? calendar.accessRole === "reader" : false
							checked: calendar ? page.isCalendarShown(accountSection.account, calendar) : false
							onToggled: page.setCalendarShown(accountSection.account, calendar, checked)
							// Name in the list and color can be set on any calendar; the name itself only by its owner.
							editable: !!calendar
							onEditRequested: calendarEditDialog.openFor(accountSection.account.id, calendar)
						}
					}

				}
			}
		}

		FormCard.FormSectionText {
			visible: googleLoginManager.isLoggedIn
			text: i18n("Task lists are chosen on the Tasks page.")
		}

		// Calendars that come in through KDE PIM: listed, chosen in the pimevents plugin's settings.
		FormCard.FormHeader {
			visible: page.pimEventsEnabled && page.shownPimCalendars.length > 0
			title: i18n("KDE PIM (Akonadi)")
		}
		FormCard.FormCard {
			visible: page.pimEventsEnabled && page.shownPimCalendars.length > 0
			Repeater {
				model: page.shownPimCalendars
				FormCard.FormTextDelegate {
					id: pimCalendarRow
					readonly property string calendarColor: page.akonadiColors[modelData.id] || ""
					icon.name: calendarColor ? "" : "view-calendar"
					text: modelData.name
					// The calendar's color, like the popup's calendar list.
					leading: Rectangle {
						visible: !!pimCalendarRow.calendarColor
						implicitWidth: Kirigami.Units.iconSizes.small * 0.75
						implicitHeight: implicitWidth
						radius: width / 2
						color: pimCalendarRow.calendarColor || "transparent"
					}
				}
			}
		}
		FormCard.FormSectionText {
			visible: page.pimEventsEnabled && page.shownPimCalendars.length > 0
			text: i18n("Shown read-only. Which Akonadi calendars are shown is set on the settings page of the PIM events plugin (Events > Plasma calendars). In the popup's calendar menu they are shown and hidden by color: calendars of one color together.")
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
							text: i18n("Click Login (Auto) to open <a href=\"%1\">%2</a>. After you grant access, the browser redirects to a localhost URL. If auto-capture succeeds you can ignore the field below; otherwise copy the full URL (or just the code) and paste it.", googleLoginManager.authorizationCodeUrl, 'https://accounts.google.com/...')
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
							text: i18n("Helper page (optional): <a href=\"%1\">%1</a>", googleLoginManager.hostedRedirectUri)
							wrapMode: Text.Wrap
						}
						Label {
							Layout.fillWidth: true
							wrapMode: Text.Wrap
							opacity: 0.7
							text: i18n("If your browser shows a connection error, that's expected. Copy the URL from the address bar anyway and paste it below. If auto-capture works, you do not need to paste anything.")
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
							enabled: !authConfigurationMessage && (!autoLoginInProgress || !!authorizationCodeInput.text)
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
	}
}
