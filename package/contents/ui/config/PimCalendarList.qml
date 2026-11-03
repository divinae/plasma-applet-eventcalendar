import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kirigamiaddons.formcard as FormCard

// KDE PIM (Akonadi) calendars to tick, under their accounts (PimCalendarSelection.groups): a
// header and a card per account; a calendar's kind as its icon (eg: a task list, which has no
// color), its color as in the popup's calendar menu.
ColumnLayout {
	id: list
	property var selection: null // PimCalendarSelection
	property var groups: []
	spacing: 0

	Repeater {
		model: list.groups
		ColumnLayout {
			id: group
			required property var modelData
			Layout.fillWidth: true
			spacing: 0

			FormCard.FormHeader {
				title: group.modelData.name || i18n("KDE PIM (Akonadi)")
			}
			FormCard.FormCard {
				Repeater {
					model: group.modelData.calendars
					FormCard.FormCheckDelegate {
						id: calendarRow
						required property var modelData
						readonly property string calendarColor: list.selection.colors[modelData.id] || ""
						text: modelData.name
						description: list.selection.mirrored[modelData.id]
							? i18n("Its events come from the account signed in to in the Google Calendar tab.")
							: ""
						checked: modelData.checked
						enabled: list.selection.canChange
						onToggled: list.selection.setChecked(modelData.id, checked)
						leading: Kirigami.Icon {
							visible: !!calendarRow.modelData.icon
							source: calendarRow.modelData.icon || ""
							implicitWidth: Kirigami.Units.iconSizes.smallMedium
							implicitHeight: implicitWidth
						}
						trailing: Rectangle {
							visible: !!calendarRow.calendarColor
							implicitWidth: Kirigami.Units.iconSizes.small * 0.75
							implicitHeight: implicitWidth
							radius: width / 2
							color: calendarRow.calendarColor || "transparent"
						}
					}
				}
			}
		}
	}
}
