import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kirigamiaddons.formcard as FormCard

import ".."
import "../lib"
import "../calendars"
import "../Shared.js" as Shared
import "../TaskLists.js" as TaskLists

// Everything about tasks: how they're shown, the Google task lists, and TickTick accounts.
ConfigPage {
	id: page

	function markDirty() {
		if (typeof kcm !== "undefined") {
			kcm.needsSave = true
		}
	}

	function byName(key) {
		return function(a, b) {
			return String(a[key] || "").toLowerCase().localeCompare(String(b[key] || "").toLowerCase())
		}
	}

	//--- Google task lists, per account (the accounts are signed in on the Google Calendar page)
	GoogleLoginManager {
		id: googleLoginManager
		configBridge: page.configBridge
		redirectMode: "local"
	}
	function googleAccountLabel(account, index) {
		return account && account.label ? account.label : i18n("Google Account %1", index + 1)
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

	//--- TickTick
	TickTickAccountsStore {
		id: tickTickStore
		configBridge: page.configBridge
	}
	// Used for Connect (the pasted token) and reloading projects (the account's keyring token).
	TickTickApiSession {
		id: tickTickSession
	}
	property bool tickTickBusy: false

	function isProjectShown(account, project) {
		return Shared.toArray(account.projectIdList).indexOf(project.id) >= 0
	}
	function setProjectShown(account, project, shown) {
		var ids = Shared.toArray(account.projectIdList).filter(function(id) {
			return id !== project.id
		})
		if (shown) {
			ids.push(project.id)
		}
		tickTickStore.setProjectIdList(account.id, ids)
		markDirty()
	}

	// What went wrong with a TickTick request, for the message bar.
	function tickTickError(err, xhr) {
		if (xhr && xhr.status === 401) {
			return i18n("TickTick did not accept the API token. Check it and try again.")
		}
		if (!xhr || xhr.status === 0) {
			return i18n("Could not connect to TickTick. Check your connection and try again.")
		}
		return i18n("TickTick error: %1", xhr.status)
	}

	// Check the pasted token (GET /project), store it in the keyring and add the account with its
	// projects, all shown.
	function connectTickTick() {
		var token = tickTickTokenField.text.trim()
		if (!token || tickTickBusy) {
			return
		}
		var server = tickTickServerCombo.currentValue || "ticktick"
		tickTickBusy = true
		messageWidget.info(i18n("Connecting to TickTick…"))
		tickTickSession.server = server
		tickTickSession.token = token
		tickTickSession.fetchProjects(i18n("Inbox"), function(err, projects, xhr) {
			tickTickSession.token = ""
			if (err) {
				tickTickBusy = false
				messageWidget.err(tickTickError(err, xhr))
				return
			}
			tickTickStore.addAccount({
				server: server,
				projectList: projects,
				projectIdList: projects.map(function(p) { return p.id }),
			}, token, function(storeErr) {
				tickTickBusy = false
				if (storeErr) {
					messageWidget.err(i18n("Could not store the API token in the system keyring: %1", storeErr))
					return
				}
				tickTickTokenField.text = ""
				messageWidget.success(i18n("TickTick account added."))
				markDirty()
			})
		})
	}

	// Fetch an account's projects again; the selection is kept (new projects aren't shown).
	function reloadTickTickProjects(account) {
		if (!account || !account.token || tickTickBusy) {
			return
		}
		tickTickBusy = true
		tickTickSession.server = account.server
		tickTickSession.token = account.token
		tickTickSession.fetchProjects(i18n("Inbox"), function(err, projects, xhr) {
			tickTickSession.token = ""
			tickTickBusy = false
			if (err) {
				messageWidget.err(tickTickError(err, xhr))
				return
			}
			var ids = projects.map(function(p) { return p.id })
			tickTickStore.updateAccount(account.id, {
				projectList: projects,
				projectIdList: Shared.toArray(account.projectIdList).filter(function(id) { return ids.indexOf(id) >= 0 }),
			})
			markDirty()
		})
	}

	//--- Managing the lists: rename, delete (confirmed first), new list, per account. The task
	// managers do the requests and update the account's stored lists (TaskLists.js).
	Component {
		id: googleTasksManagerComponent
		GoogleTasksManager {}
	}
	Component {
		id: tickTickSessionComponent
		TickTickApiSession {}
	}
	Component {
		id: tickTickManagerComponent
		TickTickTasksManager {}
	}
	property var listManagers: ({})
	property bool listBusy: false

	// provider: 'google' or 'ticktick'.
	function listManager(provider, account) {
		var key = provider + ':' + account.id
		var manager = listManagers[key]
		if (!manager && provider === 'google') {
			manager = googleTasksManagerComponent.createObject(page, {
				session: googleLoginManager.apiSessionFor(account.id),
				accountsStore: googleLoginManager.store,
				accountId: account.id,
			})
		} else if (!manager) {
			manager = tickTickManagerComponent.createObject(page, {
				session: tickTickSessionComponent.createObject(page, {}),
				accountsStore: tickTickStore,
				accountId: account.id,
			})
		}
		listManagers[key] = manager
		if (provider === 'ticktick') {
			manager.session.server = account.server
			manager.session.token = account.token || ""
		}
		return manager
	}
	// { rename, delete, color, clearCompleted } of a stored list.
	// A TickTick account without its token (not in the keyring) can't change anything.
	function listCaps(provider, account, list) {
		if (!list || !account || (provider === 'ticktick' && !account.token)) {
			return TaskLists.capabilities('', '', '')
		}
		return provider === 'google'
			? TaskLists.capabilities('GoogleTasks', list.id, 'owner')
			: TaskLists.capabilities('TickTick', list.id, TaskLists.tickTickRole(list.permission))
	}
	// section: the account's card (editingId, confirmId, errorText). start(manager, done).
	function runListAction(section, provider, account, errorText, start) {
		if (listBusy || !account) {
			return
		}
		listBusy = true
		section.errorText = ""
		start(listManager(provider, account), function(err) {
			page.listBusy = false
			if (err) {
				section.errorText = errorText
				return
			}
			section.editingId = ""
			section.confirmId = ""
			section.newListText = ""
			page.markDirty()
		})
	}
	function renameList(section, provider, account, list, text) {
		var title = TaskLists.cleanTitle(text)
		if (!title) {
			return
		}
		runListAction(section, provider, account, i18n("Couldn't rename the list"), function(manager, done) {
			manager.renameTaskList(account.id + '::' + list.id, title, done)
		})
	}
	function deleteList(section, provider, account, list) {
		runListAction(section, provider, account, i18n("Couldn't delete the list"), function(manager, done) {
			manager.deleteTaskList(account.id + '::' + list.id, done)
		})
	}
	function createList(section, provider, account, text) {
		var title = TaskLists.cleanTitle(text)
		if (!title) {
			return
		}
		runListAction(section, provider, account, i18n("Couldn't create the list"), function(manager, done) {
			manager.createTaskList(title, done)
		})
	}

	// A list's toggle with rename and delete, its name field while renaming, the delete
	// confirmation.
	component ManagedListRow: ColumnLayout {
		id: managed
		property var section: null
		property string provider: ""
		property var account: null
		property var list: null
		property string name: ""
		property alias swatchColor: selection.swatchColor
		property alias iconSource: selection.iconSource
		property alias checked: selection.checked
		signal toggled(bool checked)
		readonly property var caps: page.listCaps(provider, account, list)
		readonly property bool renaming: !!list && !!section && section.editingId === list.id
		readonly property bool confirming: !!list && !!section && section.confirmId === list.id
		Layout.fillWidth: true
		spacing: 0

		SelectionRow {
			id: selection
			Layout.fillWidth: true
			name: managed.name
			canRename: managed.caps.rename && !managed.renaming
			canDelete: managed.caps.delete && !managed.confirming
			enabled: !page.listBusy
			onToggled: managed.toggled(checked)
			onRenameRequested: {
				managed.section.confirmId = ""
				managed.section.errorText = ""
				managed.section.editingId = managed.list.id
			}
			onDeleteRequested: {
				managed.section.editingId = ""
				managed.section.errorText = ""
				managed.section.confirmId = managed.list.id
			}
		}
		FormCard.FormTextFieldDelegate {
			id: renameField
			visible: managed.renaming
			label: i18n("List name")
			readOnly: page.listBusy
			onVisibleChanged: {
				if (visible) {
					text = managed.name
					forceActiveFocus()
					selectAll()
				}
			}
			onAccepted: page.renameList(managed.section, managed.provider, managed.account, managed.list, text)
			Keys.onEscapePressed: managed.section.editingId = ""
			trailing: [
				Button {
					icon.name: "dialog-ok-apply"
					text: i18n("Rename")
					enabled: !page.listBusy
					onClicked: page.renameList(managed.section, managed.provider, managed.account, managed.list, renameField.text)
				},
				Button {
					text: i18n("Cancel")
					onClicked: managed.section.editingId = ""
				}
			]
		}
		FormCard.AbstractFormDelegate {
			visible: managed.confirming
			Layout.fillWidth: true
			background: null
			contentItem: ColumnLayout {
				spacing: Kirigami.Units.smallSpacing
				Label {
					Layout.fillWidth: true
					text: i18nc("%1 = task list name", "Delete the list \"%1\" and all its tasks? This can't be undone.", managed.name)
					textFormat: Text.PlainText // User text (list name)
					wrapMode: Text.Wrap
				}
				RowLayout {
					spacing: Kirigami.Units.smallSpacing
					Button {
						icon.name: "edit-delete"
						text: i18n("Delete")
						enabled: !page.listBusy
						onClicked: page.deleteList(managed.section, managed.provider, managed.account, managed.list)
					}
					Button {
						text: i18n("Cancel")
						onClicked: managed.section.confirmId = ""
					}
				}
			}
		}
	}

	// "New list" at the end of an account's lists, and what went wrong with its lists.
	component NewListRows: ColumnLayout {
		id: newList
		property var section: null
		property string provider: ""
		property var account: null
		Layout.fillWidth: true
		spacing: 0

		FormCard.AbstractFormDelegate {
			visible: !!newList.section && !!newList.section.errorText
			Layout.fillWidth: true
			background: null
			contentItem: Kirigami.InlineMessage {
				visible: true
				type: Kirigami.MessageType.Error
				text: newList.section ? newList.section.errorText : ""
			}
		}
		FormCard.FormTextFieldDelegate {
			id: newListField
			label: i18n("New list")
			placeholderText: i18n("List name")
			readOnly: page.listBusy
			text: newList.section ? newList.section.newListText : ""
			onTextEdited: newList.section.newListText = text
			onAccepted: page.createList(newList.section, newList.provider, newList.account, text)
			trailing: Button {
				icon.name: "list-add"
				text: i18n("Add")
				enabled: !page.listBusy && TaskLists.cleanTitle(newListField.text).length > 0
				onClicked: page.createList(newList.section, newList.provider, newList.account, newListField.text)
			}
		}
	}

	ColumnLayout {
		Layout.fillWidth: true
		spacing: 0

		MessageWidget {
			id: messageWidget
			Layout.fillWidth: true
			Layout.leftMargin: Kirigami.Units.largeSpacing
			Layout.rightMargin: Kirigami.Units.largeSpacing
		}

		//--- General
		FormCard.FormHeader {
			title: i18n("General")
		}
		FormCard.FormCard {
			FormConfigSwitch {
				text: i18n("Overdue tasks on today")
				description: i18n("Open tasks due on an earlier day are shown on today, in every view.")
				configKey: 'agendaPlaceOverdueTasksOnToday'
			}
			FormCard.FormDelegateSeparator {}
			FormConfigSwitch {
				text: i18n("Smart recognition in Add a task")
				description: i18n("Words like \"tomorrow 17:00\", \"!high\", \"#List\" or \"every week\" set the new task's day, time, priority, list and repeat.")
				configKey: 'tasksSmartQuickAdd'
			}
		}

		//--- Notifications (UpcomingEvents.qml)
		FormCard.FormHeader {
			title: i18n("Notifications")
		}
		FormCard.FormCard {
			FormConfigSwitch {
				text: i18n("Task reminders")
				description: i18n("A notification when a task with a due time or a reminder is due, and the tasks due today at the daily agenda time.")
				configKey: 'taskRemindersEnabled'
			}
			FormCard.FormDelegateSeparator {}
			FormConfigSwitch {
				text: i18n("Tasks in the daily agenda")
				description: i18n("The daily agenda notification also lists today's and overdue tasks.")
				configKey: 'dailyAgendaTasks'
			}
		}

		//--- Google Tasks
		FormCard.FormHeader {
			title: i18n("Google Tasks")
		}
		FormCard.FormSectionText {
			visible: !googleLoginManager.isLoggedIn
			text: i18n("Sign in on the Google Calendar page to choose the Google task lists shown here.")
		}
		Repeater {
			model: googleLoginManager.accounts ? googleLoginManager.accounts.length : 0

			ColumnLayout {
				id: googleSection
				readonly property var account: googleLoginManager.accounts[index] || null
				readonly property var tasklists: account ? Shared.toArray(account.tasklistList).concat().sort(page.byName("title")) : []
				// Managing the lists (see ManagedListRow, NewListRows).
				property string editingId: ""
				property string confirmId: ""
				property string errorText: ""
				property string newListText: ""
				Layout.fillWidth: true
				spacing: 0

				FormCard.FormCard {
					Layout.topMargin: index > 0 ? Kirigami.Units.largeSpacing : 0
					FormCard.FormTextDelegate {
						text: page.googleAccountLabel(googleSection.account, index)
						description: i18n("Task Lists")
						font.weight: Font.DemiBold
					}
					FormCard.FormTextDelegate {
						visible: googleSection.tasklists.length === 0
						text: i18n("No task lists loaded yet. Reload the account on the Google Calendar page.")
						textItem.opacity: 0.6
					}
					Repeater {
						model: googleSection.tasklists.length
						ManagedListRow {
							readonly property var tasklist: googleSection.tasklists[index]
							section: googleSection
							provider: "google"
							account: googleSection.account
							list: tasklist || null
							name: tasklist ? tasklist.title : ""
							iconSource: Qt.resolvedUrl("../../icons/google_tasks_96px.png")
							checked: tasklist ? page.isTasklistShown(googleSection.account, tasklist) : false
							onToggled: function(checked) { page.setTasklistShown(googleSection.account, tasklist, checked) }
						}
					}
					NewListRows {
						section: googleSection
						provider: "google"
						account: googleSection.account
					}
				}
			}
		}

		//--- TickTick
		FormCard.FormHeader {
			title: i18n("TickTick")
		}
		Repeater {
			model: tickTickStore.accounts.length

			ColumnLayout {
				id: tickTickSection
				readonly property var account: tickTickStore.accounts[index] || null
				readonly property var projects: account ? Shared.toArray(account.projectList) : []
				property bool confirmRemove: false
				// Managing the lists (see ManagedListRow, NewListRows).
				property string editingId: ""
				property string confirmId: ""
				property string errorText: ""
				property string newListText: ""
				Layout.fillWidth: true
				spacing: 0

				FormCard.FormCard {
					Layout.topMargin: index > 0 ? Kirigami.Units.largeSpacing : 0
					FormCard.AbstractFormDelegate {
						background: null
						contentItem: RowLayout {
							spacing: Kirigami.Units.smallSpacing
							Label {
								Layout.fillWidth: true
								text: tickTickSection.account ? tickTickSection.account.label : ""
								font.weight: Font.DemiBold
								elide: Text.ElideRight
							}
							ToolButton {
								visible: !tickTickSection.confirmRemove
								enabled: !page.tickTickBusy && !!(tickTickSection.account && tickTickSection.account.token)
								icon.name: "view-refresh"
								display: AbstractButton.IconOnly
								text: i18n("Reload projects")
								onClicked: page.reloadTickTickProjects(tickTickSection.account)
								ToolTip.text: text
								ToolTip.visible: hovered
							}
							ToolButton {
								visible: !tickTickSection.confirmRemove
								icon.name: "list-remove-user"
								display: AbstractButton.IconOnly
								text: i18n("Remove Account")
								onClicked: tickTickSection.confirmRemove = true
								ToolTip.text: text
								ToolTip.visible: hovered
							}
							Button {
								visible: tickTickSection.confirmRemove
								icon.name: "edit-delete"
								text: i18n("Remove")
								onClicked: {
									tickTickStore.removeAccount(tickTickSection.account.id)
									page.markDirty()
								}
							}
							Button {
								visible: tickTickSection.confirmRemove
								text: i18n("Cancel")
								onClicked: tickTickSection.confirmRemove = false
							}
						}
					}
					FormCard.AbstractFormDelegate {
						visible: tickTickStore.secretsLoaded && !!tickTickSection.account && !tickTickSection.account.token
						background: null
						contentItem: Kirigami.InlineMessage {
							visible: true
							type: Kirigami.MessageType.Warning
							text: i18n("This account's API token is not in the system keyring. Remove the account and connect it again.")
						}
					}
					FormCard.FormTextDelegate {
						visible: tickTickSection.projects.length === 0
						text: i18n("No projects loaded yet. Use the reload button.")
						textItem.opacity: 0.6
					}
					Repeater {
						model: tickTickSection.projects.length
						ManagedListRow {
							readonly property var project: tickTickSection.projects[index]
							section: tickTickSection
							provider: "ticktick"
							account: tickTickSection.account
							list: project || null
							name: project ? project.name : ""
							swatchColor: project && project.color ? project.color : Kirigami.Theme.highlightColor
							checked: project ? page.isProjectShown(tickTickSection.account, project) : false
							onToggled: function(checked) { page.setProjectShown(tickTickSection.account, project, checked) }
						}
					}
					NewListRows {
						visible: !!(tickTickSection.account && tickTickSection.account.token)
						section: tickTickSection
						provider: "ticktick"
						account: tickTickSection.account
					}
				}
			}
		}

		// Add an account
		FormCard.FormCard {
			Layout.topMargin: tickTickStore.accounts.length ? Kirigami.Units.largeSpacing : 0
			FormCard.FormComboBoxDelegate {
				id: tickTickServerCombo
				text: i18n("Server")
				textRole: "text"
				valueRole: "value"
				model: [
					{ value: "ticktick", text: i18n("TickTick (ticktick.com)") },
					{ value: "dida365", text: i18n("Dida365 (dida365.com)") },
				]
			}
			FormCard.FormDelegateSeparator {}
			FormCard.FormTextFieldDelegate {
				id: tickTickTokenField
				label: i18n("API token")
				echoMode: TextInput.Password
				placeholderText: i18n("Paste the API token")
			}
			FormCard.FormDelegateSeparator {}
			FormCard.FormButtonDelegate {
				icon.name: "list-add-user"
				text: tickTickStore.accounts.length ? i18n("Connect Another Account") : i18n("Connect")
				description: page.tickTickBusy ? i18n("Connecting to TickTick…") : ""
				enabled: !page.tickTickBusy && tickTickTokenField.text.trim().length > 0
				onClicked: page.connectTickTick()
			}
		}
		FormCard.FormSectionText {
			text: i18n("Create an API token on the TickTick website: Settings > Account > API Token (on dida365.com for Dida365). The token is kept in the system keyring (KWallet or Secret Service), not in the widget's settings.")
		}
	}
}
