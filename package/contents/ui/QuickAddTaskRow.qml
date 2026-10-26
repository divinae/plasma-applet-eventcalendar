import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "Tasks.js" as Tasks

// "Add a task…" at the bottom of a task list (Tasks view) or of the day's tasks (Day view): a flat
// field lined up with the TaskRows, a "+" where their check is. Enter adds the task (on listId,
// else on the picked one of lists, due on dueDay or undated) without the editor, then the field is
// empty and ready for the next one; Esc empties it, or leaves it when empty.
Item {
	id: quickAdd

	property var eventModel: null
	// The list to add to; '' picks one of lists (the last used, else the first), with a picker when
	// there are several.
	property string listId: ""
	property var lists: []
	// The new task's due day, 'YYYY-MM-DD', or '' for none.
	property string dueDay: ""
	// Lined up with compact TaskRows (Day view).
	property bool compact: false

	// The Tasks view makes its rows again on every change: the text typed so far and the focus
	// are kept in addDrafts ({ key: { text, focused } }, owned by the view) under draftKey.
	property string draftKey: ""
	property var addDrafts: null
	Component.onCompleted: {
		var draft = addDrafts && draftKey ? addDrafts[draftKey] : null
		if (draft) {
			field.text = draft.text || ""
			if (draft.focused) {
				field.forceActiveFocus()
			}
		}
	}
	function saveDraft() {
		if (addDrafts && draftKey) {
			var draft = addDrafts[draftKey] || {}
			draft.text = field.text
			addDrafts[draftKey] = draft
		}
	}

	property bool saving: false
	property string errorText: ""
	property string pickedListId: ""
	readonly property string targetListId: listId || Tasks.quickAddList(lists, pickedListId || String(plasmoid.configuration.tasksLastListId || ""))
	readonly property var targetList: {
		for (var i = 0; i < lists.length; i++) {
			if (lists[i].id === targetListId) {
				return lists[i]
			}
		}
		return null
	}
	readonly property bool showPicker: !listId && lists.length > 1
	readonly property real sideMargin: compact ? Kirigami.Units.smallSpacing * 2 : Kirigami.Units.largeSpacing
	readonly property int checkSize: 2 * Math.round(Math.min(Kirigami.Units.iconSizes.small * 1.1, field.implicitHeight) / 2)

	implicitWidth: layout.implicitWidth + sideMargin * 2
	implicitHeight: layout.implicitHeight + (compact ? 2 : Kirigami.Units.smallSpacing * 2)

	function add() {
		var body = Tasks.quickAddBody(field.text, dueDay)
		var target = targetListId
		if (!body || !target || saving || !eventModel) {
			return
		}
		saving = true
		errorText = ""
		var row = quickAdd
		var drafts = addDrafts
		var key = draftKey
		eventModel.createEventFromData(target, body, function(err, item) {
			if (!err) {
				plasmoid.configuration.tasksLastListId = target
				if (drafts && key && drafts[key]) {
					drafts[key].text = ""
				}
			}
			if (!row) {
				return // Gone meanwhile (rows made again)
			}
			row.saving = false
			if (err) {
				row.errorText = i18n("Couldn't add the task")
				row.restartErrorTimer()
				return
			}
			row.clear()
		})
	}

	function clear() {
		field.text = ""
	}
	function restartErrorTimer() {
		errorTimer.restart()
	}
	Timer {
		id: errorTimer
		interval: 5000
		onTriggered: quickAdd.errorText = ""
	}

	ColumnLayout {
		id: layout
		anchors.left: parent.left
		anchors.right: parent.right
		anchors.verticalCenter: parent.verticalCenter
		anchors.leftMargin: quickAdd.sideMargin
		anchors.rightMargin: quickAdd.sideMargin
		spacing: 0

		RowLayout {
			Layout.fillWidth: true
			spacing: Kirigami.Units.largeSpacing

			// The "+" where the rows have their check.
			Item {
				Layout.preferredWidth: quickAdd.checkSize
				Layout.preferredHeight: quickAdd.checkSize
				Kirigami.Icon {
					anchors.fill: parent
					visible: !quickAdd.saving
					source: "list-add"
					color: Kirigami.Theme.textColor
					isMask: true
					opacity: field.activeFocus ? 0.9 : 0.7
				}
				PlasmaComponents3.BusyIndicator {
					anchors.centerIn: parent
					width: parent.width + 4
					height: width
					visible: quickAdd.saving
					running: visible
				}
			}

			PlasmaComponents3.TextField {
				id: field
				Layout.fillWidth: true
				Layout.minimumWidth: 0
				leftPadding: 0
				rightPadding: 0
				background: Item {}
				placeholderText: i18n("Add a task…")
				font.family: appletConfig.eventFont.family
				font.pointSize: appletConfig.eventFont.pointSize
				readOnly: quickAdd.saving
				opacity: quickAdd.saving ? 0.6 : 1
				Accessible.name: quickAdd.targetList ? i18nc("%1 = task list name", "Add a task to %1", quickAdd.targetList.name) : placeholderText
				onTextEdited: quickAdd.errorText = ""
				onTextChanged: quickAdd.saveDraft()
				onAccepted: quickAdd.add()
				Keys.onEscapePressed: function(event) {
					if (text) {
						text = ""
						quickAdd.errorText = ""
					} else {
						focus = false
					}
					event.accepted = true
				}
			}

			// The list it adds to, when there's a choice.
			PlasmaComponents3.ToolButton {
				id: pickerButton
				visible: quickAdd.showPicker
				Layout.maximumWidth: Kirigami.Units.gridUnit * 8
				flat: true
				text: quickAdd.targetList ? quickAdd.targetList.name : ""
				Accessible.name: i18nc("%1 = task list name", "Task list: %1", text)
				PlasmaComponents3.ToolTip.text: i18n("The list new tasks go to")
				PlasmaComponents3.ToolTip.visible: hovered
				contentItem: RowLayout {
					spacing: Kirigami.Units.smallSpacing
					Rectangle {
						implicitWidth: Math.round(Kirigami.Units.gridUnit * 0.5)
						implicitHeight: implicitWidth
						radius: width / 2
						color: appletConfig.eventColoredTextColor(appletConfig.eventColor(quickAdd.targetList && quickAdd.targetList.color ? quickAdd.targetList.color : null))
					}
					PlasmaComponents3.Label {
						Layout.fillWidth: true
						Layout.minimumWidth: 0
						text: pickerButton.text
						textFormat: Text.PlainText // User text (list name)
						font: quickAdd.detailFont
						opacity: 0.85
						elide: Text.ElideRight
					}
					Kirigami.Icon {
						implicitWidth: Kirigami.Units.iconSizes.small / 2 + 4
						implicitHeight: implicitWidth
						source: "arrow-down"
						opacity: 0.75
					}
				}
				onClicked: listMenu.popup(pickerButton, 0, pickerButton.height)
			}
		}

		PlasmaComponents3.Label {
			visible: !!quickAdd.errorText
			Layout.fillWidth: true
			Layout.minimumWidth: 0
			Layout.leftMargin: quickAdd.checkSize + Kirigami.Units.largeSpacing
			text: quickAdd.errorText
			textFormat: Text.PlainText
			color: Kirigami.Theme.negativeTextColor
			font: quickAdd.detailFont
			elide: Text.ElideRight
		}
	}

	readonly property font detailFont: appletConfig.scaledFont(appletConfig.eventFont, 0.9)

	PlasmaComponents3.Menu {
		id: listMenu
		Instantiator {
			model: quickAdd.showPicker ? quickAdd.lists : []
			delegate: PlasmaComponents3.MenuItem {
				id: listMenuItem
				readonly property var list: modelData
				text: list.name // Shown by the plain text label below
				readonly property bool current: list.id === quickAdd.targetListId
				contentItem: RowLayout {
					spacing: Kirigami.Units.smallSpacing
					Rectangle {
						implicitWidth: Math.round(Kirigami.Units.gridUnit * 0.5)
						implicitHeight: implicitWidth
						radius: width / 2
						color: appletConfig.eventColoredTextColor(appletConfig.eventColor(listMenuItem.list.color || null))
					}
					PlasmaComponents3.Label {
						Layout.fillWidth: true
						text: listMenuItem.list.name
						textFormat: Text.PlainText // User text (list name)
						font.weight: listMenuItem.current ? Font.DemiBold : Font.Normal
						elide: Text.ElideRight
					}
				}
				onTriggered: {
					quickAdd.pickedListId = list.id
					plasmoid.configuration.tasksLastListId = list.id
					field.forceActiveFocus()
				}
			}
			onObjectAdded: function(index, object) { listMenu.insertItem(index, object) }
			onObjectRemoved: function(index, object) { listMenu.removeItem(object) }
		}
	}
}
