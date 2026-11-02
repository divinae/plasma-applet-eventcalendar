import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kirigamiaddons.formcard as FormCard

import ".."
import "../lib"
import "../ScriptPath.js" as ScriptPath

// CalDAV accounts (Nextcloud, Fastmail, iCloud, Radicale, …): server, user name and password (the
// password goes to the keyring, scope caldav-account), then the account's calendars to show. Kept
// in caldavAccounts: [{ id, label, url, username, calendars: [{ href, name, color, writable,
// selected }] }]. The widget reads them through calendars/CalDAVManager.qml.
ConfigPage {
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

	function hostOf(url) {
		var m = /^https?:\/\/([^\/:]+)/i.exec(String(url || ""))
		return m ? m[1] : String(url || "")
	}
	// The helper's error line ("AUTH: …") as a message for the user.
	function errorText(stderr) {
		var line = String(stderr || "").trim().split("\n").pop()
		var kind = (/^([A-Z]+):/.exec(line) || [])[1] || ""
		if (kind === "AUTH") {
			return i18n("The server didn't accept the user name or password. Some services need an app password (iCloud, Fastmail, Nextcloud with two-factor sign-in).")
		}
		if (kind === "NETWORK") {
			return i18n("Couldn't connect to the server. Check the address and your connection.")
		}
		if (kind === "NOTFOUND") {
			return i18n("No CalDAV calendars at that address. Try the address your service gives for CalDAV.")
		}
		return line.replace(/^[A-Z]+:\s*/, "") || i18n("Unknown error")
	}

	// The account's calendars from the server; selected ones stay selected (new ones are).
	function discover(account, password, done) {
		executable.execArgv(['python3', helperPath, 'discover', '--url', account.url, '--account', account.id,
			'--user', account.username], function(cmd, exitCode, exitStatus, stdout, stderr) {
			if (exitCode) {
				done(errorText(stderr), null)
				return
			}
			try {
				var data = JSON.parse(stdout)
				var previous = {}
				;(account.calendars || []).forEach(function(c) { previous[c.href] = c.selected !== false })
				var calendars = (data.calendars || []).map(function(c) {
					return {
						href: c.href,
						name: c.name || c.href,
						color: c.color || "",
						writable: c.writable !== false,
						selected: previous[c.href] === undefined ? true : previous[c.href],
					}
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
			statusIsError = true
			statusText = i18n("Enter the server address (https://…), your user name and your password.")
			return
		}
		var account = { id: "acc" + Date.now().toString(36), label: username + "@" + hostOf(url), url: url, username: username, calendars: [] }
		busy = true
		statusIsError = false
		statusText = i18n("Connecting…")
		keyring.store(account.id, "password", password, function(err) {
			if (err) {
				busy = false
				statusIsError = true
				statusText = i18n("The password couldn't be stored in the keyring: %1", String(err))
				return
			}
			discover(account, password, function(err, calendars) {
				busy = false
				if (err) {
					keyring.store(account.id, "password", "", null) // Not kept for an account that isn't added
					statusIsError = true
					statusText = err
					return
				}
				account.calendars = calendars
				saveAccounts(page.accounts.concat([account]))
				passwordField.text = ""
				statusIsError = false
				statusText = calendars.length ? i18np("Connected: %1 calendar", "Connected: %1 calendars", calendars.length)
					: i18n("Connected, but the account has no calendars for events.")
			})
		})
	}

	function refreshAccount(index) {
		var list = page.accounts.slice()
		var account = list[index]
		busy = true
		statusText = i18n("Connecting…")
		discover(account, "", function(err, calendars) {
			busy = false
			if (err) {
				statusIsError = true
				statusText = err
				return
			}
			account.calendars = calendars
			list[index] = account
			saveAccounts(list)
			statusIsError = false
			statusText = ""
		})
	}

	function removeAccount(index) {
		var list = page.accounts.slice()
		var account = list.splice(index, 1)[0]
		keyring.store(account.id, "password", "", null) // Clears it
		saveAccounts(list)
	}

	function setSelected(accountIndex, href, selected) {
		var list = JSON.parse(JSON.stringify(page.accounts))
		list[accountIndex].calendars.forEach(function(c) {
			if (c.href === href) {
				c.selected = selected
			}
		})
		saveAccounts(list)
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
						FormCard.FormCheckDelegate {
							text: modelData.name
							description: modelData.writable === false ? i18n("Read-only") : ""
							checked: modelData.selected !== false
							onToggled: page.setSelected(accountBlock.accountIndex, modelData.href, checked)
							leading: Rectangle {
								width: Kirigami.Units.iconSizes.small * 0.75
								height: width
								radius: width / 2
								color: modelData.color || Kirigami.Theme.highlightColor
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
							visible: !!page.statusText
							text: page.statusText
							wrapMode: Text.Wrap
							color: page.statusIsError ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
						}
						Item { Layout.fillWidth: !page.statusText }
						Button {
							icon.name: "network-connect"
							text: i18n("Connect")
							enabled: !page.busy
							onClicked: page.connect()
						}
					}
					Label {
						Layout.fillWidth: true
						visible: /^http:\/\//i.test(urlField.text.trim())
						text: i18n("Plain http works only for a server on your own network; the password isn't encrypted on the way.")
						wrapMode: Text.Wrap
						color: Kirigami.Theme.neutralTextColor
					}
				}
			}
		}
		FormCard.FormSectionText {
			text: i18n("Nextcloud, Fastmail, iCloud (with an app password), Radicale, Baïkal and others. The password is kept in the system keyring. Repeating events are shown, but changed only in their own app for now.")
		}
	}
}
