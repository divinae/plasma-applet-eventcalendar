import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kirigamiaddons.formcard as FormCard

import "../lib"

// Calendars > Akonadi: the KDE PIM calendars to show through the PIM events plugin (turned on in
// the General tab), Akonadi's Google accounts first. See PimCalendarSelection.
ConfigSection {
	id: page

	readonly property bool pimEventsEnabled: !!pimSelection && pimSelection.pimEventsEnabled

	ColumnLayout {
		Layout.fillWidth: true
		spacing: 0

		FormCard.FormSectionText {
			visible: !page.pimEventsEnabled
			text: i18n("Turn on the PIM Events plugin in the General tab (Plasma calendars) to show the calendars of KDE PIM (Akonadi).")
		}

		// Older kdepim-addons: the model can't tick (config.qml keeps the plugin's own page then).
		FormCard.FormSectionText {
			visible: page.pimEventsEnabled && !!page.pimSelection && !!page.pimSelection.model && !page.pimSelection.canChange
			text: i18n("This version of KDE PIM can't change the selection here: choose the calendars on the PIM Events Plugin page of these settings.")
		}

		PimCalendarList {
			Layout.fillWidth: true
			visible: page.pimEventsEnabled
			selection: page.pimSelection
			groups: page.pimSelection ? page.pimSelection.groups : []
		}

		// Calendars still selected that Akonadi no longer has: forgotten with the page (OK / Apply).
		FormCard.FormCard {
			visible: page.pimEventsEnabled && !!page.pimSelection && page.pimSelection.missing.length > 0
			Layout.topMargin: Kirigami.Units.largeSpacing
			FormCard.AbstractFormDelegate {
				background: null
				contentItem: Kirigami.InlineMessage {
					visible: true
					type: Kirigami.MessageType.Warning
					text: i18np("One calendar selected in the PIM events plugin no longer exists in Akonadi, eg because its account was set up anew, which gives its calendars new ids.",
						"%1 calendars selected in the PIM events plugin no longer exist in Akonadi, eg because their account was set up anew, which gives its calendars new ids.",
						page.pimSelection ? page.pimSelection.missing.length : 0)
					actions: [
						Kirigami.Action {
							icon.name: "edit-clear-history"
							text: i18n("Forget the Missing Ones")
							enabled: !!page.pimSelection && page.pimSelection.canChange
							onTriggered: page.pimSelection.forgetMissing()
						}
					]
				}
			}
		}

		FormCard.FormSectionText {
			visible: page.pimEventsEnabled
			text: i18n("In the popup's calendar menu they are shown and hidden by color: calendars of one color together.")
		}
	}
}
