import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import "../lib"

// Calendars: where the events come from, in tabs. General (Plasma's calendar plugins, the refresh
// interval, importing an .ics file), Google Calendar and CalDAV accounts, .ics files and links. A tab is loaded the first
// time it's shown and kept: its changes are applied with the page.
ConfigPage {
	id: page

	property int currentTab: 0
	readonly property var tabs: [
		{ title: i18n("General"), iconName: "office-calendar", source: "CalendarsGeneral.qml" },
		{ title: i18n("Google Calendar"), iconSource: Qt.resolvedUrl("../../icons/google_calendar_96px.png"), source: "CalendarsGoogle.qml" },
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

	component TabSection: Loader {
		property int tabIndex: 0
		Layout.fillWidth: true
		visible: page.currentTab === tabIndex
		function load() {
			if (visible && status === Loader.Null) {
				setSource(Qt.resolvedUrl(page.tabs[tabIndex].source), { configBridge: page.configBridge })
			}
		}
		onVisibleChanged: load()
		Component.onCompleted: load()
	}

	ColumnLayout {
		Layout.fillWidth: true
		spacing: 0
		TabSection { tabIndex: 0 }
		TabSection { tabIndex: 1 }
		TabSection { tabIndex: 2 }
		TabSection { tabIndex: 3 }
	}
}
