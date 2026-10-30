import QtQuick
import org.kde.kirigami as Kirigami

import "Shared.js" as Shared
import "./weather/WeatherApi.js" as WeatherApi

// The Day view's side columns for the Agenda (the same layout): left a small month (MiniMonth) and
// below it Up next; right the day's tasks (DayTasksPanel) and below them its weather (WeatherPanel).
// The view places them: leftX / rightX, from topY down to bottomY, sideWidth wide; leftShown /
// rightShown say whether a column has room.
Item {
	id: panels

	property var eventModel: null
	property date day: new Date()
	property date today: new Date()
	// The small month: its month follows monthDate, the days in sight a band (rangeStart .. rangeEnd).
	property date monthDate: day
	property date rangeStart: new Date(NaN)
	property date rangeEnd: new Date(NaN)
	signal dayClicked(date day)

	property real leftX: 0
	property real rightX: 0
	property real topY: 0
	property real bottomY: 0
	property real sideWidth: Kirigami.Units.gridUnit * 14
	property bool leftShown: false
	property bool rightShown: false

	// Weather (as PopupView gives the Week view).
	property var weatherByDay: ({})
	property var weatherHourly: []
	property var weatherCurrent: null
	property bool weatherIsSetup: false
	property bool weatherLoading: false
	property string weatherError: ""
	signal weatherRetryRequested()

	readonly property bool islands: appletConfig.islands
	readonly property real cardGap: islands ? appletConfig.cardGap : Kirigami.Units.largeSpacing
	readonly property bool showingToday: Shared.isSameDate(day, today)
	readonly property bool wantsMiniMonth: plasmoid.configuration.dayShowMiniMonth !== false
	readonly property bool wantsUpNext: plasmoid.configuration.dayShowUpNext !== false
	readonly property bool wantsWeather: plasmoid.configuration.dayShowWeather !== false
		&& (Object.keys(weatherByDay).length > 0 || weatherIsSetup)
	readonly property bool wantsTasks: plasmoid.configuration.dayShowTasks !== false
	readonly property bool tasksShown: rightShown && wantsTasks && tasksPanel.hasLists
	readonly property bool weatherShown: rightShown && wantsWeather
	function dayWeather(d) {
		return weatherByDay ? weatherByDay[Shared.dayKey(d)] : null
	}

	// Left: the small month.
	IslandCard {
		id: miniMonthCard
		visible: panels.leftShown && panels.wantsMiniMonth
		x: panels.leftX
		y: panels.topY
		width: panels.sideWidth
		height: implicitHeight
		MiniMonth {
			eventModel: miniMonthCard.visible ? panels.eventModel : null
			selectedDate: panels.monthDate
			rangeStart: panels.rangeStart
			rangeEnd: panels.rangeEnd
			today: panels.today
			firstDayOfWeek: {
				var setting = plasmoid.configuration.firstDayOfWeek
				return setting >= 0 ? setting : Qt.locale().firstDayOfWeek % 7
			}
			onDayClicked: function(day) { panels.dayClicked(day) }
		}
	}

	// Under it (islands, when there's room): the events after the day, down to the bottom.
	IslandCard {
		id: upNextCard
		readonly property real startY: miniMonthCard.visible ? miniMonthCard.y + miniMonthCard.height + panels.cardGap : panels.topY
		visible: panels.islands && panels.leftShown && panels.wantsUpNext && panels.bottomY - startY >= Kirigami.Units.gridUnit * 6
		x: panels.leftX
		y: startY
		width: panels.sideWidth
		height: Math.max(0, Math.min(implicitHeight, panels.bottomY - startY))
		UpNextPanel {
			fill: true
			maxHeight: panels.bottomY - upNextCard.startY - upNextCard.topPadding - upNextCard.bottomPadding
			eventModel: upNextCard.visible ? panels.eventModel : null
			after: Shared.addDays(Shared.startOfDay(panels.day), 1)
			today: panels.today
			onDayRequested: function(day) { panels.dayClicked(day) }
		}
	}

	// Right, on top: the day's tasks, as tall as they are (the list scrolls past the room there is).
	IslandCard {
		id: tasksCard
		readonly property real bottomLimit: panels.weatherShown ? panels.bottomY - Kirigami.Units.gridUnit * 9 - panels.cardGap : panels.bottomY
		visible: panels.tasksShown
		x: panels.rightX
		y: panels.topY
		width: panels.sideWidth
		height: implicitHeight
		DayTasksPanel {
			id: tasksPanel
			eventModel: panels.rightShown && panels.wantsTasks ? panels.eventModel : null
			day: panels.day
			showSeparator: false
			maxListHeight: Math.max(Kirigami.Units.gridUnit * 3, tasksCard.bottomLimit - tasksCard.y - tasksCard.topPadding - tasksCard.bottomPadding - Kirigami.Units.gridUnit * 5)
		}
	}

	// Under the tasks (or at the top without them): the day's weather, as tall as it is.
	IslandCard {
		id: weatherCard
		visible: panels.weatherShown
		x: panels.rightX
		y: panels.tasksShown ? tasksCard.y + tasksCard.height + panels.cardGap : panels.topY
		readonly property real room: panels.bottomY - y
		width: panels.sideWidth
		height: Math.max(0, Math.min(implicitHeight, room))
		WeatherPanel {
			isSetup: panels.weatherIsSetup
			loading: panels.weatherLoading
			errorText: panels.weatherError
			onRetryRequested: panels.weatherRetryRequested()
			isToday: panels.showingToday
			current: panels.showingToday ? panels.weatherCurrent : null
			today: panels.dayWeather(panels.day)
			showHourly: weatherCard.room >= Kirigami.Units.gridUnit * 25
			showNextDays: weatherCard.room >= Kirigami.Units.gridUnit * 15.5
			forecastUrl: WeatherApi.forecastPageUrl(plasmoid.configuration)
			locationName: plasmoid.configuration.weatherService === 'OpenMeteo' ? plasmoid.configuration.openMeteoLocationName
				: panels.weatherCurrent && panels.weatherCurrent.place ? panels.weatherCurrent.place : ""
			hourly: panels.showingToday ? panels.weatherHourly : []
			maxHeight: weatherCard.room - weatherCard.topPadding - weatherCard.bottomPadding
			nextDays: {
				var list = []
				for (var i = 1; i <= 7; i++) {
					var d = panels.dayWeather(Shared.addDays(Shared.startOfDay(panels.day), i))
					if (!d) {
						break
					}
					list.push(d)
				}
				return list
			}
		}
	}
}
