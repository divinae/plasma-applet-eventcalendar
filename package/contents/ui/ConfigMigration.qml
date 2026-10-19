import QtQuick

import "./calendars/PlasmaCalendarUtils.js" as PlasmaCalendarUtils

QtObject {
	signal migrate()
	readonly property bool showDebug: typeof plasmoid !== "undefined"
		&& plasmoid.configuration
		&& plasmoid.configuration.debugging === true

	function logMigration(message) {
		if (showDebug) {
			console.log("[eventcalendar:migrate] " + message)
		}
	}

	Component.onCompleted: migrate()
	onMigrate: {
		// The Year view (briefly on master before 1.3) was removed: back to the month view.
		if (plasmoid.configuration.popupMode === 'year') {
			plasmoid.configuration.popupMode = 'month'
			logMigration('popupMode year => month')
		}

		// Modified in: v72
		if (!plasmoid.configuration.v72Migration) {
			var oldValue = plasmoid.configuration.enabledCalendarPlugins
			var newValue = PlasmaCalendarUtils.pluginPathToFilenameList(plasmoid.configuration.enabledCalendarPlugins)
			plasmoid.configuration.enabledCalendarPlugins = newValue
			logMigration('convert enabledCalendarPlugins (' + oldValue + ' => ' + newValue + ')')

			plasmoid.configuration.v72Migration = true
		}

		// Added in: v73
		if (!plasmoid.configuration.v73Migration) {
			if (!plasmoid.configuration.enabledCalendarPluginsAllowEmpty) {
				var oldEnabledCalendarPlugins = plasmoid.configuration.enabledCalendarPlugins
				var newEnabledCalendarPlugins = PlasmaCalendarUtils.getEffectivePluginFilenameList(
					null,
					oldEnabledCalendarPlugins,
					false
				)
				plasmoid.configuration.enabledCalendarPlugins = newEnabledCalendarPlugins
				logMigration('fallback enabledCalendarPlugins (' + oldEnabledCalendarPlugins + ' => ' + newEnabledCalendarPlugins + ')')
			}

			plasmoid.configuration.v73Migration = true
		}
	}

}
