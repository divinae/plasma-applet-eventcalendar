import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kirigamiaddons.formcard as FormCard

import ".."
import "../lib"
import "../ScriptPath.js" as ScriptPath
import "../calendars/CalDAVErrors.js" as CalDAVErrors

// CalDAV accounts (Nextcloud, Fastmail, iCloud, Radicale, …): server, user name and password (the
// password goes to the keyring, scope caldav-account), then the account's calendars to show. Kept
// in caldavAccounts: [{ id, label, url, username, calendars: [{ href, name, color, writable,
// selected, userColor }] }]. The widget reads them through calendars/CalDAVManager.qml.
ConfigSection {
	id: page

	Base64Json {
		id: accountsConfig
		configKey: 'caldavAccounts'
		configBridge: page.configBridge // The page's cfg_ value (applied with OK)
	}
	readonly property var accounts: Array.isArray(accountsConfig.value) ? accountsConfig.value : []
	function saveAccounts(list) {
		accountsConfig.value = list
		accountsConfig.serialize()
	}

	KeyringSecret {
		id: keyring
		scope: "caldav-account"
	}
	ExecUtil { id: executable }
	readonly property string helperPath: ScriptPath.scriptPath("caldav.py")

	property bool busy: false
	property string statusText: ""
	property bool statusIsError: false
	function setStatus(text, isError) {
		statusText = text
		statusIsError = !!isError
	}

	function hostOf(url) {
		var m = /^https?:\/\/([^\/:]+)/i.exec(String(url || ""))
		return m ? m[1] : String(url || "")
	}
	// The helper's error (CalDAVErrors.parse) as a message for the user.
	// The Python modules CalDAV is read with, missing (an install from the KDE Store): the error
	// offers to install them, then connects again.
	PythonModules {
		id: pythonModules
		property string installError: ""
		Component.onCompleted: check()
	}
	property bool modulesMissing: false
	function installModules() {
		setStatus(i18n("Installing…"), false)
		pythonModules.install(function(error) {
			if (error) {
				page.setStatus(error, true)
				return
			}
			page.modulesMissing = false
			page.connect() // With what's typed (the password is kept until connected)
		})
	}

	function errorText(stderr) {
		if (pythonModules.isMissing(stderr)) {
			return i18n("CalDAV needs the Python modules icalendar and recurring-ical-events.")
		}
		var parsed = CalDAVErrors.parse(stderr)
		var kind = parsed.kind
		if (kind === "AUTH") {
			return i18n("The server didn't accept the user name or password. Some services need an app password (iCloud, Fastmail, Nextcloud with two-factor sign-in).")
		}
		if (kind === "NETWORK") {
			return i18n("Couldn't connect to the server. Check the address and your connection.")
		}
		if (kind === "NOTFOUND") {
			return i18n("No CalDAV calendars at that address. Try the address your service gives for CalDAV.")
		}
		return parsed.text || i18n("Unknown error")
	}

	// The account's calendars from the server; selected ones stay selected (new ones are).
	function discover(account, done) {
		executable.execArgv(['python3', helperPath, 'discover', '--url', account.url, '--account', account.id,
			'--user', account.username], function(cmd, exitCode, exitStatus, stdout, stderr) {
			if (exitCode) {
				page.modulesMissing = pythonModules.isMissing(stderr)
				done(errorText(stderr), null)
				return
			}
			try {
				var data = JSON.parse(stdout)
				var previous = {}
				var userColors = {} // Picked in the widget: kept over the server's color
				;(account.calendars || []).forEach(function(c) {
					previous[c.href] = c.selected !== false
					if (c.userColor) {
						userColors[c.href] = c.userColor
					}
				})
				var calendars = (data.calendars || []).map(function(c) {
					var calendar = {
						href: c.href,
						name: c.name || c.href,
						color: c.color || "",
						writable: c.writable !== false,
						selected: previous[c.href] === undefined ? true : previous[c.href],
					}
					if (userColors[c.href]) {
						calendar.userColor = userColors[c.href]
					}
					return calendar
				})
				done(null, calendars)
			} catch (e) {
				done(i18n("The server's answer couldn't be read"), null)
			}
		})
	}

	function connect() {
		var url = urlField.text.trim()
		var username = userField.text.trim()
		var password = passwordField.text
		if (!/^https?:\/\//i.test(url) || !username || !password) {
			setStatus(i18n("Enter the server address (https://…), your user name and your password."), true)
			return
		}
		var account = { id: "acc" + Date.now().toString(36), label: username + "@" + hostOf(url), url: url, username: username, calendars: [] }
		busy = true
		setStatus(i18n("Connecting…"), false)
		keyring.store(account.id, "password", password, function(err) {
			if (err) {
				busy = false
				setStatus(i18n("The password couldn't be stored in the keyring: %1", String(err)), true)
				return
			}
			discover(account, function(err, calendars) {
				busy = false
				if (err) {
					keyring.clear(account.id, "password", null) // Not kept for an account that isn't added
					setStatus(err, true)
					return
				}
				account.calendars = calendars
				saveAccounts(page.accounts.concat([account]))
				passwordField.text = ""
				setStatus(calendars.length ? i18np("Connected: %1 calendar", "Connected: %1 calendars", calendars.length)
					: i18n("Connected, but the account has no calendars for events."), false)
			})
		})
	}

	function refreshAccount(index) {
		var list = page.accounts.slice()
		var account = list[index]
		busy = true
		setStatus(i18n("Connecting…"), false)
		discover(account, function(err, calendars) {
			busy = false
			if (err) {
				setStatus(err, true)
				return
			}
			account.calendars = calendars
			list[index] = account
			saveAccounts(list)
			setStatus("", false)
		})
	}

	function removeAccount(index) {
		var list = page.accounts.slice()
		var account = list.splice(index, 1)[0]
		keyring.clear(account.id, "password", null)
		saveAccounts(list)
	}

	function setCalendarProperty(accountIndex, href, key, value) {
		var list = JSON.parse(JSON.stringify(page.accounts))
		list[accountIndex].calendars.forEach(function(c) {
			if (c.href === href) {
				if (value === undefined) {
					delete c[key]
				} else {
					c[key] = value
				}
			}
		})
		saveAccounts(list)
	}
	function setSelected(accountIndex, href, selected) {
		setCalendarProperty(accountIndex, href, 'selected', selected)
	}
	// Its color in the widget; "" goes back to the server's.
	function setUserColor(accountIndex, href, color) {
		setCalendarProperty(accountIndex, href, 'userColor', color || undefined)
	}

	// The Python modules missing (an install from the KDE Store): said before anything is tried,
	// with Install (lib/PythonModules.qml).
	Kirigami.InlineMessage {
		Layout.fillWidth: true
		Layout.margins: Kirigami.Units.largeSpacing
		visible: pythonModules.present === false
		type: Kirigami.MessageType.Warning
		text: pythonModules.installing ? i18n("Installing…")
			: i18n("The Python modules icalendar and recurring-ical-events aren't all installed: calendars, or their repeating events, can be missing.")
		actions: [
			Kirigami.Action {
				icon.name: "download"
				text: i18n("Install")
				enabled: !pythonModules.installing
				tooltip: i18n("Downloads icalendar and recurring-ical-events into the widget's own folder.")
				onTriggered: pythonModules.install(function(error) { pythonModules.installError = error })
			}
		]
	}
	Kirigami.InlineMessage {
		Layout.fillWidth: true
		Layout.leftMargin: Kirigami.Units.largeSpacing
		Layout.rightMargin: Kirigami.Units.largeSpacing
		visible: !!pythonModules.installError
		type: Kirigami.MessageType.Error
		text: pythonModules.installError
	}

	ColumnLayout {
		Layout.fillWidth: true
		spacing: 0

		// The accounts and their calendars.
		Repeater {
			model: page.accounts
			ColumnLayout {
				id: accountBlock
				readonly property var account: modelData
				readonly property int accountIndex: index
				Layout.fillWidth: true
				spacing: 0
				FormCard.FormHeader {
					title: accountBlock.account.label || accountBlock.account.username
				}
				FormCard.FormCard {
					Repeater {
						model: accountBlock.account.calendars || []
						// Not a FormCheckDelegate: its leading item (the color) isn't shown.
						FormCard.AbstractFormDelegate {
							id: calendarRow
							readonly property bool shown: modelData.selected !== false
							onClicked: page.setSelected(accountBlock.accountIndex, modelData.href, !shown)
							contentItem: RowLayout {
								spacing: Kirigami.Units.largeSpacing
								CheckBox {
									focusPolicy: Qt.NoFocus // The row has it
									checked: calendarRow.shown
									onToggled: page.setSelected(accountBlock.accountIndex, modelData.href, checked)
									Accessible.name: modelData.name
								}
								CalendarColorButton {
									shownColor: modelData.userColor || modelData.color || Kirigami.Theme.highlightColor
									resetText: modelData.userColor ? i18n("Server's Color") : ""
									onColorChosen: function(color) { page.setUserColor(accountBlock.accountIndex, modelData.href, color) }
								}
								ColumnLayout {
									Layout.fillWidth: true
									spacing: 0
									Label {
										Layout.fillWidth: true
										text: modelData.name
										elide: Text.ElideRight
									}
									Label {
										Layout.fillWidth: true
										visible: modelData.writable === false
										text: i18n("Read-only")
										color: Kirigami.Theme.disabledTextColor
										font: Kirigami.Theme.smallFont
									}
								}
							}
						}
					}
					FormCard.FormDelegateSeparator {}
					FormCard.AbstractFormDelegate {
						background: null
						contentItem: RowLayout {
							Item { Layout.fillWidth: true }
							Button {
								icon.name: "view-refresh"
								text: i18n("Refresh Calendars")
								enabled: !page.busy
								onClicked: page.refreshAccount(accountBlock.accountIndex)
							}
							Button {
								icon.name: "edit-delete"
								text: i18n("Remove Account")
								enabled: !page.busy
								onClicked: page.removeAccount(accountBlock.accountIndex)
							}
						}
					}
				}
			}
		}

		// A new account.
		FormCard.FormHeader {
			title: i18n("Add a CalDAV Account")
		}
		FormCard.FormCard {
			FormCard.FormTextFieldDelegate {
				id: urlField
				label: i18n("Server")
				placeholderText: i18n("eg: https://cloud.example.org/remote.php/dav")
			}
			FormCard.FormDelegateSeparator {}
			FormCard.FormTextFieldDelegate {
				id: userField
				label: i18n("User name")
			}
			FormCard.FormDelegateSeparator {}
			FormCard.FormPasswordFieldDelegate {
				id: passwordField
				label: i18n("Password")
			}
			FormCard.FormDelegateSeparator {}
			FormCard.AbstractFormDelegate {
				background: null
				contentItem: ColumnLayout {
					spacing: Kirigami.Units.smallSpacing
					RowLayout {
						BusyIndicator {
							visible: page.busy
							running: visible
							Layout.preferredWidth: Kirigami.Units.iconSizes.small
							Layout.preferredHeight: Layout.preferredWidth
						}
						Label {
							Layout.fillWidth: true
							visible: !!page.statusText && !page.statusIsError
							text: page.statusText
							wrapMode: Text.Wrap
						}
						Item { Layout.fillWidth: !page.statusText || page.statusIsError }
						Button {
							icon.name: "network-connect"
							text: i18n("Connect")
							enabled: !page.busy
							onClicked: page.connect()
						}
					}
					// As the other settings pages: errors and warnings in an inline message.
					Kirigami.InlineMessage {
						Layout.fillWidth: true
						visible: page.statusIsError && !!page.statusText
						type: Kirigami.MessageType.Error
						text: page.statusText
						actions: [
							Kirigami.Action {
								visible: page.modulesMissing
								icon.name: "download"
								text: i18n("Install")
								enabled: !pythonModules.installing && !page.busy
								tooltip: i18n("Downloads icalendar and recurring-ical-events into the widget's own folder.")
								onTriggered: page.installModules()
							}
						]
					}
					Kirigami.InlineMessage {
						Layout.fillWidth: true
						visible: /^http:\/\//i.test(urlField.text.trim())
						type: Kirigami.MessageType.Warning
						text: i18n("Plain http works only for a server on your own network; the password isn't encrypted on the way.")
					}
				}
			}
		}
		FormCard.FormSectionText {
			text: i18n("Nextcloud, Fastmail, iCloud (with an app password), Radicale, Baïkal and others. The password is kept in the system keyring. Repeating events are shown, but changed only in their own app for now.")
		}
	}
}
