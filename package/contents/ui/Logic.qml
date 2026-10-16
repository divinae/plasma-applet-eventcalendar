import QtQuick
import "./ErrorType.js" as ErrorType
import "./lib/Requests.js" as Requests
import "./weather/WeatherApi.js" as WeatherApi
import "./lib/Base64Compat.js" as Base64Compat

Item {
	readonly property Item popup: root.fullRepresentationItem

	//--- Weather
	property var dailyWeatherData: { "list": [] }
	property var hourlyWeatherData: { "list": [] }
	property var currentWeatherData: null
	property var lastForecastAt: null
	property var lastForecastErr: null
	property int weatherRequests: 0 // Running weather requests
	readonly property bool weatherLoading: weatherRequests > 0

	//--- Main
	Component.onCompleted: {
		lastGoogleSelectionSignature = googleSelectionSignature()
		pollTimer.start()
	}

	//--- Update
	Timer {
		id: pollTimer
		
		repeat: true
		triggeredOnStart: true
		interval: plasmoid.configuration.eventsPollInterval * 60000
		onTriggered: logic.update()
	}

	function update() {
		logger.debug('update')
		logic.updateData()
	}

	function updateData() {
		logger.debug('updateData')
		logic.updateEvents()
		logic.updateWeather()
	}

	//--- Events
	function updateEvents() {
		updateEventsTimer.restart()
	}
	Timer {
		id: updateEventsTimer
		interval: 1000
		onTriggered: logic.deferredUpdateEvents()
	}
	function deferredUpdateEvents() {
		var range = agendaModel.getDateRange(agendaModel.currentMonth)

		agendaModel.visibleDateMin = range.min
		agendaModel.visibleDateMax = range.max
		eventModel.fetchAll(range.min, range.max)
	}

	//--- Weather
	function updateWeather(force) {
		if (WeatherApi.weatherIsSetup(plasmoid.configuration)) {
			// update every hour
			var shouldUpdate = false
			if (lastForecastAt) {
				var now = new Date()
				var currentHour = now.getHours()
				var lastUpdateHour = new Date(lastForecastAt).getHours()
				var beenOverAnHour = now.valueOf() - lastForecastAt >= 60 * 60 * 1000
				if (lastUpdateHour !== currentHour || beenOverAnHour) {
					shouldUpdate = true
				}
			} else {
				shouldUpdate = true
			}
			
			if (force || shouldUpdate) {
				updateWeatherTimer.restart()
			}
		}
	}
	Timer {
		id: updateWeatherTimer
		interval: 100
		onTriggered: logic.deferredUpdateWeather()
	}
	function deferredUpdateWeather() {
		logic.updateDailyWeather()

		// Hourly data feeds the meteogram (agenda view) and the Today view's weather panel.
		var meteogramShown = popup ? popup.showMeteogram : plasmoid.configuration.widgetShowMeteogram && plasmoid.configuration.popupMode === 'classic' // popup exists after first open
		if (meteogramShown || plasmoid.configuration.popupMode === 'today') {
			logic.updateHourlyWeather()
		}
	}

	function resetWeatherData() {
		logic.dailyWeatherData = { "list": [] }
		logic.hourlyWeatherData = { "list": [] }
		logic.currentWeatherData = null
	}

	function resetWeatherAndUpdate() {
		logic.resetWeatherData()
		logic.updateWeather(true)
	}

	function handleWeatherError(funcName, err, data, xhr) {
		logger.log(funcName + '.err', err, xhr && xhr.status, data)
		if (Requests.isNetworkError(xhr)) { // No connection / timeout: retried with backoff
			logic.lastForecastErr = i18n("Could not connect.") + '\n' + i18n("Will try again soon.")
			logic.weatherNetworkFailed = true
			logic.networkFailed()
		} else if (xhr && xhr.status === 429) {
			lastForecastAt = Date.now() // If there's an error, don't bother the API for another hour.
			var msg = i18n("Weather API limit reached")
			var errorMessage = i18n("HTTP Error %1: %2", xhr.status, msg)
			errorMessage += '\n' + i18n("Will try again soon.")
			logic.lastForecastErr = errorMessage
		} else {
			lastForecastAt = Date.now() // If there's an error, don't bother the API for another hour.
			logic.lastForecastErr = err
		}
	}

	function updateDailyWeather() {
		logger.debug('updateDailyWeather', lastForecastAt, Date.now())
		logic.weatherRequests++
		WeatherApi.updateDailyWeather(plasmoid.configuration, function(err, data, xhr) {
			logic.weatherRequests = Math.max(0, logic.weatherRequests - 1)
			if (err) return handleWeatherError('updateDailyWeather', err, data, xhr)
			logger.debugJSON('updateDailyWeather.response', data)

			logic.lastForecastAt = Date.now()
			logic.lastForecastErr = null
			logic.weatherNetworkFailed = false
			logic.networkRecovered()
			logic.dailyWeatherData = data
			if (data.current) {
				logic.currentWeatherData = data.current
			}
			if (popup) popup.updateUI()
		})
	}

	function updateHourlyWeather() {
		logger.debug('updateHourlyWeather', lastForecastAt, Date.now())
		logic.weatherRequests++
		WeatherApi.updateHourlyWeather(plasmoid.configuration, function(err, data, xhr) {
			logic.weatherRequests = Math.max(0, logic.weatherRequests - 1)
			if (err) return handleWeatherError('updateHourlyWeather', err, data, xhr)
			logger.debugJSON('updateHourlyWeather.response', data)

			logic.lastForecastAt = Date.now()
			logic.lastForecastErr = null
			logic.weatherNetworkFailed = false
			logic.networkRecovered()
			logic.hourlyWeatherData = data
			logic.currentWeatherData = data.current || data.list[0]
			if (popup) popup.updateMeteogram()
		})
	}

	//---
	Connections {
		target: plasmoid.configuration

		//--- Events
		function onAccessTokenChanged() { logic.updateEvents() }
		function onCalendarIdListChanged() { logic.updateEvents() }
		function onEnabledCalendarPluginsChanged() { logic.updateEvents() }
		function onTasklistIdListChanged() { logic.updateEvents() }
		function onGoogleAccountsChanged() {
			// Token refreshes rewrite googleAccounts too. Only refetch when the selection changes.
			var signature = logic.googleSelectionSignature()
			if (signature !== logic.lastGoogleSelectionSignature) {
				logic.lastGoogleSelectionSignature = signature
				logic.updateEvents()
			}
		}
		function onGoogleActiveAccountIdChanged() { logic.updateEvents() }
		function onGoogleEventClickActionChanged() { logic.updateEvents() }

		//--- Weather
		function onWeatherServiceChanged() { logic.resetWeatherAndUpdate() }
		function onOpenMeteoLatitudeChanged() { logic.resetWeatherAndUpdate() }
		function onOpenMeteoLongitudeChanged() { logic.resetWeatherAndUpdate() }
		function onPopupModeChanged() { logic.updateWeather(true) } // Today needs hourly data
		function onOpenWeatherMapAppIdChanged() { logic.resetWeatherAndUpdate() }
		function onOpenWeatherMapCityIdChanged() { logic.resetWeatherAndUpdate() }
		function onWeatherCanadaCityIdChanged() { logic.resetWeatherAndUpdate() }
		function onWeatherUnitsChanged() { logic.updateWeather(true) }
		function onWidgetShowMeteogramChanged() {
			if (plasmoid.configuration.widgetShowMeteogram) {
				logic.updateHourlyWeather()
			}
		}

		//--- UI
		function onAgendaBreakupMultiDayEventsChanged() { if (popup) popup.updateUI() }
		function onMeteogramHoursChanged() { if (popup) popup.updateMeteogram() }
	}

	//---
	Connections {
		target: appletConfig
		function onClock24hChanged() { if (popup) popup.updateUI() }
	}

	//---
	property int currentErrorType: ErrorType.NoError
	property string lastGoogleSelectionSignature: "" // Set once in onCompleted, not a binding.
	function googleSelectionSignature() {
		return JSON.stringify(parseGoogleAccounts().map(function(account) {
			return [account.id, !!account.refreshToken, account.calendarIdList, account.tasklistIdList]
		}))
	}
	function parseGoogleAccounts() {
		var raw = plasmoid.configuration.googleAccounts
		if (!raw) {
			return []
		}
		if (Array.isArray(raw)) {
			return raw
		}
		var decoded = raw
		try {
			decoded = Base64Compat.base64DecodeToString(raw)
		} catch (e) {
			decoded = raw
		}
		try {
			var parsed = JSON.parse(decoded)
			return Array.isArray(parsed) ? parsed : []
		} catch (e2) {
			return []
		}
	}
	property string currentErrorMessage: {
		var accounts = parseGoogleAccounts()
		for (var i = 0; i < accounts.length; i++) {
			var account = accounts[i]
			if (account.accessToken && account.sessionClientId && account.sessionClientId != plasmoid.configuration.latestClientId) {
				return i18n("Widget has been updated. Please logout and login to Google Calendar again.")
			}
		}
		if (plasmoid.configuration.accessToken && plasmoid.configuration.latestClientId != plasmoid.configuration.sessionClientId) {
			return i18n("Widget has been updated. Please logout and login to Google Calendar again.")
		} else if (!plasmoid.configuration.accessToken && plasmoid.configuration.access_token) {
			return i18n("Logged out of Google. Please login again.")
		} else {
			return ""
		}
	}
	function clearError() {
		currentErrorType = ErrorType.NoError
		if (popup) popup.clearError()
	}
	Connections {
		target: eventModel
		function onError(msg, errorType) {
			if (errorType === ErrorType.NetworkError) {
				// Shown as the offline banner when the fetch round ends (one per round, not per calendar).
				logic.eventsRoundNetworkError = true
				return
			}
			logic.currentErrorMessage = msg
			logic.currentErrorType = errorType
			if (popup) popup.showError(logic.currentErrorMessage)
		}
		function onFetchingData() {
			logic.eventsRoundNetworkError = false
		}
		function onAllDataFetched() {
			if (logic.eventsRoundNetworkError) {
				logic.eventsNetworkFailed = true
				logic.networkFailed()
			} else {
				logic.eventsNetworkFailed = false
				if (logic.currentErrorType !== ErrorType.NoError && logic.currentErrorType !== ErrorType.NetworkError) {
					logic.clearError() // Fetched fine this time
				}
				logic.networkRecovered()
			}
		}
	}

	//--- Network failures: keep the last data, retry with backoff, tell the user once.
	property bool offline: false // The last events or weather fetch couldn't connect
	property bool eventsRoundNetworkError: false
	property bool eventsNetworkFailed: false
	property bool weatherNetworkFailed: false
	property int networkFailures: 0
	property double nextRetryAt: 0 // ms since epoch
	property bool outageNotified: false
	readonly property var retryDelays: [30, 60, 120, 300] // seconds; capped below the poll interval
	property int outageNotifyDelay: 3 * 60 * 1000 // Desktop notification only if the outage lasts

	function networkFailed() {
		if (!offline) {
			offline = true
			outageNotified = false
			outageNotifyTimer.restart()
		}
		currentErrorType = ErrorType.NetworkError
		if (retryTimer.running) {
			return // A retry is already scheduled (eg: daily and hourly weather both failed)
		}
		var delay = retryDelays[Math.min(networkFailures, retryDelays.length - 1)] * 1000
		networkFailures++
		nextRetryAt = Date.now() + delay
		retryTimer.interval = delay
		retryTimer.restart()
		if (popup) popup.showNetworkError()
	}
	function networkRecovered() {
		if (!offline || eventsNetworkFailed || weatherNetworkFailed) {
			return
		}
		offline = false
		networkFailures = 0
		nextRetryAt = 0
		retryTimer.stop()
		outageNotifyTimer.stop()
		if (currentErrorType === ErrorType.NetworkError) {
			clearError()
		}
		if (outageNotified) {
			outageNotified = false
			notificationManager.notify({
				appName: i18n("Event Calendar"),
				appIcon: "network-connect",
				summary: i18n("Calendar is back in sync"),
				expireTimeout: 4000,
			})
		}
	}
	function retryNow() {
		retryTimer.stop()
		nextRetryAt = 0
		if (eventsNetworkFailed || !weatherNetworkFailed) {
			logic.updateEvents()
		}
		if (weatherNetworkFailed) {
			logic.updateWeather(true)
		}
	}
	Timer {
		id: retryTimer
		onTriggered: logic.retryNow()
	}
	// One desktop notification per outage, only if it lasts.
	Timer {
		id: outageNotifyTimer
		interval: logic.outageNotifyDelay
		onTriggered: {
			if (logic.offline && !logic.outageNotified) {
				logic.outageNotified = true
				notificationManager.notify({
					appName: i18n("Event Calendar"),
					appIcon: "network-disconnect",
					summary: i18n("Calendar can't sync"),
					body: i18n("No connection. Showing the last loaded events; retrying automatically."),
					expireTimeout: 10000,
				})
			}
		}
	}

	//---
	Connections {
		target: eventModel
		function onCalendarFetched(calendarId, data) {
			logger.debug('onCalendarFetched', calendarId)
			// UI is rebuilt from eventsData, which only changes in mergeEvents() on allDataFetched.
		}
		function onAllDataFetched() {
			logger.debug('onAllDataFetched')
			if (popup) popup.deferredUpdateUI()
		}
		function onEventCreated(calendarId, data) {
			logger.debugJSON('onEventCreated', calendarId, data)
			if (popup) popup.deferredUpdateUI()
		}
		function onEventUpdated(calendarId, eventId, data) {
			logger.debugJSON('onEventUpdated', calendarId, eventId, data)
			if (popup) popup.deferredUpdateUI()
		}
		function onEventDeleted(calendarId, eventId, data) {
			logger.debugJSON('onEventDeleted', calendarId, eventId, data)
			if (popup) popup.deferredUpdateUI()
		}
	}

	//---
	Connections {
		target: networkMonitor
		function onIsConnectedChanged() {
			if (networkMonitor.isConnected) {
				// Back online: retry right away with a fresh backoff.
				logic.networkFailures = 0
				if (logic.offline) {
					logic.retryNow()
				} else {
					logic.update()
				}
			}
		}
	}
}
