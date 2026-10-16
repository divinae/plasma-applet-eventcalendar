import QtQuick

import "../ErrorType.js" as ErrorType
import "../Shared.js" as Shared
import "../lib/Async.js" as Async
import "../lib/Requests.js" as Requests
import "../code/ColorIdMap.js" as ColorIdMap

CalendarManager {
	id: googleCalendarManager

	calendarManagerId: "GoogleCalendar"

	property var session
	property var accountsStore
	property string accountId: ""
	property string accountLabel: ""

	function getAccount() {
		if (!accountsStore || !accountId) {
			return null
		}
		return accountsStore.getAccount(accountId)
	}

	function getCalendarIdList() {
		var account = getAccount()
		if (!account) {
			return []
		}
		var list = account.calendarIdList || []
		if (account.calendarSelectionInitialized) {
			return list
		}
		if (list.length) {
			if (accountsStore && accountId) {
				accountsStore.updateAccount(accountId, { calendarSelectionInitialized: true })
			}
			return list
		}
		return []
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

	function formatCalendarSummary(calendar) {
		if (accountLabel) {
			return accountLabel + " - " + calendar.summary
		}
		return calendar.summary
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
		if (!session.accessToken) {
			return
		}
		var idList = getCalendarIdList()
		if (idList.length) { // Avoid a token refresh when nothing is selected.
			fetchGoogleAccountEvents(idList)
		}
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
	function handleError(err, data, xhr) {
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
	function handleAuthError(err, markDone) {
		if (markDone) {
			googleCalendarManager.asyncRequestsDone += 1
		}
		var message = i18n("Google authentication failed: %1", err)
		googleCalendarManager.error(message, ErrorType.ClientError)
	}
	function withAccessToken(action, onError) {
		session.checkAccessToken(function(err) {
			if (err) {
				if (onError) {
					onError(err)
				}
				return
			}
			action()
		})
	}

	//--- Utils
	function cloneRawEvent(event) {
		// Clone the event data and clean up the extra stuff we added when parsing the event.
		var data = JSON.parse(JSON.stringify(event)) // clone
		if (data.description === "") delete data.description
		if (data.calendarManagerId) delete data.calendarManagerId
		if (data.calendarId) delete data.calendarId
		delete data.startDateTime
		delete data.endDateTime
		delete data.canEdit
		delete data._summary
		delete data.reminderMinutes
		return data
	}

	//--- List Events
	function fetchGoogleAccountEvents(calendarIdList) {
		googleCalendarManager.asyncRequests += 1
		var generation = googleCalendarManager.fetchGeneration
		var func = fetchGoogleAccountEvents_run.bind(this, calendarIdList, function(errObj, data) {
			if (generation !== googleCalendarManager.fetchGeneration) {
				logger.debug('fetchGoogleAccountEvents', 'dropping stale response')
				return
			}
			if (errObj) {
				fetchGoogleAccountEvents_err(errObj.err, errObj.data, errObj.xhr)
			} else {
				fetchGoogleAccountEvents_done(data)
			}
		})
		withAccessToken(func, function(err) {
			handleAuthError(err, true)
		})
	}
	function fetchGoogleAccountEvents_run(calendarIdList, callback) {
		logger.debug('fetchGoogleAccountEvents_run', calendarIdList)

		var tasks = []
		for (var i = 0; i < calendarIdList.length; i++) {
			var calendarId = calendarIdList[i]
			var task = fetchGoogleCalendarEventsAllowError.bind(this, calendarId)
			tasks.push(task)
		}

		Async.parallel(tasks, callback)
	}

	function fetchGoogleCalendarEventsAllowError(calendarId, callback) {
		fetchGoogleCalendarEvents(calendarId, function(errObj, data) {
			if (errObj) {
				callback(null, {
					calendarId: calendarId,
					scopedCalendarId: scopedCalendarId(calendarId),
					error: errObj,
				})
				return
			}
			callback(null, data)
		})
	}
	function fetchGoogleAccountEvents_err(err, data, xhr) {
		logger.debug('fetchGoogleAccountEvents_err', err, data, xhr)
		googleCalendarManager.asyncRequestsDone += 1
		return handleError(err, data, xhr)
	}
	function fetchGoogleAccountEvents_done(results) {
		for (var i = 0; i < results.length; i++) {
			var result = results[i]
			if (!result) {
				continue
			}
			if (result.error) {
				var errObj = result.error
				if (errObj && errObj.xhr) {
					handleError(errObj.err, errObj.data, errObj.xhr)
				} else {
					googleCalendarManager.error(
						i18n("Error fetching calendar: %1", result.calendarId || ""),
						ErrorType.UnknownError
					)
				}
				continue
			}
			var calendarId = result.calendarId
			var calendarData = result.data
			var scopedId = result.scopedCalendarId || scopedCalendarId(calendarId)
			setCalendarData(scopedId, calendarData)
		}
		googleCalendarManager.asyncRequestsDone += 1
	}

	function fetchGoogleCalendarEvents(calendarId, callback) {
		logger.debug('fetchGoogleCalendarEvents', calendarId)
		fetchGCalEvents({
			calendarId: calendarId,
			start: googleCalendarManager.dateMin.toISOString(),
			end: googleCalendarManager.dateMax.toISOString(),
			accessToken: session.accessToken,
		}, function(err, data, xhr) {
			if (err) {
				logger.debugJSON('onErrorFetchingEvents: ', err)
				var errObj = {
					err: err,
					data: data,
					xhr: xhr,
				}
				return callback(errObj, null)
			}

			return callback(null, {
				calendarId: calendarId,
				scopedCalendarId: scopedCalendarId(calendarId),
				data: data,
			})
		})
	}

	function fetchGCalEvents(args, callback) {
		logger.debug('fetchGCalEvents', args.calendarId)

		// return GoogleCalendarTests.testCouldNotConnect(callback)
		// return GoogleCalendarTests.testInvalidCredentials(callback)
		// return GoogleCalendarTests.testDailyLimitExceeded(callback)
		// return GoogleCalendarTests.testBackendError(callback)

		var onResponse = fetchGCalEventsPageResponse.bind(this, args, callback, null)
		fetchGCalEventsPage(args, onResponse)
	}

	function fetchGCalEventsPageResponse(args, finishedCallback, allData, err, data, xhr) {
		logger.debug('fetchGCalEventsPageResponse', args, finishedCallback, allData, err, data, xhr)
		if (err) {
			return finishedCallback(err, data, xhr)
		}
		if (allData) {
			data.items = allData.items.concat(data.items)
			delete allData.items
			delete allData
		}
		allData = data
		
		if (allData.nextPageToken) {
			logger.debug('fetchGCalEventsPageResponse.nextPageToken', allData.nextPageToken)
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
			if (!err && data && data.error) {
				return pageCallback(data, null, xhr)
			}
			pageCallback(err, data, xhr)
		})
	}

	//--- Get Single Event
	function fetchGoogleCalendarEvent(calendarId, eventId, callback) {
		logger.debug('fetchGoogleCalendarEvent', calendarId, eventId)
		if (session.accessToken) {
			var func = fetchGoogleCalendarEvent_run.bind(this, calendarId, eventId, callback)
			withAccessToken(func, function(err) {
				handleAuthError(err, false)
			})
		} else {
			session.transactionError('attempting to "fetch an event" without an access token set')
		}
	}
function fetchGoogleCalendarEvent_run(calendarId, eventId, callback) {
	logger.debugJSON('fetchGoogleCalendarEvent_run', calendarId, eventId)
	fetchGCalEvent({
		accessToken: session.accessToken,
		calendarId: unscopedCalendarId(calendarId),
		eventId: eventId,
	}, callback)
}
	function fetchGCalEvent(args, callback) {
		logger.debug('fetchGCalEvent', args.calendarId, args.eventId)

		var url = 'https://www.googleapis.com/calendar/v3'
		url += '/calendars/'
		url += encodeURIComponent(args.calendarId)
		url += '/events/'
		url += encodeURIComponent(args.eventId)
		url += '?timeZone=' + encodeURIComponent('Etc/UTC')
		Requests.getJSON({
			url: url,
			headers: {
				"Authorization": "Bearer " + args.accessToken,
			}
		}, function(err, data, xhr) {
			logger.debug('fetchGCalEvent.response', args.calendarId, args.eventId, err, data, xhr.status)
			if (!err && data && data.error) {
				return callback(data, null, xhr)
			}
			logger.debugJSON('\t data:', data)
			callback(err, data, xhr)
		})
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

	function parseEvent(calendar, event) {
		event.description = event.description || ""
		event.reminderMinutes = parseReminderMinutes(calendar, event)
		event.backgroundColor = parseColor(calendar, event)
		// Recurring events: edits and deletes apply to this occurrence only (Google makes it an exception).
		event.canEdit = (calendar.accessRole === 'writer' || calendar.accessRole === 'owner')
		if (plasmoid.configuration.googleHideGoalsDesc
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
			} else if (plasmoid.configuration.googleEventClickAction === 'WebMonthView') {
				// Default behavior
			}
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

	function parseColor(calendar, event) {
		var colorId = parseColorId('event', event.colorId)
		// event.backgroundColor is a hardcoded color (like the debug calendar)
		return event.backgroundColor || colorId || calendar.backgroundColor
	}

	//--- Create / POST
	function createEvent(calendarId, date, text) {
		if (session.accessToken) {
			var dateString = date.getFullYear() + '-' + (date.getMonth()+1) + '-' + date.getDate()
			var eventText = dateString + ' ' + text

			var func = createEvent_run.bind(this, calendarId, eventText, function(err, data, xhr) {
				if (err) {
					createEvent_err(err, data, xhr)
				} else {
					createEvent_done(calendarId, data)
					if (done) {
						done()
					}
				}
			})
			withAccessToken(func, function(err) {
				handleAuthError(err, false)
			})
		} else {
			session.transactionError('attempting to "create an event" without an access token set')
		}
	}
	function createEvent_run(calendarId, eventText, callback) {
		logger.debugJSON(calendarManagerId, 'createEvent_run', calendarId, eventText)
		var rawCalendarId = unscopedCalendarId(calendarId)
		createGCalEvent({
			accessToken: session.accessToken,
			calendarId: rawCalendarId,
			text: eventText,
		}, callback)
	}
	function createEvent_done(calendarId, data) {
		logger.debugJSON(calendarManagerId, 'createEvent_done', calendarId, data)
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
		logger.log(calendarManagerId, 'createEvent_err', err, data, xhr)
		return handleError(err, data, xhr)
	}

	// Create an event from full data: { summary, start, end, location, description, recurrence }.
	// done(): called after it's saved (eg: to refetch the occurrences of a recurring event).
	function createEventFromData(calendarId, eventData, done) {
		if (!session.accessToken) {
			session.transactionError('attempting to "create an event" without an access token set')
			return
		}
		var func = function() {
			var url = 'https://www.googleapis.com/calendar/v3/calendars/'
			url += encodeURIComponent(unscopedCalendarId(calendarId))
			url += '/events'
			Requests.postJSON({
				url: url,
				headers: {
					"Authorization": "Bearer " + session.accessToken,
				},
				data: eventData,
			}, function(err, data, xhr) {
				if (!err && data && data.error) {
					err = data
				}
				if (err) {
					createEvent_err(err, data, xhr)
				} else {
					createEvent_done(calendarId, data)
				}
			})
		}
		withAccessToken(func, function(err) {
			handleAuthError(err, false)
		})
	}

	function createGCalEvent(args, callback) {
		// https://www.googleapis.com/calendar/v3/calendars/calendarId/events/quickAdd
		var url = 'https://www.googleapis.com/calendar/v3'
		url += '/calendars/'
		url += encodeURIComponent(args.calendarId)
		url += '/events/quickAdd'
		url += '?text=' + encodeURIComponent(args.text)
		Requests.postJSON({
			url: url,
			headers: {
				"Authorization": "Bearer " + args.accessToken,
			},
			data: "",
		}, function(err, data, xhr) {
			logger.debug('createGCalEvent.response', err, data, xhr.status)
			if (!err && data && data.error) {
				return callback(data, null, xhr)
			}
			callback(err, data, xhr)
		})
	}

	//--- Update Event
	// Fetch an event as stored on the server, eg: the series of a recurring event's occurrence.
	function fetchEvent(calendarId, eventId, callback) {
		fetchGoogleCalendarEvent(calendarId, eventId, callback)
	}

	// Update an event from its server copy: buildArgs(serverEvent) returns the changed fields.
	// Used for recurring series (occurrences are separate events here) and recurrence changes.
	// The occurrences change on the server, so done() should refetch.
	function updateEventFromServer(calendarId, eventId, buildArgs, done) {
		if (!session.accessToken) {
			session.transactionError('attempting to "update an event" without an access token set')
			return
		}
		var func = function() {
			fetchGoogleCalendarEvent_run(calendarId, eventId, function(err, serverEvent, xhr) {
				if (err || !serverEvent) {
					updateGoogleCalendarEvent_err(err, serverEvent, xhr)
					return
				}
				var data = cloneRawEvent(serverEvent)
				Shared.merge(data, buildArgs(serverEvent))
				updateGCalEvent({
					accessToken: session.accessToken,
					calendarId: unscopedCalendarId(calendarId),
					eventId: eventId,
					data: data,
				}, function(err2, data2, xhr2) {
					if (err2) {
						updateGoogleCalendarEvent_err(err2, data2, xhr2)
					} else if (done) {
						done()
					}
				})
			})
		}
		withAccessToken(func, function(err) {
			handleAuthError(err, false)
		})
	}

	function setEventProperty(calendarId, eventId, key, value) {
		logger.debug(calendarManagerId, 'setEventProperty', calendarId, eventId, key, value)
		var args = {}
		args[key] = value
		setEventProperties(calendarId, eventId, args)
	}

	function setEventProperties(calendarId, eventId, args) {
		logger.debugJSON(calendarManagerId, 'setEventProperties', calendarId, eventId, args)
		updateGoogleCalendarEvent(calendarId, eventId, args)
	}

	function updateGoogleCalendarEvent(calendarId, eventId, args) {
		if (session.accessToken) {
			var event = getEvent(calendarId, eventId)
			if (!event) {
				session.transactionError('attempting to "set an event property" for an event that doesn\'t exist')
				return
			}

			var func = updateGoogleCalendarEvent_run.bind(this, calendarId, eventId, event, args, function(err, data, xhr) {
				if (err) {
					updateGoogleCalendarEvent_err(err, data, xhr)
				} else {
					updateGoogleCalendarEvent_done(calendarId, eventId, event, data)
				}
			})
			withAccessToken(func, function(err) {
				handleAuthError(err, false)
			})
		} else {
			session.transactionError('attempting to "set an event property" without an access token set')
		}
	}
	function updateGoogleCalendarEvent_run(calendarId, eventId, event, args, callback) {
		logger.debugJSON('updateGoogleCalendarEvent_run', calendarId, eventId, event, args)

		// Merge assigned values into a cloned object
		var data = cloneRawEvent(event)
		Shared.merge(data, args)
		logger.debugJSON('updateGoogleCalendarEvent', 'sent', data)

		updateGCalEvent({
			accessToken: session.accessToken,
			calendarId: unscopedCalendarId(calendarId),
			eventId: eventId,
			data: data,
		}, callback)
	}
	function updateGoogleCalendarEvent_done(calendarId, eventId, event, data) {
		logger.debugJSON('updateGoogleCalendarEvent_done', calendarId, data)

		// Merge serialized values
		Shared.merge(event, data)

		parseSingleEvent(calendarId, event)
		eventUpdated(calendarId, eventId, event)
	}
	function updateGoogleCalendarEvent_err(err, data, xhr) {
		logger.log('updateGoogleCalendarEvent_err', err, data, xhr)
		return handleError(err, data, xhr)
	}

	function updateGCalEvent(args, callback) {
		// PUT https://www.googleapis.com/calendar/v3/calendars/calendarId/events/eventId
		var url = 'https://www.googleapis.com/calendar/v3'
		url += '/calendars/'
		url += encodeURIComponent(args.calendarId)
		url += '/events/'
		url += encodeURIComponent(args.eventId)
		Requests.postJSON({
			method: 'PUT',
			url: url,
			headers: {
				"Authorization": "Bearer " + args.accessToken,
			},
			data: args.data,
		}, function(err, data, xhr) {
			logger.debug('updateGCalEvent.response', err, data, xhr.status)
			if (!err && data && data.error) {
				return callback(data, null, xhr)
			}
			callback(err, data, xhr)
		})
	}

	//--- Delete Event
	function deleteEvent(calendarId, eventId) {
		logger.debug(calendarManagerId, 'deleteEvent', calendarId, eventId)
		if (session.accessToken) {
			var event = getEvent(calendarId, eventId)
			if (!event) {
				session.transactionError('attempting to "delete an event" for an event that doesn\'t exist')
				return
			}

			var func = deleteEvent_run.bind(this, calendarId, eventId, function(err, data, xhr) {
				if (err) {
					deleteEvent_err(err, data, xhr)
				} else {
					deleteEvent_done(calendarId, eventId, data)
				}
			})
			withAccessToken(func, function(err) {
				handleAuthError(err, false)
			})
		} else {
			session.transactionError('attempting to "delete an event" without an access token set')
		}
	}
	function deleteEvent_run(calendarId, eventId, callback) {
		logger.debugJSON(calendarManagerId, 'deleteEvent_run', calendarId, eventId)
		var rawCalendarId = unscopedCalendarId(calendarId)
		deleteGCalEvent({
			accessToken: session.accessToken,
			calendarId: rawCalendarId,
			eventId: eventId,
		}, callback)
	}
	function deleteEvent_done(calendarId, eventId, data) {
		logger.debugJSON(calendarManagerId, 'deleteEvent_done', calendarId, eventId, data)

		// Note: No data is returned on success
		var event = getEvent(calendarId, eventId)
		if (event) {
			removeEvent(calendarId, eventId)
			eventDeleted(calendarId, eventId, event)
		}
	}
	function deleteEvent_err(err, data, xhr) {
		logger.log(calendarManagerId, 'deleteEvent_err', err, data, xhr)
		return handleError(err, data, xhr)
	}

	function deleteGCalEvent(args, callback) {
		// DELETE https://www.googleapis.com/calendar/v3/calendars/calendarId/events/eventId
		// Note: Success means a response of xhr.status == 204 (No Content)
		var url = 'https://www.googleapis.com/calendar/v3'
		url += '/calendars/'
		url += encodeURIComponent(args.calendarId)
		url += '/events/'
		url += encodeURIComponent(args.eventId)
		Requests.postJSON({
			method: 'DELETE',
			url: url,
			headers: {
				"Authorization": "Bearer " + args.accessToken,
			},
		}, function(err, data, xhr) {
			logger.debug('deleteGCalEvent.response', err, data, xhr.status)
			if (!err && data && data.error) {
				return callback(data, null, xhr)
			}
			callback(err, data, xhr)
		})
	}

	//--- CalendarManager
	function getCalendarList() {
		var account = getAccount()
		if (!session.accessToken || !account || !account.calendarList) {
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
