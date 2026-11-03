import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import "../lib"

// Calendars: where the events come from, in tabs. General (Plasma's calendar plugins, the refresh
// interval, importing an .ics file), Google Calendar accounts, the KDE PIM (Akonadi) calendars,
// CalDAV accounts, .ics files and links. The Akonadi calendars to show (the PIM events plugin's
// selection, its own settings page otherwise) are ticked in the Akonadi tab. A tab is loaded the
// first time it's shown and kept: its changes are applied with the page.
ConfigPage {
	id: page

	// The PIM events plugin's selection, saved with the page (the dialog calls saveConfig on OK /
	// Apply; configurationChanged enables Apply).
	signal configurationChanged()
	function saveConfig() {
		pimSelection.save()
	}
	PimCalendarSelection {
		id: pimSelection
		configBridge: page.configBridge
		onChanged: page.configurationChanged()
	}

	property int currentTab: 0
	readonly property var tabs: [
		{ title: i18n("General"), iconName: "office-calendar", source: "CalendarsGeneral.qml" },
		{ title: i18n("Google Calendar"), iconSource: Qt.resolvedUrl("../../icons/google_calendar_96px.png"), source: "CalendarsGoogle.qml" },
		{ title: i18n("Akonadi"), iconName: "akonadiconsole", source: "CalendarsAkonadi.qml" },
		{ title: i18n("CalDAV"), iconName: "folder-cloud", source: "CalendarsCalDAV.qml" },
		{ title: i18n("iCalendar"), iconName: "text-calendar", source: "CalendarsICal.qml" },
	]

	header: QQC2.TabBar {
		id: tabBar
		currentIndex: page.currentTab
		onCurrentIndexChanged: page.currentTab = currentIndex
		Repeater {
			model: page.tabs
			QQC2.TabButton {
				text: modelData.title
				icon.name: modelData.iconName || ""
				icon.source: modelData.iconSource || ""
			}
		}
	}

	ColumnLayout {
		Layout.fillWidth: true
		spacing: 0
		Repeater {
			model: page.tabs
			Loader {
				Layout.fillWidth: true
				visible: page.currentTab === index
				function load() {
					if (visible && status === Loader.Null) {
						setSource(Qt.resolvedUrl(modelData.source), { configBridge: page.configBridge, pimSelection: pimSelection })
					}
				}
				onVisibleChanged: load()
				Component.onCompleted: load()
			}
		}
	}
}
