import QtQuick
import QtQuick.Layouts

// A part of a settings page shown in one of its tabs (config/ConfigCalendars.qml): its items read
// and write the settings through the page's configBridge, given when the tab is loaded, so they're
// applied with the page (OK / Apply).
ColumnLayout {
	property QtObject configBridge: null
	spacing: 0
}
