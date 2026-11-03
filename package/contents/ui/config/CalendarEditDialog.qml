import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import "../lib"
import "../code/GooglePalette.js" as GooglePalette

// Edit a Google calendar: its name (the calendar's own name when the user owns it, otherwise the
// name in their list) and its color, picked from Google Calendar's colors.
Dialog {
	id: editDialog
	title: i18n("Edit Calendar")
	modal: true
	parent: Overlay.overlay
	anchors.centerIn: parent
	width: Math.min(Kirigami.Units.gridUnit * 24, parent ? parent.width - Kirigami.Units.gridUnit * 2 : Kirigami.Units.gridUnit * 24)

	property var loginManager: null
	property string accountId: ""
	property var calendar: null
	property string selectedColor: ""
	property bool saving: false
	property string errorText: ""

	readonly property bool canRename: !!loginManager && loginManager.canRenameCalendar(calendar)

	signal saved()

	function openFor(accountId, calendar) {
		editDialog.accountId = accountId
		editDialog.calendar = calendar
		nameField.text = calendar ? (calendar.summaryOverride || calendar.summary || "") : ""
		selectedColor = calendar ? String(GooglePalette.calendarColor(calendar) || "").toLowerCase() : ""
		errorText = ""
		saving = false
		open()
		nameField.forceActiveFocus()
	}

	function save() {
		if (!loginManager || !calendar || saving) {
			return
		}
		saving = true
		errorText = ""
		// Unchanged color: send the calendar's own value, so nothing is written.
		var shownColor = String(GooglePalette.calendarColor(calendar) || "").toLowerCase()
		var color = selectedColor === shownColor ? calendar.backgroundColor : selectedColor
		loginManager.saveCalendarChanges(accountId, calendar, {
			name: nameField.text,
			color: color,
		}, function(err) {
			saving = false
			if (err) {
				errorText = err
				return
			}
			editDialog.saved()
			editDialog.close()
		})
	}

	contentItem: ColumnLayout {
		spacing: Kirigami.Units.smallSpacing

		Label {
			text: editDialog.canRename ? i18n("Name") : i18n("Name in my list")
		}
		TextField {
			id: nameField
			Layout.fillWidth: true
			enabled: !editDialog.saving
			placeholderText: editDialog.calendar ? (editDialog.calendar.summary || "") : ""
			onAccepted: editDialog.save()
		}
		Label {
			Layout.fillWidth: true
			visible: !editDialog.canRename
			text: i18n("Only you see this name. The calendar keeps its name for others.")
			wrapMode: Text.Wrap
			opacity: 0.7
			font: Kirigami.Theme.smallFont
		}

		Label {
			Layout.topMargin: Kirigami.Units.largeSpacing
			text: i18n("Color")
		}
		ColorSwatchGrid {
			id: colorGrid
			Layout.alignment: Qt.AlignHCenter
			enabled: !editDialog.saving
			selectedColor: editDialog.selectedColor
			onPicked: function(color) { editDialog.selectedColor = color }
		}

		Kirigami.InlineMessage {
			Layout.fillWidth: true
			Layout.topMargin: Kirigami.Units.smallSpacing
			visible: editDialog.errorText !== ""
			type: Kirigami.MessageType.Error
			text: editDialog.errorText
		}
	}

	// Save isn't the accept role: the dialog stays open until Google answers (and on an error).
	footer: DialogButtonBox {
		Button {
			text: i18n("Save")
			icon.name: "document-save"
			enabled: !editDialog.saving && !!editDialog.calendar
			DialogButtonBox.buttonRole: DialogButtonBox.ApplyRole
			onClicked: editDialog.save()
		}
		Button {
			text: i18n("Cancel")
			icon.name: "dialog-cancel"
			DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
		}
	}
}
