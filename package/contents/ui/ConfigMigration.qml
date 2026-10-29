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

		// 1.4: Open-Meteo became the default weather service (was OpenWeatherMap). Keep OpenWeatherMap
		// for those who set its city but never picked a service (the old default isn't saved).
		if (plasmoid.configuration.weatherService === 'OpenMeteo'
			&& !plasmoid.configuration.openMeteoLatitude && !plasmoid.configuration.openMeteoLongitude
			&& plasmoid.configuration.openWeatherMapCityId > 0) {
			plasmoid.configuration.weatherService = 'OpenWeatherMap'
			logMigration('weatherService => OpenWeatherMap (its city is set)')
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

		// The view switcher can't be hidden any more (1.8.2): hidden became the small one.
		if (plasmoid.configuration.showViewTabs === false) {
			plasmoid.configuration.viewSwitcher = 'menu'
			plasmoid.configuration.showViewTabs = true
			logMigration('showViewTabs false => viewSwitcher menu')
		}

		// Another (broken) Plasma 6 port stored the plugin list one character per entry: put it
		// back together, or the default plugins when nothing usable is left.
		var plugins = PlasmaCalendarUtils.toArray(plasmoid.configuration.enabledCalendarPlugins)
		var repairedPlugins = PlasmaCalendarUtils.repairPluginList(plugins)
		if (plugins.length > 0 && JSON.stringify(repairedPlugins) !== JSON.stringify(Array.prototype.slice.call(plugins))) {
			plasmoid.configuration.enabledCalendarPlugins = repairedPlugins.length > 0 ? repairedPlugins : ['holidaysevents.so', 'pimevents.so']
			logMigration('repair enabledCalendarPlugins (' + plugins + ' => ' + plasmoid.configuration.enabledCalendarPlugins + ')')
		}
	}

}
