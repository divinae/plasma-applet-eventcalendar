import QtQuick
import "./ErrorType.js" as ErrorType
import "./lib/Requests.js" as Requests
import "./weather/WeatherApi.js" as WeatherApi
import "./lib/GoogleOAuthConfig.js" as GoogleOAuthConfig
import "./lib/SafeConfig.js" as SafeConfig
import "./EventCacheUtil.js" as EventCacheUtil

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
		lastCacheAccountIds = cacheAccountIds()
		showCachedEvents()
		pollTimer.start()
	}

	//--- Event cache: the last loaded Google events and tasks (Google, TickTick), shown until the
	// first fetch round finishes.
	function showCachedEvents() {
		var selected = EventCacheUtil.selectedCalendarIds(parseGoogleAccounts().concat(parseTickTickAccounts()))
		var cached = eventCache.load(function(calendarId) { return !!selected[calendarId] })
		if (!cached) {
			return
		}
		logger.debug('showCachedEvents', Object.keys(cached.calendars).length, 'calendars from', new Date(cached.savedAt))
		eventModel.showCachedEvents(cached.calendars)
		if (popup) popup.updateUI()
	}

	// Ids of the Google and TickTick accounts in config.
	property var lastCacheAccountIds: []
	function cacheAccountIds() {
		return parseGoogleAccounts().concat(parseTickTickAccounts()).map(function(account) {
			return account && account.id ? String(account.id) : ''
		}).filter(function(id) { return !!id })
	}
	// An account was removed (signed out): its calendars leave the cache file right away, not
	// with the next refresh.
	function pruneCacheOfGoneAccounts() {
		var ids = cacheAccountIds()
		var gone = lastCacheAccountIds.some(function(id) { return ids.indexOf(id) < 0 })
		lastCacheAccountIds = ids
		if (gone) {
			eventCache.pruneAccounts(ids)
		}
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
	// A view filter changed (declined events, hidden calendars): rebuild from what's loaded.
	function refilterEvents() {
		eventModel.mergeEvents()
		if (popup) popup.updateUI()
		upcomingEvents.updateNextEvent()
		upcomingEvents.updateTooltipEvents()
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

		// Hourly data feeds the meteogram (agenda view) and the Day view's weather panel.
		// The popup exists after its first open; before, the view it will open in.
		var cfg = plasmoid.configuration
		var viewMode = popup ? popup.viewMode : (cfg.popupOpenLastView && cfg.popupLastView ? cfg.popupLastView : cfg.popupMode)
		var meteogramShown = popup ? popup.showMeteogram : cfg.widgetShowMeteogram && viewMode === 'classic'
		if (meteogramShown || viewMode === 'today') {
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
		} else if (xhr && xhr.status >= 500 && xhr.status < 600) {
			// The service is down or overloaded (eg: Open-Meteo's 503): try again soon, not in an hour.
			logic.lastForecastErr = i18n("The weather service is not available right now.") + '\n' + i18n("Will try again soon.")
			logic.scheduleWeatherRetry()
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

	// Server errors: retried after 30 s, 1, 2, then every 5 minutes, until a forecast arrives.
	property int weatherRetries: 0
	function scheduleWeatherRetry() {
		if (weatherRetryTimer.running) {
			return // Daily and hourly both failed: one retry
		}
		var delays = [30, 60, 120, 300]
		weatherRetryTimer.interval = delays[Math.min(weatherRetries, delays.length - 1)] * 1000
		weatherRetries++
		weatherRetryTimer.start()
	}
	Timer {
		id: weatherRetryTimer
		onTriggered: logic.updateWeather(true)
	}
	function weatherArrived() {
		retryDone()
		weatherRetries = 0
		weatherRetryTimer.stop()
	}

	function updateDailyWeather() {
		logger.debug('updateDailyWeather', lastForecastAt, Date.now())
		logic.weatherRequests++
		WeatherApi.updateDailyWeather(plasmoid.configuration, function(err, data, xhr) {
			logic.weatherRequests = Math.max(0, logic.weatherRequests - 1)
			if (err) return handleWeatherError('updateDailyWeather', err, data, xhr)
			logger.debugJSON('updateDailyWeather.responseSummary', {
				count: data && data.list ? data.list.length : 0,
			})

			logic.lastForecastAt = Date.now()
			logic.lastForecastErr = null
			logic.weatherNetworkFailed = false
			logic.weatherArrived()
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
			logger.debugJSON('updateHourlyWeather.responseSummary', {
				count: data && data.list ? data.list.length : 0,
			})

			logic.lastForecastAt = Date.now()
			logic.lastForecastErr = null
			logic.weatherNetworkFailed = false
			logic.weatherArrived()
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
		function onEnabledCalendarPluginsChanged() { logic.updateEvents() }
		function onGoogleAccountsChanged() {
			logic.pruneCacheOfGoneAccounts()
			// Token refreshes rewrite googleAccounts too. Only refetch when the selection changes.
			var signature = logic.googleSelectionSignature()
			if (signature !== logic.lastGoogleSelectionSignature) {
				logic.lastGoogleSelectionSignature = signature
				logic.updateEvents()
			}
		}
		function onGoogleActiveAccountIdChanged() { logic.updateEvents() }
		function onTickTickAccountsChanged() { logic.pruneCacheOfGoneAccounts() }
		function onGoogleEventClickActionChanged() { logic.updateEvents() }
		function onGoogleColorPaletteChanged() {
			// Recolor right away (system palette is applied at display time anyway).
			eventModel.recolorEvents()
			if (popup) popup.updateUI()
		}
		function onShowDeclinedEventsChanged() { logic.refilterEvents() }
		// Calendars hidden in the popup header's menu: a view filter, nothing is fetched again.
		function onHiddenCalendarIdsChanged() { logic.refilterEvents() }
		// The clock's next-event chip only.
		function onClockHiddenCalendarIdsChanged() { upcomingEvents.updateNextEvent() }
		function onClockNextEventSkipAllDayChanged() { upcomingEvents.updateNextEvent() }

		//--- Weather
		function onWeatherServiceChanged() { logic.resetWeatherAndUpdate() }
		function onOpenMeteoLatitudeChanged() { logic.resetWeatherAndUpdate() }
		function onOpenMeteoLongitudeChanged() { logic.resetWeatherAndUpdate() }
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
			// Calendar names and colors too: editing a calendar in the settings recolors its events.
			var calendars = (Array.isArray(account.calendarList) ? account.calendarList : []).map(function(calendar) {
				return [calendar.id, calendar.summaryOverride || calendar.summary, calendar.backgroundColor, calendar.colorId]
			})
			return [account.id, !!account.refreshToken, account.calendarIdList, account.tasklistIdList, calendars]
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
		try {
			var parsed = SafeConfig.parseBase64Json(raw, [])
			return Array.isArray(parsed) ? parsed : []
		} catch (e) {
			return []
		}
	}
	// TickTick accounts from config (ids and selected projects; the tokens are in the keyring).
	function parseTickTickAccounts() {
		var raw = plasmoid.configuration.tickTickAccounts
		if (!raw) {
			return []
		}
		try {
			var parsed = Array.isArray(raw) ? raw : SafeConfig.parseBase64Json(raw, [])
			return Array.isArray(parsed) ? parsed : []
		} catch (e) {
			return []
		}
	}
	function currentGoogleCredentials() {
		return GoogleOAuthConfig.effectiveClientCredentials(plasmoid.configuration, GoogleOAuthConfig.defaultClientId)
	}
	function currentGoogleClientId() {
		return currentGoogleCredentials().clientId
	}
	function currentGoogleUsesPkce() {
		return !currentGoogleCredentials().clientSecret
	}
	property string currentErrorMessage: {
		var accounts = parseGoogleAccounts()
		for (var i = 0; i < accounts.length; i++) {
			var account = accounts[i]
			if (account.reauthRequired) {
				return i18n("Google authorization expired or was revoked. Open Event Calendar Settings > Google Calendar and sign in to that account again.")
			}
			if (account.sessionUsesPkce === false) {
				continue
			}
			if (account.sessionClientId && account.sessionClientId !== currentGoogleClientId()) {
				return i18n("Widget has been updated. Please logout and login to Google Calendar again.")
			}
			if (account.sessionUsesPkce === true && currentGoogleUsesPkce() === false) {
				return i18n("Widget has been updated. Please logout and login to Google Calendar again.")
			}
		}
		if (plasmoid.configuration.access_token) {
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
				// A round that hit the network error keeps the cache file as it is.
				logic.eventsNetworkFailed = true
				logic.networkFailed()
			} else {
				// Event cache: the last loaded Google events and tasks (see showCachedEvents).
				eventModel.settleCachedCalendars()
				eventCache.scheduleSave(eventModel.eventsByCalendar, eventModel.dateMin, eventModel.dateMax)
				logic.eventsNetworkFailed = false
				if (logic.currentErrorType !== ErrorType.NoError && logic.currentErrorType !== ErrorType.NetworkError) {
					logic.clearError() // Fetched fine this time
				}
				logic.networkRecovered()
			}
			// UI is rebuilt from eventsData, which only changes in mergeEvents() on allDataFetched.
			if (popup) popup.deferredUpdateUI()
		}
		function onEventCreated(calendarId, data) {
			if (popup) popup.deferredUpdateUI()
		}
		function onEventUpdated(calendarId, eventId, data) {
			if (popup) popup.deferredUpdateUI()
		}
		function onEventDeleted(calendarId, eventId, data) {
			if (popup) popup.deferredUpdateUI()
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
	// A retry is running (the banner's Retry Now waits for it): until the fetch fails or comes back,
	// at most retryingTimeout.
	property bool retrying: false
	readonly property var retryDelays: [30, 60, 120, 300] // seconds; capped below the poll interval
	property int outageNotifyDelay: 3 * 60 * 1000 // Desktop notification only if the outage lasts

	function networkFailed() {
		retryDone()
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
		retryDone()
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
				event: "syncProblem",
				appName: i18n("Event Calendar"),
				appIcon: "network-connect",
				summary: i18n("Calendar is back in sync"),
				expireTimeout: 4000,
			})
		}
	}
	function retryNow() {
		if (retrying) {
			return
		}
		retryTimer.stop()
		nextRetryAt = 0
		retrying = true
		retryingTimeout.restart()
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
	function retryDone() {
		retrying = false
		retryingTimeout.stop()
	}
	// A fetch that never ends (no answer, no error): Retry Now can be pressed again.
	Timer {
		id: retryingTimeout
		interval: 45000
		onTriggered: logic.retrying = false
	}
	// One desktop notification per outage, only if it lasts.
	Timer {
		id: outageNotifyTimer
		interval: logic.outageNotifyDelay
		onTriggered: {
			if (logic.offline && !logic.outageNotified) {
				logic.outageNotified = true
				notificationManager.notify({
					event: "syncProblem",
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
