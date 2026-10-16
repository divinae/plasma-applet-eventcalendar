import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "Shared.js" as Shared
import "lib/ColorUtil.js" as ColorUtil

// Quick add: one line like "Lunch with Anna tomorrow 13:00". Google Calendar reads the day,
// time and place from the text; other calendars get an all-day event with the text as its title.
Rectangle {
	id: quickAdd

	property date date: new Date() // The selected day
	signal closeRequested()
	signal moreOptionsRequested(string title)

	readonly property string text: textField.text.trim()
	readonly property bool isToday: Shared.isSameDate(date, new Date())
	readonly property bool canAdd: text.length > 0 && !!calendarSelector.selectedCalendarId

	color: Kirigami.Theme.backgroundColor
	radius: Kirigami.Units.cornerRadius * 2
	border.width: 1
	border.color: ColorUtil.setAlpha(Kirigami.Theme.textColor, 0.15)
	implicitHeight: actionsRow.implicitHeight + Kirigami.Units.smallSpacing * 2 + 1
		+ fieldsColumn.implicitHeight + Kirigami.Units.largeSpacing * 2

	function add() {
		if (!canAdd) {
			textField.forceActiveFocus()
			return
		}
		// Today: no date, so "tomorrow" or "Friday" in the text count from today.
		// Another selected day: the event goes on that day unless the text says otherwise.
		eventModel.createEvent(calendarSelector.selectedCalendarId, isToday ? null : date, text)
		closeRequested()
	}

	Keys.onEscapePressed: closeRequested()
	Component.onCompleted: {
		var calendarList = eventModel.getCalendarList().filter(function(c) { return !c.isTasklist })
		calendarSelector.populate(calendarList, plasmoid.configuration.agendaNewEventLastCalendarId)
		textField.forceActiveFocus()
	}

	ColumnLayout {
		anchors.fill: parent
		spacing: 0

		// Cancel on the left, title centered, Add on the right.
		Item {
			id: actionsRow
			Layout.fillWidth: true
			Layout.margins: Kirigami.Units.smallSpacing
			implicitHeight: Math.max(cancelButton.implicitHeight, addButton.implicitHeight, cardTitle.implicitHeight)

			PlasmaComponents3.ToolButton {
				id: cancelButton
				anchors.left: parent.left
				anchors.verticalCenter: parent.verticalCenter
				icon.name: "go-previous"
				text: i18n("Cancel")
				onClicked: quickAdd.closeRequested()
			}
			Kirigami.Heading {
				id: cardTitle
				anchors.centerIn: parent
				width: Math.min(implicitWidth, parent.width - Math.max(cancelButton.width, addButton.width) * 2 - Kirigami.Units.largeSpacing * 2)
				horizontalAlignment: Text.AlignHCenter
				level: 3
				elide: Text.ElideRight
				text: i18n("Quick Add")
			}
			PlasmaComponents3.Button {
				id: addButton
				anchors.right: parent.right
				anchors.verticalCenter: parent.verticalCenter
				icon.name: "list-add"
				text: i18n("Add")
				enabled: quickAdd.canAdd
				onClicked: quickAdd.add()
			}
		}

		Kirigami.Separator {
			Layout.fillWidth: true
		}

		ColumnLayout {
			id: fieldsColumn
			Layout.fillWidth: true
			Layout.margins: Kirigami.Units.largeSpacing
			spacing: Kirigami.Units.largeSpacing

			PlasmaComponents3.TextField {
				id: textField
				Layout.fillWidth: true
				placeholderText: i18nc("quick add example", "Lunch with Anna tomorrow 13:00")
				font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.3
				onAccepted: quickAdd.add()
				Keys.onEscapePressed: quickAdd.closeRequested()
			}

			PlasmaComponents3.Label {
				Layout.fillWidth: true
				wrapMode: Text.Wrap
				opacity: 0.6
				font: Kirigami.Theme.smallFont
				text: quickAdd.isToday
					? i18n("Type what, when and where. Without a day, the event is added today.")
					: i18nc("%1 = date", "Type what, when and where. Without a day, the event is added on %1.",
						Qt.formatDate(quickAdd.date, Qt.locale().dateFormat(Locale.LongFormat)))
			}

			CalendarSelector {
				id: calendarSelector
				Layout.fillWidth: true
			}

			PlasmaComponents3.ToolButton {
				Layout.alignment: Qt.AlignRight
				icon.name: "document-edit"
				text: i18n("More options…")
				onClicked: quickAdd.moreOptionsRequested(quickAdd.text)
			}
		}
	}
}
