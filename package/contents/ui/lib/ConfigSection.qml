import QtQuick
import QtQuick.Layouts

// A part of a settings page shown in one of its tabs (config/ConfigCalendars.qml): its items read
// and write the settings through the page's configBridge, given when the tab is loaded, so they're
// applied with the page (OK / Apply). pimSelection: the page's PimCalendarSelection (the KDE PIM
// calendars to show), for the tabs that list them.
ColumnLayout {
	property QtObject configBridge: null
	property var pimSelection: null
	spacing: 0
}
