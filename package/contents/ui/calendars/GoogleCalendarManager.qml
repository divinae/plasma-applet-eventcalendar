import QtQuick

import "../ErrorType.js" as ErrorType
import "../EventTypes.js" as EventTypes
import "../IcsImport.js" as IcsImport
import "../Shared.js" as Shared
import "EventFields.js" as EventFields
import "../lib"
import "../lib/Async.js" as Async
import "../lib/Requests.js" as Requests
import "../code/ColorIdMap.js" as ColorIdMap
import "../code/GooglePalette.js" as GooglePalette

CalendarManager {
	id: googleCalendarManager

	calendarManagerId: "GoogleCalendar"

	property var session
	property var accountsStore
	property string accountId: ""
	property string accountLabel: ""

	Logger {
		id: logger
		name: 'eventcalendar-google-calendar'
		showDebug: plasmoid.configuration.debugging
	}

	function getAccount() {
		if (!accountsStore || !accountId) {
			return null
		}
		return accountsStore.getAccount(accountId)
	}

	function getCalendarIdList() {
		return getAccount() ? accountsStore.ensureCalendarSelection(accountId) : []
	}

	function scopedCalendarId(rawId) {
		if (!accountId) {
			return rawId
		}
		return accountId + "::" + rawId
	}

	function unscopedCalendarId(scopedId) {
		if (!accountId) {
			return scopedId
		}
		var prefix = accountId + "::"
		if (scopedId.indexOf(prefix) === 0) {
			return scopedId.substr(prefix.length)
		}
		return scopedId
	}

	// The name in the user's calendar list (summaryOverride) wins over the calendar's own name.
	function formatCalendarSummary(calendar) {
		var name = calendar.summaryOverride || calendar.summary
		if (accountLabel) {
			return accountLabel + " - " + name
		}
		return name
	}

	function decorateCalendar(calendar) {
		var decorated = {}
		for (var key in calendar) {
			decorated[key] = calendar[key]
		}
		decorated.id = scopedCalendarId(calendar.id)
		decorated.summary = formatCalendarSummary(calendar)
		decorated.isTasklist = false
		return decorated
	}

	onFetchAllCalendars: {
		fetchGoogleAccountData()
	}

	function fetchGoogleAccountData() {
		// Tokens may live in the system keyring: an account is enough to start.
		var account = getAccount()
		if (!account) {
			return
		}
		if (!account.calendarList || !account.calendarList.length) {
			fetchGoogleCalendarList()
			return
		}
		var idList = getCalendarIdList()
		if (idList.length) { // Avoid a token refresh when nothing is selected.
			fetchGoogleAccountEvents(idList)
		}
	}

	function fetchGoogleCalendarList() {
		googleCalendarManager.asyncRequests += 1
		googleRequest('GET', '/users/me/calendarList', null, null, function(err, data, xhr) {
			if (err) {
				googleCalendarManager.asyncRequestsDone += 1
				handleError(err, data, xhr)
				return
			}
			accountsStore.applyCalendarList(accountId, data.items)
			fetchGoogleAccountEvents(getCalendarIdList())
			googleCalendarManager.asyncRequestsDone += 1
		})
	}

	//--- Requests
	readonly property string apiUrl: 'https://www.googleapis.com/calendar/v3'

	// action() once the session has a valid access token (refreshed when needed), else
	// fail(err, isNetworkError).
	function withToken(action, fail) {
		session.checkAccessToken(function(err, isNetworkError) {
			if (err) {
				fail(err, !!isNetworkError)
				return
			}
			action()
		})
	}

	// One Calendar API request. path: after /calendar/v3, ids encoded (see eventPath). query:
	// optional params (see queryString). body: the JSON body (not for GET).
	// callback(err, data, xhr), always called: err is Google's error body when it sent one. When no
	// token could be had, xhr is null (auth error) or { status: 0, noToken: true } (offline);
	// handleError knows both.
	// Only the HTTP status is logged: no ids, titles, emails or bodies.
	function googleRequest(method, path, query, body, callback) {
		withToken(function() {
			var opt = {
				method: method,
				url: apiUrl + path + queryString(query),
				headers: {
					"Authorization": "Bearer " + session.accessToken,
				},
			}
			var send = Requests.getJSON
			if (method !== 'GET') {
				opt.data = body
				send = Requests.postJSON
			}
			send(opt, function(err, data, xhr) {
				logger.debug(calendarManagerId, method, 'response', xhr && xhr.status)
				if (!err && data && data.error) {
					err = data
				}
				callback(err, data, xhr)
			})
		}, function(err, isNetworkError) {
			callback(err, null, isNetworkError ? { status: 0, noToken: true } : null)
		})
	}

	// '/calendars/{calendarId}/events[/{eventId}]' for a raw (unscoped) calendar id.
	function eventPath(rawCalendarId, eventId) {
		var path = '/calendars/' + encodeURIComponent(rawCalendarId) + '/events'
		if (eventId) {
			path += '/' + encodeURIComponent(eventId)
		}
		return path
	}

	//-------------------------
	// Events

	//--- Errors
	function showHttpError(httpCode, msg, suggestion, errorType) {
		var errorMessage = i18n("HTTP Error %1: %2", httpCode, msg)
		if (suggestion) {
			errorMessage += '\n' + suggestion
		}
		googleCalendarManager.error(errorMessage, errorType)
	}
	// err, data, xhr: as googleRequest gives them.
	function handleError(err, data, xhr) {
		if (!xhr) {
			handleAuthError(err, false, false) // No access token
			return
		}
		var httpCode = xhr.status
		if (httpCode === 0) {
			var msg = i18n("Could not connect")
			var suggestion = i18n("Will try again soon.")
			showHttpError(httpCode, msg, suggestion, ErrorType.NetworkError)
			return
		}

		// https://developers.google.com/calendar/v3/errors
		// On HTTP errors, err is a string and the JSON error body is in data.
		if (!(err && err.error) && typeof data === 'string') {
			try {
				err = JSON.parse(data)
			} catch (e) {
				// Not JSON
			}
		}
		if (err && err.error && err.error.errors && err.error.errors.length >= 1) {
			httpCode = err.error.code
			var err0 = err.error.errors[0]

			if (httpCode === 401 && err0.reason === 'authError') {
				var suggestion = i18n("Widget has been updated. Please logout and login to Google Calendar again.")
				showHttpError(httpCode, err0.message, suggestion, ErrorType.ClientError)
			} else if (httpCode === 403 && err0.domain === 'usageLimits') {
				var suggestion = i18n("Too many web requests. Will try again soon.")
				showHttpError(httpCode, err0.message, suggestion, ErrorType.ClientError)
			} else {
				var suggestion = i18n("Will try again soon.")
				showHttpError(httpCode, err0.message, suggestion, ErrorType.UnknownError)
			}
			return
		}

		showHttpError(httpCode, String(err), i18n("Will try again soon."), ErrorType.UnknownError)
	}
	function handleAuthError(err, markDone, isNetworkError) {
		if (markDone) {
			googleCalendarManager.asyncRequestsDone += 1
		}
		if (isNetworkError) {
			// The token couldn't be refreshed because we're offline.
			showHttpError(0, i18n("Could not connect"), i18n("Will try again soon."), ErrorType.NetworkError)
			return
		}
		var message = i18n("Google authentication failed: %1", err)
		googleCalendarManager.error(message, ErrorType.ClientError)
	}
	// A whole account failed to fetch: keep showing its previous events.
	function restorePrevious(idList) {
		for (var i = 0; i < idList.length; i++) {
			restorePreviousCalendar(scopedCalendarId(idList[i]))
		}
	}

	//--- Utils
	function cloneRawEvent(event) {
		// Clone the event data and clean up the extra stuff we added when parsing the event.
		var data = JSON.parse(JSON.stringify(event)) // clone
		if (data.description === "") delete data.description
		return EventFields.stripWidgetFields(data)
	}
	// Merge changed fields into an event body. A field set to undefined is removed: updates are a
	// full PUT, so a key left in the body keeps its old value (eg: colorId back to the calendar color).
	function mergeArgs(data, args) {
		Shared.merge(data, args)
		for (var key in args) {
			if (typeof args[key] === 'undefined') {
				delete data[key]
			}
		}
		return data
	}
	// Query string for the optional request params: { sendUpdates: 'all' | 'none', conferenceDataVersion: 1 }
	function queryString(params) {
		var parts = []
		for (var key in (params || {})) {
			var value = params[key]
			if (typeof value !== 'undefined' && value !== null && value !== '') {
				parts.push(encodeURIComponent(key) + '=' + encodeURIComponent(value))
			}
		}
		return parts.length ? '?' + parts.join('&') : ''
	}

	//--- List Events
	function fetchGoogleAccountEvents(calendarIdList) {
		googleCalendarManager.asyncRequests += 1
		var generation = googleCalendarManager.fetchGeneration
		withToken(function() {
			var tasks = calendarIdList.map(function(calendarId) {
				return fetchGoogleCalendarEvents.bind(this, calendarId)
			})
			// Tasks never fail: a calendar's error is in its result.
			Async.parallel(tasks, function(err, results) {
				if (generation !== googleCalendarManager.fetchGeneration) {
					logger.debug('fetchGoogleAccountEvents', 'dropping stale response')
					return
				}
				fetchGoogleAccountEvents_done(results)
			})
		}, function(err, isNetworkError) {
			restorePrevious(calendarIdList)
			handleAuthError(err, true, isNetworkError)
		})
	}
	function fetchGoogleAccountEvents_done(results) {
		for (var i = 0; i < results.length; i++) {
			var result = results[i]
			if (result.error) {
				restorePreviousCalendar(result.scopedCalendarId)
				handleError(result.error.err, result.error.data, result.error.xhr)
			} else {
				setCalendarData(result.scopedCalendarId, result.data)
			}
		}
		googleCalendarManager.asyncRequestsDone += 1
	}

	// callback(null, { scopedCalendarId, data, error }): error is { err, data, xhr } or null.
	function fetchGoogleCalendarEvents(calendarId, callback) {
		fetchGCalEvents({
			calendarId: calendarId,
			start: googleCalendarManager.dateMin.toISOString(),
			end: googleCalendarManager.dateMax.toISOString(),
			accessToken: session.accessToken,
		}, function(err, data, xhr) {
			if (err) {
				logger.debug('onErrorFetchingEvents', xhr && xhr.status)
			}
			callback(null, {
				scopedCalendarId: scopedCalendarId(calendarId),
				data: data,
				error: err ? { err: err, data: data, xhr: xhr } : null,
			})
		})
	}

	function fetchGCalEvents(args, callback) {
		// Out of office, focus time and working locations too (see EventTypes.js), unless the calendar
		// rejected the list before. Decided once per fetch: page tokens are only valid for the same query.
		delete args.pageToken
		args.withTypes = !eventTypesRejected[args.calendarId]
		var onResponse = fetchGCalEventsPageResponse.bind(this, args, callback, null)
		fetchGCalEventsPage(args, onResponse)
	}

	// typesRejected: the calendar refused the eventTypes list (see fetchGCalEventsPage).
	function fetchGCalEventsPageResponse(args, finishedCallback, allData, err, data, xhr, typesRejected) {
		logger.debug('fetchGCalEventsPageResponse', xhr && xhr.status)
		if (typesRejected) {
			// Again from the first page without eventTypes, dropping the pages fetched with them (a
			// page token of that query isn't valid for the new one).
			logger.log('eventTypes rejected by a calendar, fetching without them') // No calendar id/name
			eventTypesRejected[args.calendarId] = true
			delete args.pageToken
			args.withTypes = false
			fetchGCalEventsPage(args, fetchGCalEventsPageResponse.bind(this, args, finishedCallback, null))
			return
		}
		if (err) {
			return finishedCallback(err, data, xhr)
		}
		if (allData) {
			data.items = allData.items.concat(data.items)
		}
		allData = data

		if (allData.nextPageToken) {
			logger.debug('fetchGCalEventsPageResponse.nextPageToken', 'allData.items.length', allData.items && allData.items.length)
			args.pageToken = allData.nextPageToken
			var onResponse = fetchGCalEventsPageResponse.bind(this, args, finishedCallback, allData)
			fetchGCalEventsPage(args, onResponse)
		} else {
			logger.debug('fetchGCalEventsPageResponse.finished', 'allData.items.length', allData.items && allData.items.length)
			finishedCallback(err, allData, xhr)
		}
	}

	function fetchGCalEventsPage(args, pageCallback) {
		logger.debug('fetchGCalEventsPage', args.calendarId)
		var url = 'https://www.googleapis.com/calendar/v3'
		url += '/calendars/'
		url += encodeURIComponent(args.calendarId)
		url += '/events'
		url += '?timeMin=' + encodeURIComponent(args.start)
		url += '&timeMax=' + encodeURIComponent(args.end)
		url += '&singleEvents=' + encodeURIComponent('true')
		url += '&maxResults=2500' // API max. Default 250 means more sequential pages.
		url += '&timeZone=' + encodeURIComponent('Etc/UTC')
		// args.withTypes: the eventTypes list (see fetchGCalEvents). A calendar that rejects it (400) is
		// asked again without it, and from then on (eventTypesRejected).
		var withTypes = !!args.withTypes
		if (withTypes) {
			EventTypes.FETCHED_TYPES.forEach(function(type) {
				url += '&eventTypes=' + encodeURIComponent(type)
			})
		}
		if (args.pageToken) {
			url += '&pageToken=' + encodeURIComponent(args.pageToken)
		}
		Requests.getJSON({
			url: url,
			headers: {
				"Authorization": "Bearer " + args.accessToken,
			}
		}, function(err, data, xhr) {
			logger.debug('fetchGCalEventsPage.response', args.calendarId, err, data, xhr.status)
			if (withTypes && xhr && xhr.status === 400 && rejectsEventTypes(data)) {
				pageCallback(err, data, xhr, true)
				return
			}
			if (!err && data && data.error) {
				return pageCallback(data, null, xhr)
			}
			pageCallback(err, data, xhr)
		})
	}
	property var eventTypesRejected: ({}) // Raw calendar id -> true
	// Whether a 400 answer is about the eventTypes parameter (another 400 is a real error). body:
	// the answer's text (or parsed JSON), { error: { message, errors: [{ reason, location, message }] } }.
	function rejectsEventTypes(body) {
		var data = body
		if (typeof data === 'string') {
			try {
				data = JSON.parse(data)
			} catch (e) {
				return false
			}
		}
		var error = data && data.error
		if (!error) {
			return false
		}
		var texts = [error.message]
		var errors = error.errors || []
		for (var i = 0; i < errors.length; i++) {
			texts.push(errors[i].reason, errors[i].location, errors[i].message)
		}
		return texts.some(function(text) { return /event\s*_?types?/i.test(String(text || '')) })
	}

	//--- Search
	// Events matching query in the selected calendars between timeMin and timeMax (Dates).
	// callback(err, items): items are parsed like fetched events. Result bodies are never logged.
	function searchEvents(query, timeMin, timeMax, callback) {
		var idList = getCalendarIdList()
		if (!idList.length) {
			callback(null, [])
			return
		}
		var pending = idList.length
		var found = []
		var firstError = null
		idList.forEach(function(rawId) {
			googleRequest('GET', eventPath(rawId), {
				q: query,
				timeMin: timeMin.toISOString(),
				timeMax: timeMax.toISOString(),
				singleEvents: 'true',
				orderBy: 'startTime',
				maxResults: 50,
				timeZone: 'Etc/UTC',
			}, null, function(err, data) {
				if (err) {
					firstError = firstError || err
				} else if (data && data.items) {
					calendarParsing(scopedCalendarId(rawId), data)
					found = found.concat(data.items)
				}
				pending -= 1
				if (pending === 0) {
					callback(found.length ? null : firstError, found)
				}
			})
		})
	}

	//--- Get Single Event
	// The server copy of an event. callback(err, data, xhr), always called.
	function fetchGoogleCalendarEvent(calendarId, eventId, callback) {
		getServerEvent(calendarId, eventId, function(err, data, xhr) {
			if (err && (!xhr || xhr.noToken)) {
				handleError(err, data, xhr) // No access token: say so, as for the other requests
			}
			callback(err, data, xhr)
		})
	}
	function getServerEvent(calendarId, eventId, callback) {
		googleRequest('GET', eventPath(unscopedCalendarId(calendarId), eventId), {
			timeZone: 'Etc/UTC',
		}, null, callback)
	}

	//--- Parsing Events
	function parseCalendarData(calendarId, data) {
		var calendar = getCalendar(calendarId)
		if (!calendar) {
			logger.debug('googleCalendarManager.missingCalendar', calendarId)
			calendar = {
				accessRole: 'reader',
				backgroundColor: null,
				primary: false,
				summary: calendarId,
			}
		}
		data.items.forEach(function(event){
			parseEvent(calendar, event)
		})
		EventTypes.splitWorkingLocations(data)
	}

	// Popup reminder minutes from the event, or the calendar defaults.
	// [] = the event has no reminders. undefined = unknown (use the widget setting).
	function parseReminderMinutes(calendar, event) {
		var reminders = event.reminders
		if (!reminders) {
			return undefined
		}
		var list = reminders.useDefault ? calendar.defaultReminders : reminders.overrides
		if (!list) {
			return reminders.useDefault ? undefined : []
		}
		var minutes = []
		for (var i = 0; i < list.length; i++) {
			if (list[i].method === 'popup' && typeof list[i].minutes === 'number') {
				minutes.push(list[i].minutes)
			}
		}
		return minutes
	}

	// The event color palette changed: recolor the loaded events now (no refetch needed).
	function recolorEvents() {
		for (var calendarId in googleCalendarManager.eventsByCalendar) {
			var calendar = getCalendar(calendarId)
			var data = googleCalendarManager.eventsByCalendar[calendarId]
			if (!calendar || !data || !data.items) {
				continue
			}
			for (var i = 0; i < data.items.length; i++) {
				data.items[i].backgroundColor = parseColor(calendar, data.items[i])
			}
			calendarFetched(calendarId, data) // EventModel keeps its own copy
		}
	}

	function parseEvent(calendar, event) {
		event.description = event.description || ""
		event.reminderMinutes = parseReminderMinutes(calendar, event)
		// Set on the event itself (not the calendar's defaults): used even when the widget's own
		// reminder time is chosen over Google's (UpcomingEvents.reminderMinutesFor).
		event.reminderOwn = !!(event.reminders && event.reminders.useDefault === false)
		event.backgroundColor = parseColor(calendar, event)
		// Recurring events: edits and deletes apply to this occurrence only (Google makes it an exception).
		event.canEdit = (calendar.accessRole === 'writer' || calendar.accessRole === 'owner')
		if (plasmoid.configuration.googleHideGoalsDesc
			&& event.organizer // Not every event has one
			&& event.organizer.email === "unknownorganizer@calendar.google.com"
			&& event.organizer.displayName === "Google Calendar"
		) {
			event.description = ""
		}
		if (event.htmlLink) {
			// The new material website doesn't open the editor right away.
			// The htmlLink will select the event in the month view, forcing the
			// user to click the edit icon after loading the page.
			// Example htmlLink: "https://www.google.com/calendar/event?eid=...&ctz=Etc/UTC"
			// Which redirects to: "https://calendar.google.com/calendar/u/0/r/month/2021/12/31?eid=...&sf=true"
			if (plasmoid.configuration.googleEventClickAction === 'WebEventView') {
				var eidRegex = /eid=(\w+)(\&|$)/
				var eidMatch = eidRegex.exec(event.htmlLink)
				if (eidMatch) {
					var eid = eidMatch[1]
					if (eid) {
						event.htmlLink = 'https://calendar.google.com/calendar/r/eventedit/' + eid
					}
				}
			}
			// WebMonthView: the htmlLink as it is.
		}
	}

	function parseColorId(colorIdType, colorId) {
		// Use hardcoded colorIdMap rather than requesting the list from the API.
		// We could possibly fetch this in the config...
		if (typeof colorId !== "undefined") {
			var typeMap = ColorIdMap.colorIdMap[colorIdType]
			if (typeMap) {
				var colorIdStr = "" + colorId // Cast to string
				if (typeMap[colorIdStr]) {
					return typeMap[colorId]['background']
				}
			}
		}
		return null
	}

	// "current": the colors Google Calendar shows today; "classic": the old palette the API returns.
	readonly property bool currentGooglePalette: plasmoid.configuration.googleColorPalette !== 'classic'
	function parseColor(calendar, event) {
		if (currentGooglePalette) {
			return GooglePalette.eventColor(event.colorId) || GooglePalette.calendarColor(calendar)
		}
		return parseColorId('event', event.colorId) || calendar.backgroundColor
	}

	//--- Create / POST
	function createEvent(calendarId, date, text) {
		// No date: Google reads the day from the text (eg: "tomorrow"), relative to today.
		var eventText = text
		if (date) {
			var pad = function(n) { return (n < 10 ? '0' : '') + n }
			eventText = date.getFullYear() + '-' + pad(date.getMonth() + 1) + '-' + pad(date.getDate()) + ' ' + text
		}
		googleRequest('POST', eventPath(unscopedCalendarId(calendarId)) + '/quickAdd', {
			text: eventText,
		}, "", function(err, data, xhr) {
			if (err) {
				createEvent_err(err, data, xhr)
			} else {
				createEvent_done(calendarId, data)
			}
		})
	}
	function createEvent_done(calendarId, data) {
		var rawCalendarId = unscopedCalendarId(calendarId)
		var calendar = getCalendar(calendarId)
		var selectedList = getCalendarIdList()
		var isPrimarySelected = calendar && calendar.primary && selectedList.indexOf('primary') >= 0
		if (selectedList.indexOf(rawCalendarId) >= 0 || isPrimarySelected) {
			parseSingleEvent(calendarId, data)
			addEvent(calendarId, data)
			eventCreated(calendarId, data)
		}
	}
	function createEvent_err(err, data, xhr) {
		logger.log(calendarManagerId, 'createEvent_err', xhr && xhr.status)
		return handleError(err, data, xhr)
	}

	// Create an event from full data: { summary, start, end, location, description, recurrence }.
	// done(err): optional, called once the server answered, err null when it's saved (eg: to
	// refetch the occurrences of a recurring event).
	// params: optional query params, eg: { sendUpdates: 'all', conferenceDataVersion: 1 }.
	function createEventFromData(calendarId, eventData, done, params) {
		googleRequest('POST', eventPath(unscopedCalendarId(calendarId)), params, eventData, function(err, data, xhr) {
			if (err) {
				createEvent_err(err, data, xhr)
			} else {
				createEvent_done(calendarId, data)
			}
			if (done) {
				done(err || null)
			}
		})
	}

	//--- Import (.ics)
	// Import an event body (see IcsImport.googleEventBody) with events.import: it keeps the
	// iCalUID, so importing the same invitation twice updates the event instead of adding a copy.
	// Sends no invitations. done(err, data): err is a short message, or null. The caller refetches.
	function importEvent(calendarId, eventData, done) {
		googleRequest('POST', eventPath(unscopedCalendarId(calendarId)) + '/import', null, eventData, function(err, data, xhr) {
			if (err) {
				logger.log(calendarManagerId, 'importEvent_err', xhr && xhr.status) // No event data in logs
				done(requestErrorText(err, xhr) || IcsImport.errorMessage(err, data, xhr.status), null)
				return
			}
			done(null, data)
		})
	}

	// The message of a request that failed without an answer from Google (no access token,
	// offline), else ''.
	function requestErrorText(err, xhr) {
		if (!xhr) {
			return i18n("Google authentication failed: %1", err)
		}
		return Requests.isNetworkError(xhr) ? i18n("Could not connect") : ''
	}

	//--- Update Event
	// Fetch an event as stored on the server, eg: the series of a recurring event's occurrence.
	function fetchEvent(calendarId, eventId, callback) {
		fetchGoogleCalendarEvent(calendarId, eventId, callback)
	}

	// Update an event from its server copy: buildArgs(serverEvent) returns the changed fields.
	// Used for recurring series (occurrences are separate events here) and recurrence changes.
	// The occurrences change on the server, so done() should refetch.
	// options: optional { params } with query params for the PUT (see createEventFromData).
	// Optional failed(report): called instead of showing the error; report() shows it.
	function updateEventFromServer(calendarId, eventId, buildArgs, done, options, failed) {
		getServerEvent(calendarId, eventId, function(err, serverEvent, xhr) {
			if (err || !serverEvent) {
				updateFromServer_failed(failed, err, serverEvent, xhr)
				return
			}
			var data = mergeArgs(cloneRawEvent(serverEvent), buildArgs(serverEvent))
			updateGCalEvent(calendarId, eventId, data, options && options.params, function(err2, data2, xhr2) {
				if (err2) {
					updateFromServer_failed(failed, err2, data2, xhr2)
				} else if (done) {
					done()
				}
			})
		})
	}

	function updateFromServer_failed(failed, err, data, xhr) {
		var report = function() {
			updateGoogleCalendarEvent_err(err, data, xhr)
		}
		if (failed) {
			failed(report)
		} else {
			report()
		}
	}

	// Undo a delete: Google keeps a deleted event (or occurrence, or series) as cancelled, so
	// it's confirmed again. If that fails, copy (Undo.restoreCopy, single events only) is created
	// as a new event. done() should refetch.
	function restoreEvent(calendarId, eventId, copy, done) {
		updateEventFromServer(calendarId, eventId, function() {
			return { status: 'confirmed' }
		}, done, null, function(report) {
			if (copy) {
				createEventFromData(calendarId, copy, done)
			} else {
				report()
			}
		})
	}

	// options: optional { params } with query params for the PUT (see createEventFromData).
	function setEventProperties(calendarId, eventId, args, options) {
		updateGoogleCalendarEvent(calendarId, eventId, args, options)
	}

	function updateGoogleCalendarEvent(calendarId, eventId, args, options) {
		var event = getEvent(calendarId, eventId)
		if (!event) {
			logger.log(calendarManagerId, 'updateGoogleCalendarEvent', 'event not loaded')
			return
		}
		var params = options && options.params
		var callback = function(err, data, xhr) {
			if (err) {
				updateGoogleCalendarEvent_err(err, data, xhr)
			} else {
				updateGoogleCalendarEvent_done(calendarId, eventId, event, data, args)
			}
		}
		// Shown from the disk cache (no guests, description, ...): a PUT of that copy would wipe
		// them, so start from the server copy.
		if (event.fromCache) {
			getServerEvent(calendarId, eventId, function(err, serverEvent, xhr) {
				if (err || !serverEvent) {
					updateGoogleCalendarEvent_err(err, serverEvent, xhr)
					return
				}
				updateGCalEvent(calendarId, eventId, mergeArgs(cloneRawEvent(serverEvent), args), params, callback)
			})
		} else {
			updateGCalEvent(calendarId, eventId, mergeArgs(cloneRawEvent(event), args), params, callback)
		}
	}
	function updateGoogleCalendarEvent_done(calendarId, eventId, event, data, args) {
		// Fields removed by the update (eg: colorId, a removed Meet) are missing from the response:
		// drop them from the event too.
		for (var key in (args || {})) {
			if (!(key in data)) {
				delete event[key]
				if (key === 'conferenceData') {
					delete event.hangoutLink
				}
			}
		}
		// Merge serialized values
		Shared.merge(event, data)

		parseSingleEvent(calendarId, event)
		eventUpdated(calendarId, eventId, event)
	}
	function updateGoogleCalendarEvent_err(err, data, xhr) {
		logger.log(calendarManagerId, 'updateGoogleCalendarEvent_err', xhr && xhr.status)
		return handleError(err, data, xhr)
	}

	// PUT the whole event (data). params: optional query params.
	function updateGCalEvent(calendarId, eventId, data, params, callback) {
		// The body is the whole event (cloneRawEvent), file attachments included: say we support
		// them, or Google may drop them from the updated event.
		var query = { supportsAttachments: true }
		for (var key in (params || {})) {
			query[key] = params[key]
		}
		googleRequest('PUT', eventPath(unscopedCalendarId(calendarId), eventId), query, data, callback)
	}

	//--- Move Event
	// Move an event, or a whole recurring series (eventId = its recurringEventId), to another
	// calendar of the same account (Google events.move). The moved event keeps its id. The loaded
	// copies are removed from the source calendar; done(err, movedEvent) should refetch to show it
	// in the destination. done is always called. params: optional query params, eg: { sendUpdates: 'all' }.
	function moveEvent(calendarId, eventId, destinationCalendarId, done, params) {
		// Only within this account: the scoped id of another account isn't one of our calendars.
		if (accountId && destinationCalendarId.indexOf(accountId + "::") !== 0) {
			logger.log(calendarManagerId, 'moveEvent', 'destination is in another account')
			if (done) {
				done('moveEvent: destination is in another account', null)
			}
			return
		}
		var query = { destination: unscopedCalendarId(destinationCalendarId) }
		for (var key in (params || {})) {
			query[key] = params[key]
		}
		googleRequest('POST', eventPath(unscopedCalendarId(calendarId), eventId) + '/move', query, "", function(err, data, xhr) {
			if (err) {
				logger.log(calendarManagerId, 'moveEvent_err', xhr && xhr.status)
				handleError(err, data, xhr)
			} else {
				moveEvent_done(calendarId, eventId)
			}
			if (done) {
				done(err, data)
			}
		})
	}
	// The event (or the series' loaded occurrences) left this calendar.
	function moveEvent_done(calendarId, eventId) {
		var items = eventItems(calendarId).slice()
		for (var i = 0; i < items.length; i++) {
			if (items[i].id === eventId || items[i].recurringEventId === eventId) {
				removeEvent(calendarId, items[i].id)
			}
		}
	}

	//--- Delete Event
	// Optional done(err), always called.
	function deleteEvent(calendarId, eventId, done) {
		var event = getEvent(calendarId, eventId)
		if (!event) {
			logger.log(calendarManagerId, 'deleteEvent', 'event not loaded')
			if (done) {
				done('deleteEvent: event not loaded')
			}
			return
		}
		deleteGCalEvent(calendarId, eventId, function(err, data, xhr) {
			if (!err) {
				// Note: No data is returned on success
				var deleted = getEvent(calendarId, eventId)
				if (deleted) {
					removeEvent(calendarId, eventId)
					eventDeleted(calendarId, eventId, deleted)
				}
			}
			if (done) {
				done(err)
			}
		})
	}

	// Delete a whole recurring series by its id (an occurrence's recurringEventId). The loaded
	// occurrences are removed locally; done(err) is called either way.
	function deleteSeries(calendarId, seriesId, done) {
		if (!seriesId) {
			if (done) {
				done('deleteSeries: no series')
			}
			return
		}
		deleteGCalEvent(calendarId, seriesId, function(err, data, xhr) {
			if (!err) {
				var items = eventItems(calendarId).slice()
				for (var i = 0; i < items.length; i++) {
					if (items[i].recurringEventId === seriesId || items[i].id === seriesId) {
						removeEvent(calendarId, items[i].id)
						eventDeleted(calendarId, items[i].id, items[i])
					}
				}
			}
			if (done) {
				done(err)
			}
		})
	}

	// DELETE an event. Success is 204 (No Content). Errors are shown.
	function deleteGCalEvent(calendarId, eventId, callback) {
		googleRequest('DELETE', eventPath(unscopedCalendarId(calendarId), eventId), null, undefined, function(err, data, xhr) {
			if (err) {
				logger.log(calendarManagerId, 'deleteEvent_err', xhr && xhr.status)
				handleError(err, data, xhr)
			}
			callback(err, data, xhr)
		})
	}

	//--- Free / busy (Find a time)
	// Busy times of calendars (people's emails, or 'primary') of this account's view between from
	// and to (Dates). done(err, data): data is Google's answer, { calendars: { id: { busy, errors } } };
	// err a short message. calendarId: any calendar of the account (picks the account).
	function freeBusy(calendarId, ids, from, to, done) {
		googleRequest('POST', '/freeBusy', null, {
			timeMin: from.toISOString(),
			timeMax: to.toISOString(),
			timeZone: 'UTC',
			items: ids.map(function(id) { return { id: id } }),
		}, function(err, data, xhr) {
			if (err) {
				logger.log(calendarManagerId, 'freeBusy_err', xhr && xhr.status) // No emails in logs
				done(requestErrorText(err, xhr) || i18n("Could not get the free / busy times"), null)
				return
			}
			logger.debug(calendarManagerId, 'freeBusy', ids.length, 'calendars')
			done(null, data)
		})
	}

	// You in freeBusy: this account's primary calendar (its raw id is the account's email), else
	// Google's 'primary' (the account of the token).
	function ownFreeBusyId() {
		var account = getAccount()
		var list = (account && account.calendarList) || []
		for (var i = 0; i < list.length; i++) {
			if (list[i].primary === true && list[i].id) {
				return String(list[i].id)
			}
		}
		return 'primary'
	}

	//--- CalendarManager
	function getCalendarList() {
		var account = getAccount()
		if (!account || !account.calendarList) {
			return []
		}
		var calendarList = account.calendarList
		var out = []
		for (var i = 0; i < calendarList.length; i++) {
			out.push(decorateCalendar(calendarList[i]))
		}
		return out
	}

	function getCalendar(calendarId) {
		var account = getAccount()
		if (!account || !account.calendarList) {
			return null
		}
		var rawCalendarId = unscopedCalendarId(calendarId)
		for (var i = 0; i < account.calendarList.length; i++) {
			var calendar = account.calendarList[i]
			if (rawCalendarId === calendar.id || (rawCalendarId === 'primary' && calendar.primary)) {
				return decorateCalendar(calendar)
			}
		}
		return null
	}
}
