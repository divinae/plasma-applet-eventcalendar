import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kirigamiaddons.formcard as FormCard

import "../lib"
import "../calendars/PlasmaCalendarUtils.js" as PlasmaCalendarUtils

// Where the events come from: Plasma's calendar plugins (holidays, KDE PIM), how often they're
// fetched, and importing an .ics file. Google and CalDAV accounts have their own pages.
ConfigSection {
	id: page
	property var eventPluginsManager: null

	// From digitalclock's configCalendar.qml
	signal configurationChanged()
	function saveConfig() {
		if (!eventPluginsManager) {
			return
		}
		var enabledPluginFilenames = PlasmaCalendarUtils.pluginPathToFilenameList(eventPluginsManager.enabledPlugins)
		page.configBridge.write("enabledCalendarPlugins", enabledPluginFilenames)
		page.configBridge.write("enabledCalendarPluginsAllowEmpty", enabledPluginFilenames.length === 0)
	}
	Component.onCompleted: {
		try {
			eventPluginsManager = Qt.createQmlObject(
				"import org.kde.plasma.workspace.calendar as PlasmaCalendar; PlasmaCalendar.EventPluginsManager {}",
				page
			)
		} catch (e) {
			console.warn("[eventcalendar] PlasmaCalendar.EventPluginsManager unavailable:", e)
			return
		}
		PlasmaCalendarUtils.populateEnabledPluginsByFilename(
			eventPluginsManager,
			page.configBridge.read("enabledCalendarPlugins", []),
			page.configBridge.read("enabledCalendarPluginsAllowEmpty", false)
		)
	}

	ColumnLayout {
		Layout.fillWidth: true
		spacing: 0

		FormCard.FormHeader {
			title: i18n("Calendars")
		}
		FormCard.FormCard {
			// The events of an .ics file (exported from another calendar app) copied into one of your
			// calendars: the widget opens its import card for it (importRequest, see main.qml), as
			// the widget menu's "Import Events…".
			FormCard.FormButtonDelegate {
				icon.name: "document-import"
				text: i18n("Import Events from a File…")
				description: i18n("Copy the events of an .ics file (exported from another calendar app) into one of your calendars. The widget shows them first, to pick the calendar.")
				onClicked: importFileDialog.open()
			}
			FileDialog {
				id: importFileDialog
				title: i18n("Import Events")
				nameFilters: [ i18n("iCalendar (*.ics)") ]
				// Straight to the widget (not a setting applied with OK, no cfg_ property).
				onAccepted: page.configBridge.write("importRequest", Date.now() + "|" + String(selectedFile))
			}
			FormCard.FormDelegateSeparator {}
			FormConfigSwitch {
				text: i18n("Share events with Glance")
				description: i18n("Today's and tomorrow's events, with meeting links, for the Glance panel widget. Only on this computer; no descriptions or guest addresses.")
				configKey: 'glanceShareEvents'
			}
			FormCard.FormDelegateSeparator {}
			FormConfigSpin {
				label: i18n("Refresh every")
				configKey: 'eventsPollInterval'
				suffix: i18nc("Polling interval in minutes", " min")
				from: 5
				to: 90
			}
			FormCard.FormDelegateSeparator {}
			FormCard.FormTextDelegate {
				visible: !page.eventPluginsManager
				text: i18n("Plasma calendar plugins are unavailable.")
			}
			FormCard.AbstractFormDelegate {
				visible: !!page.eventPluginsManager
				background: null
				contentItem: ColumnLayout {
					spacing: 0
					QQC2.Label {
						text: i18n("Plasma calendars")
					}
					// A Repeater needs a layout parent (it breaks form layouts' child handling).
					Repeater {
						model: page.eventPluginsManager ? page.eventPluginsManager.model : null
						delegate: QQC2.CheckBox {
							text: model.display
							checked: model.checked
							onClicked: {
								model.checked = checked // needed for model's setData to be called
								page.saveConfig()
							}
						}
					}
				}
			}
		}
	}
}
