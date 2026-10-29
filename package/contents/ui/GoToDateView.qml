import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "Shared.js" as Shared
import "Tasks.js" as Tasks
import "QuickParse.js" as QuickParse

// Go to date (the G key, like Dato): type a day ("next friday", "15 nov", "+2w") and the view goes
// there. The day understood shows under the field.
Item {
	id: goToDate

	signal closeRequested()
	signal dayChosen(date day)

	readonly property string text: textField.text.trim()
	// 'YYYY-MM-DD', or '' (nothing understood yet).
	readonly property string dayString: text ? QuickParse.goToDate(text, {
		today: Tasks.dayString(new Date()),
		dayFirst: appletConfig.quickParseLocale.dayFirst,
		dayNames: appletConfig.quickParseLocale.dayNames,
		monthNames: appletConfig.quickParseLocale.monthNames,
	}) : ''
	readonly property var day: {
		if (!dayString) {
			return null
		}
		var parts = dayString.split('-')
		return new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
	}
	function go() {
		if (day) {
			dayChosen(day)
		}
	}

	implicitHeight: actionsRow.implicitHeight + Kirigami.Units.smallSpacing * 2 + 1
		+ fieldsColumn.implicitHeight + Kirigami.Units.largeSpacing * 2
	Component.onCompleted: textField.forceActiveFocus()
	Keys.onEscapePressed: closeRequested()

	ColumnLayout {
		anchors.fill: parent
		spacing: 0

		CardHeader {
			id: actionsRow
			Layout.fillWidth: true
			Layout.margins: Kirigami.Units.smallSpacing
			title: i18n("Go to Date")
			actionText: i18n("Go")
			actionIcon: "go-jump"
			actionEnabled: !!goToDate.day
			onCancelClicked: goToDate.closeRequested()
			onActionClicked: goToDate.go()
		}

		Kirigami.Separator {
			Layout.fillWidth: true
		}

		ColumnLayout {
			id: fieldsColumn
			Layout.fillWidth: true
			Layout.margins: Kirigami.Units.largeSpacing
			spacing: Kirigami.Units.smallSpacing

			PlasmaComponents3.TextField {
				id: textField
				Layout.fillWidth: true
				placeholderText: i18n("Eg: next friday, 15 nov, +2w")
				onAccepted: goToDate.go()
				Keys.onEscapePressed: goToDate.closeRequested()
			}
			PlasmaComponents3.Label {
				Layout.fillWidth: true
				text: goToDate.day ? Shared.formatDate(goToDate.day, Locale.LongFormat)
					: goToDate.text ? i18n("No day found in the text") : " "
				textFormat: Text.PlainText
				opacity: goToDate.day ? 0.85 : 0.6
				elide: Text.ElideRight
			}
		}
	}
}
