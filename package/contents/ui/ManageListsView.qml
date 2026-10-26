import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "TaskLists.js" as TaskLists

// The Tasks tab's "Manage lists" page (TasksView.managing): every selected task list by account
// (islands: a card each), with its color, name, open count and its actions in plain sight: Show in
// smart lists, Rename (inline), Clear completed (Google), Delete (confirmed inline); the color dot
// picks a color (TickTick). "New list" at the end of each account's lists. The list requests and
// their state (busy, errors, rename, new list) are TasksView's.
ColumnLayout {
	id: manage

	property Item view: null

	// [{ account, lists }]: the lists whose ids start with the account's prefix; lists of no known
	// account (can't make new ones there) in a group of their own, by their group label.
	readonly property var groups: {
		var accounts = view ? view.taskAccounts : []
		var lists = view ? view.allLists : []
		var out = accounts.map(function(account) {
			return {
				account: account,
				label: account.label,
				lists: lists.filter(function(list) { return String(list.id).indexOf(account.id + '::') === 0 }),
			}
		})
		var rest = lists.filter(function(list) {
			return !accounts.some(function(account) { return String(list.id).indexOf(account.id + '::') === 0 })
		})
		rest.forEach(function(list) {
			var group = out.filter(function(g) { return !g.account && g.label === list.group })[0]
			if (!group) {
				group = { account: null, label: list.group || "", lists: [] }
				out.push(group)
			}
			group.lists.push(list)
		})
		return out
	}

	function close() {
		view.cancelRename()
		view.confirmDeleteListId = ""
		view.addingList = false
		view.newListDraft = ""
		view.managing = false
	}

	spacing: Kirigami.Units.smallSpacing

	// Back, "Manage lists".
	Item {
		Layout.fillWidth: true
		implicitHeight: headerRow.implicitHeight
		RowLayout {
			id: headerRow
			x: column.x
			width: column.width
			spacing: Kirigami.Units.smallSpacing
			PlasmaComponents3.ToolButton {
				Layout.leftMargin: Math.max(0, manage.view.sideMargin - Kirigami.Units.smallSpacing)
				icon.name: Qt.application.layoutDirection === Qt.RightToLeft ? "go-next" : "go-previous"
				display: QQC2.AbstractButton.IconOnly
				text: i18n("Back")
				onClicked: manage.close()
				PlasmaComponents3.ToolTip.text: text
				PlasmaComponents3.ToolTip.visible: hovered
			}
			Kirigami.Heading {
				Layout.fillWidth: true
				Layout.minimumWidth: 0
				level: 2
				font.weight: Font.Bold
				font.pointSize: manage.view.titlePointSize
				text: i18n("Manage lists")
				textFormat: Text.PlainText
				elide: Text.ElideRight
			}
		}
	}

	PlasmaComponents3.ScrollView {
		id: scrollView
		Layout.fillWidth: true
		Layout.fillHeight: true
		contentWidth: availableWidth
		QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

		ColumnLayout {
			id: column
			x: Math.round((scrollView.availableWidth - width) / 2)
			width: Math.min(scrollView.availableWidth, manage.view.maxColumnWidth)
			spacing: appletConfig.islands ? appletConfig.cardGap : 0

			Repeater {
				model: manage.groups
				IslandCard {
					id: groupCard
					readonly property var group: modelData
					Layout.fillWidth: true
					Layout.topMargin: appletConfig.islands && index === 0 ? Kirigami.Units.smallSpacing : 0
					padding: shown ? Kirigami.Units.smallSpacing : 0

					ColumnLayout {
						spacing: 0
						Kirigami.Separator {
							visible: !appletConfig.islands && index > 0
							Layout.fillWidth: true
							Layout.topMargin: Kirigami.Units.largeSpacing
							opacity: 0.6
						}
						Kirigami.Heading {
							Layout.fillWidth: true
							Layout.minimumWidth: 0
							Layout.leftMargin: manage.view.sideMargin
							Layout.rightMargin: manage.view.sideMargin
							Layout.topMargin: Kirigami.Units.smallSpacing
							Layout.bottomMargin: Kirigami.Units.smallSpacing
							level: 5
							text: groupCard.group.label
							textFormat: Text.PlainText // User text (account label)
							opacity: manage.view.dimOpacity
							elide: Text.ElideRight
						}
						Repeater {
							model: groupCard.group.lists
							ListRow {
								Layout.fillWidth: true
								list: modelData
							}
						}
						PlasmaComponents3.Label {
							visible: groupCard.group.lists.length === 0
							Layout.fillWidth: true
							Layout.leftMargin: manage.view.titleX
							text: i18n("No tasks")
							textFormat: Text.PlainText
							opacity: manage.view.dimOpacity
						}
						NewListRow {
							visible: !!groupCard.group.account
							Layout.fillWidth: true
							account: groupCard.group.account
						}
					}
				}
			}
			Item {
				implicitHeight: Kirigami.Units.largeSpacing
			}
		}
	}

	// A list: color dot (a color menu when it can have one), name (a field while renamed), open
	// count, then its actions. A delete waits for the confirmation below the row.
	component ListRow: ColumnLayout {
		id: listRow
		property var list: null
		readonly property string listId: list ? list.id : ""
		readonly property var caps: manage.view.listCaps(listId)
		readonly property bool renaming: !!listId && manage.view.renamingListId === listId
		readonly property bool confirming: !!listId && manage.view.confirmDeleteListId === listId
		readonly property bool busy: !!listId && manage.view.busyListId === listId
		readonly property bool idle: !manage.view.busyListId
		readonly property bool inSmartLists: !manage.view.smartHidden[listId]
		readonly property int openCount: manage.view.filterCounts['list:' + listId] || 0
		readonly property string errorText: manage.view.listErrors[listId] || ""
		readonly property real dotSize: Math.round(Kirigami.Units.gridUnit * 0.7)
		spacing: 0

		Rectangle {
			Layout.fillWidth: true
			implicitHeight: row.implicitHeight + 4
			radius: Kirigami.Units.cornerRadius
			color: hover.hovered && !listRow.renaming ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.06) : "transparent"
			HoverHandler {
				id: hover
			}
			RowLayout {
				id: row
				anchors.left: parent.left
				anchors.right: parent.right
				anchors.verticalCenter: parent.verticalCenter
				spacing: 0

				// The dot lined up with the task checks; a button when the list's color can change.
				QQC2.AbstractButton {
					id: colorButton
					Layout.leftMargin: manage.view.sideMargin + (manage.view.checkSize - implicitWidth) / 2
					Layout.rightMargin: manage.view.titleX - manage.view.sideMargin - (manage.view.checkSize + implicitWidth) / 2
					implicitWidth: listRow.dotSize + 6
					implicitHeight: implicitWidth
					enabled: !!listRow.caps.color && listRow.idle
					hoverEnabled: true
					text: i18n("Color")
					contentItem: Item {}
					background: Rectangle {
						radius: width / 2
						color: "transparent"
						border.width: colorButton.enabled && colorButton.hovered ? 1 : 0
						border.color: Kirigami.Theme.textColor
						Rectangle {
							anchors.centerIn: parent
							width: listRow.dotSize
							height: width
							radius: width / 2
							color: manage.view.listDotColor(listRow.list)
						}
					}
					onClicked: manage.view.openColorMenu(listRow.list, colorButton, 0, colorButton.height)
					PlasmaComponents3.ToolTip.text: text
					PlasmaComponents3.ToolTip.visible: hovered
				}
				PlasmaComponents3.Label {
					visible: !listRow.renaming
					Layout.minimumWidth: 0
					Layout.maximumWidth: Math.ceil(implicitWidth)
					Layout.fillWidth: true
					text: listRow.list ? listRow.list.name : ""
					textFormat: Text.PlainText // User text (list name)
					font.weight: Font.DemiBold
					opacity: listRow.inSmartLists ? 1 : manage.view.dimOpacity
					elide: Text.ElideRight
				}
				PlasmaComponents3.Label {
					visible: !listRow.renaming && listRow.openCount > 0
					Layout.leftMargin: Kirigami.Units.smallSpacing
					text: String(listRow.openCount)
					textFormat: Text.PlainText
					opacity: manage.view.dimOpacity
					Accessible.name: i18np("%1 open task", "%1 open tasks", listRow.openCount)
				}
				Item {
					visible: !listRow.renaming
					Layout.fillWidth: true
					Layout.minimumWidth: Kirigami.Units.smallSpacing
				}
				// Rename: Enter saves, Esc cancels.
				Loader {
					active: listRow.renaming
					visible: active
					Layout.fillWidth: true
					Layout.minimumWidth: 0
					Layout.rightMargin: Kirigami.Units.smallSpacing
					sourceComponent: PlasmaComponents3.TextField {
						text: manage.view.renameDraft
						topPadding: 2
						bottomPadding: 2
						font.weight: Font.DemiBold
						readOnly: listRow.busy
						Accessible.name: i18n("List name")
						Component.onCompleted: {
							forceActiveFocus()
							selectAll()
						}
						onTextEdited: manage.view.renameDraft = text
						onAccepted: manage.view.commitRename(listRow.list, text)
						Keys.onEscapePressed: function(event) {
							manage.view.cancelRename()
							event.accepted = true
						}
					}
				}
				PlasmaComponents3.BusyIndicator {
					visible: listRow.busy
					running: visible
					Layout.preferredWidth: Kirigami.Units.iconSizes.small
					Layout.preferredHeight: Kirigami.Units.iconSizes.small
				}
				ActionButton {
					visible: listRow.renaming && !listRow.busy
					icon.name: "dialog-ok-apply"
					text: i18n("Save")
					onClicked: manage.view.commitRename(listRow.list, manage.view.renameDraft)
				}
				ActionButton {
					visible: listRow.renaming && !listRow.busy
					icon.name: "dialog-cancel"
					text: i18n("Cancel")
					onClicked: manage.view.cancelRename()
				}
				// Like TickTick's Someday: the list's tasks only on its own filter.
				ActionButton {
					visible: !listRow.renaming
					icon.name: listRow.inSmartLists ? "view-visible" : "view-hidden"
					text: i18n("Show in smart lists")
					Accessible.role: Accessible.CheckBox
					Accessible.checkable: true
					Accessible.checked: listRow.inSmartLists
					opacity: listRow.inSmartLists ? 1 : manage.view.dimOpacity
					onClicked: manage.view.setShownInSmartLists(listRow.list, !listRow.inSmartLists)
				}
				ActionButton {
					visible: !listRow.renaming
					available: !!listRow.caps.rename
					enabled: available && listRow.idle
					icon.name: "edit-rename"
					text: i18n("Rename…")
					onClicked: manage.view.startRename(listRow.list)
				}
				ActionButton {
					visible: !listRow.renaming
					available: !!listRow.caps.clearCompleted
					enabled: available && listRow.idle
					icon.name: "edit-clear-history"
					text: i18n("Clear completed")
					onClicked: manage.view.clearCompleted(listRow.list)
				}
				ActionButton {
					visible: !listRow.renaming
					available: !!listRow.caps.delete
					enabled: available && listRow.idle && !listRow.confirming
					icon.name: "edit-delete"
					text: i18n("Delete list…")
					onClicked: manage.view.askDelete(listRow.list)
				}
				Item {
					implicitWidth: Math.max(0, manage.view.sideMargin - Kirigami.Units.smallSpacing)
				}
			}
		}
		// Delete: confirmed here first.
		ColumnLayout {
			visible: listRow.confirming
			Layout.fillWidth: true
			Layout.leftMargin: manage.view.titleX
			Layout.rightMargin: manage.view.sideMargin
			Layout.topMargin: Kirigami.Units.smallSpacing
			Layout.bottomMargin: Kirigami.Units.smallSpacing
			spacing: Kirigami.Units.smallSpacing
			PlasmaComponents3.Label {
				Layout.fillWidth: true
				Layout.minimumWidth: 0
				text: listRow.confirming ? i18ncp("%2 = task list name", "Delete the list \"%2\" and its %1 task? This can't be undone.", "Delete the list \"%2\" and its %1 tasks? This can't be undone.", manage.view.listTaskCount(listRow.listId), listRow.list.name) : ""
				textFormat: Text.PlainText // User text (list name)
				wrapMode: Text.Wrap
			}
			RowLayout {
				spacing: Kirigami.Units.smallSpacing
				PlasmaComponents3.Button {
					icon.name: "edit-delete"
					text: i18n("Delete")
					onClicked: manage.view.deleteList(listRow.list)
				}
				PlasmaComponents3.Button {
					text: i18n("Cancel")
					onClicked: manage.view.confirmDeleteListId = ""
				}
			}
		}
		PlasmaComponents3.Label {
			visible: !!listRow.errorText
			Layout.fillWidth: true
			Layout.minimumWidth: 0
			Layout.leftMargin: manage.view.titleX
			Layout.rightMargin: manage.view.sideMargin
			text: listRow.errorText
			textFormat: Text.PlainText
			color: Kirigami.Theme.negativeTextColor
			elide: Text.ElideRight
		}
	}

	// "New list" in this account: a button, then a field (Enter makes the list, Esc closes it).
	component NewListRow: ColumnLayout {
		id: newList
		property var account: null
		readonly property bool open: !!account && manage.view.addingList && manage.view.newListAccount === account.id
		readonly property bool busy: open && manage.view.busyListId === "new"
		readonly property string errorText: open ? (manage.view.listErrors[""] || "") : ""
		spacing: 0
		PlasmaComponents3.ToolButton {
			visible: !newList.open
			// Its "+" where the dots are.
			Layout.leftMargin: Math.max(0, manage.view.sideMargin + (manage.view.checkSize - icon.width) / 2 - leftPadding)
			Layout.topMargin: 2
			icon.name: "list-add"
			icon.width: Kirigami.Units.iconSizes.small
			icon.height: Kirigami.Units.iconSizes.small
			text: i18n("New list")
			enabled: !manage.view.busyListId
			opacity: hovered ? 1 : 0.8
			onClicked: {
				manage.view.cancelRename()
				manage.view.newListDraft = ""
				manage.view.newListAccount = newList.account.id
				manage.view.addingList = true
			}
		}
		RowLayout {
			visible: newList.open
			Layout.fillWidth: true
			Layout.topMargin: Kirigami.Units.smallSpacing
			Layout.leftMargin: manage.view.sideMargin
			Layout.rightMargin: manage.view.sideMargin - Kirigami.Units.smallSpacing
			spacing: Kirigami.Units.smallSpacing
			PlasmaComponents3.TextField {
				id: newListField
				Layout.fillWidth: true
				Layout.minimumWidth: 0
				placeholderText: i18n("New list name")
				text: manage.view.newListDraft
				readOnly: newList.busy
				onTextEdited: manage.view.newListDraft = text
				onAccepted: manage.view.createList(text)
				Keys.onEscapePressed: function(event) {
					manage.view.addingList = false
					manage.view.newListDraft = ""
					event.accepted = true
				}
				onVisibleChanged: {
					if (visible) {
						forceActiveFocus()
					}
				}
			}
			PlasmaComponents3.BusyIndicator {
				visible: newList.busy
				running: visible
				Layout.preferredWidth: Kirigami.Units.iconSizes.small
				Layout.preferredHeight: Kirigami.Units.iconSizes.small
			}
			ActionButton {
				visible: !newList.busy
				icon.name: "dialog-ok-apply"
				text: i18n("Create")
				enabled: TaskLists.cleanTitle(manage.view.newListDraft) !== ""
				onClicked: manage.view.createList(manage.view.newListDraft)
			}
			ActionButton {
				visible: !newList.busy
				icon.name: "dialog-cancel"
				text: i18n("Cancel")
				onClicked: {
					manage.view.addingList = false
					manage.view.newListDraft = ""
				}
			}
		}
		PlasmaComponents3.Label {
			visible: !!newList.errorText
			Layout.fillWidth: true
			Layout.minimumWidth: 0
			Layout.leftMargin: manage.view.sideMargin
			Layout.rightMargin: manage.view.sideMargin
			text: newList.errorText
			textFormat: Text.PlainText
			color: Kirigami.Theme.negativeTextColor
			elide: Text.ElideRight
		}
		Item {
			implicitHeight: Kirigami.Units.smallSpacing
		}
	}

	// A row's action: an icon, its name in the tooltip. Not available for the list: its place kept
	// empty, so the actions of all the lists line up.
	component ActionButton: PlasmaComponents3.ToolButton {
		property bool available: true
		opacity: available ? 1 : 0
		icon.width: Kirigami.Units.iconSizes.small
		icon.height: Kirigami.Units.iconSizes.small
		display: QQC2.AbstractButton.IconOnly
		PlasmaComponents3.ToolTip.text: text
		PlasmaComponents3.ToolTip.visible: hovered
	}
}
