import QtQuick
import org.kde.plasma.configuration

import "../ui/calendars/PlasmaCalendarUtils.js" as PlasmaCalendarUtils

ConfigModel {
	id: configModel
	property var eventPluginsManager: null
	readonly property bool hasPlasmoidConfig: typeof plasmoid !== "undefined"
		&& plasmoid
		&& plasmoid.configuration
	readonly property var effectiveEnabledCalendarPlugins: PlasmaCalendarUtils.getEffectivePluginFilenameList(
		eventPluginsManager,
		hasPlasmoidConfig ? plasmoid.configuration.enabledCalendarPlugins : [],
		hasPlasmoidConfig ? plasmoid.configuration.enabledCalendarPluginsAllowEmpty : false
	)

	ConfigCategory {
		name: i18n("Views")
		icon: "view-calendar"
		source: "config/ConfigViews.qml"
	}
	ConfigCategory {
		name: i18n("Clock")
		icon: "clock"
		source: "config/ConfigClock.qml"
	}
	ConfigCategory {
		name: i18n("Events")
		icon: "view-calendar-upcoming-events"
		source: "config/ConfigEvents.qml"
	}
	ConfigCategory {
		name: i18n("Calendars")
		icon: "office-calendar"
		source: "config/ConfigCalendars.qml"
	}
	ConfigCategory {
		name: i18n("Tasks")
		icon: "view-task"
		source: "config/ConfigTasks.qml"
	}
	ConfigCategory {
		name: i18n("Weather")
		icon: "weather-clouds"
		source: "config/ConfigWeather.qml"
	}
	ConfigCategory {
		name: i18n("Time Zones")
		icon: "globe"
		source: "config/ConfigTimezones.qml"
	}
	ConfigCategory {
		name: i18n("Advanced")
		icon: "applications-development"
		source: "lib/ConfigAdvanced.qml"
		visible: hasPlasmoidConfig && plasmoid.configuration.debugging
	}

	// Whether the Akonadi tab can tick calendars (newer kdepim-addons): then the PIM events plugin's
	// own page isn't needed; without it, that page stays. Found out once, only when that page would
	// be shown (a model starts talking to Akonadi).
	property var pimProbe: ({}) // Not a notifying property: written from a binding
	function pimTabCanChoose() {
		if (pimProbe.canChoose === undefined) {
			var model = PlasmaCalendarUtils.createPimCalendarsModel(configModel)
			pimProbe.canChoose = PlasmaCalendarUtils.pimModelCanChoose(model)
			if (model) {
				model.destroy()
			}
		}
		return pimProbe.canChoose
	}
	Component.onCompleted: {
		try {
			eventPluginsManager = Qt.createQmlObject(
				"import org.kde.plasma.workspace.calendar as PlasmaCalendar; PlasmaCalendar.EventPluginsManager {}",
				configModel
			)
		} catch (e) {
			console.warn("[eventcalendar] PlasmaCalendar.EventPluginsManager unavailable:", e)
		}
	}

	property Instantiator __eventPlugins: Instantiator {
		model: eventPluginsManager ? eventPluginsManager.model : null
		delegate: ConfigCategory {
			name: model.display
			icon: model.decoration
			source: model.configUi
			readonly property string pluginFilename: PlasmaCalendarUtils.getModelPluginFilename(eventPluginsManager, index, model)
			// Not the PIM events plugin's when its calendars can be chosen in Calendars > Akonadi
			// (see PimCalendarSelection).
			visible: hasPlasmoidConfig
				&& effectiveEnabledCalendarPlugins.indexOf(pluginFilename) > -1
				&& !(PlasmaCalendarUtils.hasPlugin([pluginFilename], "pimevents") && configModel.pimTabCanChoose())
		}

		onObjectAdded: function(index, object) {
			configModel.appendCategory(object)
		}
		onObjectRemoved: function(index, object) {
			configModel.removeCategory(object)
		}
	}
}
