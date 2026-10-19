import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "EventEdit.js" as EventEdit
import "EventTypes.js" as EventTypes
import "Guests.js" as Guests
import "LocaleFuncs.js" as LocaleFuncs
import "MeetingLink.js" as MeetingLink
import "Recurrence.js" as Recurrence
import "Reminders.js" as Reminders
import "SeriesEdit.js" as SeriesEdit
import "Shared.js" as Shared
import "TimeZone.js" as TimeZone
import "code/ColorIdMap.js" as ColorIdMap
import "code/GooglePalette.js" as GooglePalette
import "lib/ColorUtil.js" as ColorUtil
import "lib/Pkce.js" as Pkce

// Form to create a new event (eventItem == null) or edit an existing one.
Rectangle {
	id: form

	property var eventItem: null
	property date initialDate: new Date() // New events: day to create on
	property var initialStart: null // New events: exact start time (eg: clicked week view slot)
	property string initialTitle: "" // New events: title typed so far (eg: in quick add)
	property var templateEvent: null // New events: a copy of this event (Duplicate)
	readonly property bool isNew: !eventItem
	// Rows below a row with an icon line up with its text.
	readonly property real indent: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing
	signal closeRequested()

	//--- Recurrence
	// Occurrences of a recurring event are separate events here; their series is fetched from the server.
	readonly property bool isOccurrence: !isNew && !!eventItem.recurringEventId
	readonly property bool editSeries: isOccurrence && scopeCombo.currentIndex === 1
	property var seriesEvent: null
	property bool seriesLoading: false
	property string originalRule: "" // The series' RRULE line
	property string initialRepeatKey: "none"
	property string initialRepeatRule: ""
	// none, a preset key, custom (edited below the combo) or original (a rule the editor can't
	// show, kept as it is apart from its end).
	property string repeatKey: "none"
	property string customFreq: "WEEKLY"
	property int customInterval: 1
	property var customDays: [] // BYDAY codes, for WEEKLY
	property string endType: "never" // never, until, count
	property var endDate: null // Last day, inclusive
	property int endCount: 10
	property string lastStartDay: ""
	readonly property bool supportsRecurrence: !!calendarSelector.selectedCalendarId
		&& eventModel.supportsRecurrence(calendarSelector.selectedCalendarId)
	readonly property bool canEditRepeat: supportsRecurrence && !seriesLoading && (!isOccurrence || editSeries)

	// The rule for the repeat options, for an event starting on `start`.
	function repeatRuleAt(start) {
		var allDay = allDayCheckBox.checked
		var rule
		if (repeatKey === 'original') {
			rule = originalRule
		} else if (repeatKey === 'custom') {
			rule = Recurrence.buildRule({
				freq: customFreq,
				interval: customInterval,
				byDay: customDays,
				byMonthDay: customFreq === 'MONTHLY' ? start.getDate() : 0,
			}, allDay)
		} else {
			rule = Recurrence.presetRule(repeatKey, start)
		}
		return Recurrence.withEnd(rule, { type: endType, date: endDate, count: endCount }, allDay)
	}
	function repeatRule() {
		return repeatRuleAt(durationSelector.startDateTime)
	}
	function setCustom(custom) {
		customFreq = custom.freq
		customInterval = custom.interval
		customDays = custom.byDay
	}
	function setInitialRepeat(rule, start) {
		originalRule = rule
		var key = Recurrence.matchPreset(rule, start)
		if (!key) {
			key = Recurrence.parseRule(rule).supported ? 'custom' : 'original'
		}
		setCustom(Recurrence.customOf(rule, start))
		var end = Recurrence.endOf(rule)
		endType = end.type
		if (end.date) {
			endDate = end.date
		}
		if (end.count) {
			endCount = end.count
		}
		initialRepeatKey = key
		repeatKey = key
		// The rule as the options give it at the original date: moving the event to another weekday
		// (weekly) or day (monthly) changes it, and the series' rule follows, keeping its end.
		initialRepeatRule = repeatRuleAt(start)
	}
	readonly property bool repeatChanged: repeatRule() !== initialRepeatRule
	// A custom weekly repeat on the event's own weekday moves with the event, like the weekly preset.
	function followStartDay() {
		var code = Recurrence.dayCodes[durationSelector.startDateTime.getDay()]
		if (customDays.length === 1 && customDays[0] === lastStartDay) {
			customDays = [code]
		}
		lastStartDay = code
	}
	function toggleCustomDay(code) {
		var days = customDays.slice()
		var i = days.indexOf(code)
		if (i < 0) {
			days.push(code)
		} else if (days.length > 1) { // At least one day
			days.splice(i, 1)
		}
		customDays = days
	}
	Connections {
		target: durationSelector
		function onStartDateTimeChanged() { form.followStartDay() }
	}
	function calendarTimeZone() {
		var calendar = calendarSelector.selectedCalendar
		if (calendar && calendar.timeZone) {
			return calendar.timeZone
		}
		if (seriesEvent && seriesEvent.start && seriesEvent.start.timeZone) {
			return seriesEvent.start.timeZone
		}
		return 'UTC'
	}
	// Google needs a time zone on the start / end of recurring timed events (to expand them).
	function withTimeZone(obj) {
		if (obj.dateTime && !obj.timeZone) {
			obj.timeZone = timeZone || calendarTimeZone()
		}
		return obj
	}

	//--- Time zone (Google): the editor's times are the wall clock in `timeZone` (the selectors
	// show local Dates with that clock time; see TimeZone.toWallDate). '' = local time.
	property string timeZone: ""
	property string initialTimeZone: ""
	property bool timeZoneTouched: false // Picked by the user: no longer follows the calendar
	readonly property bool supportsTimeZone: supportsRecurrence
	readonly property bool timeZoneChanged: supportsTimeZone && !allDayCheckBox.checked && timeZone !== initialTimeZone
	// The local zone's id: from the time data engine (Plasma), else one with the same rules.
	function localZoneName() {
		var data = typeof timeModel !== "undefined" && timeModel.dataSource && timeModel.dataSource.data
		var local = data && data.Local && data.Local.Timezone
		if (local && TimeZone.knows(String(local))) {
			return String(local)
		}
		return TimeZone.guessLocal(Date.now())
	}
	// The zone a new or edited event starts in: its own, its calendar's or the local one.
	function defaultTimeZone(item) {
		if (!supportsTimeZone) {
			return ""
		}
		if (item && item.start && item.start.timeZone) {
			return String(item.start.timeZone)
		}
		var calendar = calendarSelector.selectedCalendar
		return calendar && calendar.timeZone ? String(calendar.timeZone) : localZoneName()
	}
	// Instants of wall times shifted by the local DST gap (see TimeZone.toWallDate).
	property var wallMemo: ({})
	function toWall(instant) {
		return TimeZone.knows(timeZone) ? TimeZone.toWallDate(timeZone, instant, wallMemo) : new Date(instant)
	}
	function fromWall(wallDate) {
		return TimeZone.knows(timeZone) ? TimeZone.fromWallDate(timeZone, wallDate, wallMemo) : new Date(wallDate)
	}
	// The event's start / end instants.
	function startInstant() {
		return fromWall(durationSelector.startDateTime)
	}
	function endInstant() {
		return fromWall(durationSelector.endDateTime)
	}
	// Picked by the user: the clock times stay, in the new zone (as in Google Calendar).
	function setTimeZone(zone) {
		timeZoneTouched = true
		timeZone = zone
	}
	// Another zone showing the same instants (eg: a new event's calendar changed).
	function moveToTimeZone(zone) {
		var start = startInstant()
		var end = endInstant()
		timeZone = zone
		durationSelector.startDateTime = toWall(start)
		durationSelector.endDateTime = toWall(end)
	}
	property bool initialized: false
	Connections {
		target: calendarSelector
		function onSelectedCalendarChanged() {
			if (form.isNew && form.initialized && !form.timeZoneTouched) {
				form.moveToTimeZone(form.defaultTimeZone(null))
			}
		}
	}
	// Local times of the event, when its zone shows another clock.
	readonly property string localTimesText: {
		if (!supportsTimeZone || allDayCheckBox.checked || !TimeZone.knows(timeZone)) {
			return ""
		}
		var start = fromWall(durationSelector.startDateTime)
		var end = fromWall(durationSelector.endDateTime)
		if (TimeZone.matchesLocal(timeZone, start.getTime())) {
			return ""
		}
		var format = { clock24h: appletConfig.clock24h }
		var text = LocaleFuncs.formatEventTime(start, format) + " – " + LocaleFuncs.formatEventTime(end, format)
		if (start.toDateString() !== durationSelector.startDateTime.toDateString()) {
			text = Qt.formatDate(start, i18nc("event editor date format", "d MMM, yyyy")) + " " + text
		}
		return i18nc("%1 = start and end time in the local time zone", "%1 your time", text)
	}
	function refetch() {
		logic.update()
	}

	//--- Calendar (Google): an existing event can move to another calendar of its account that we
	// can write to (Google events.move). An occurrence only with its whole series.
	// "account::" of the event's calendar, or '' (not a Google account calendar).
	readonly property string accountPrefix: {
		var id = !isNew && eventItem.calendarId ? String(eventItem.calendarId) : ''
		var i = id.indexOf('::')
		return i > 0 ? id.slice(0, i + 2) : ''
	}
	// Only the organizer's copy moves (it changes the organizer), and only default events
	// (not birthdays, focus time, out of office...).
	readonly property bool movable: accountPrefix !== '' && !!eventItem.canEdit && !isInvited
		&& (!eventItem.eventType || eventItem.eventType === 'default')
		&& eventModel.supportsMove(eventItem.calendarId)
	readonly property bool canMove: movable && (!isOccurrence || editSeries)
	readonly property bool moving: canMove && !!calendarSelector.selectedCalendarId
		&& calendarSelector.selectedCalendarId !== eventItem.calendarId
	onCanMoveChanged: {
		if (!canMove && !isNew) {
			calendarSelector.selectCalendar(eventItem.calendarId) // Back to "This event"
		}
	}
	// Move first when another calendar was picked, then update(model, calendarId, done) on the
	// calendar the event is in. Runs after the form closed: no ids of the form are used later on.
	function afterMove(eventId, update) {
		var model = eventModel
		if (!moving) {
			update(model, eventItem.calendarId, refetch)
			return
		}
		var appLogic = logic
		var target = calendarSelector.selectedCalendarId
		var done = function() {
			appLogic.update()
		}
		model.moveEvent(eventItem.calendarId, eventId, target, function(err) {
			if (!err) {
				update(model, target, done)
			}
		}, sendUpdatesChoice ? { sendUpdates: sendUpdatesChoice } : null)
	}

	//--- Event color (Google): '' = the calendar's color, else a colorId '1'..'11'.
	property string initialColorId: ""
	property string colorId: ""
	readonly property var colorNames: ({
		'1': i18nc("Google Calendar event color", "Lavender"),
		'2': i18nc("Google Calendar event color", "Sage"),
		'3': i18nc("Google Calendar event color", "Grape"),
		'4': i18nc("Google Calendar event color", "Flamingo"),
		'5': i18nc("Google Calendar event color", "Banana"),
		'6': i18nc("Google Calendar event color", "Tangerine"),
		'7': i18nc("Google Calendar event color", "Peacock"),
		'8': i18nc("Google Calendar event color", "Graphite"),
		'9': i18nc("Google Calendar event color", "Blueberry"),
		'10': i18nc("Google Calendar event color", "Basil"),
		'11': i18nc("Google Calendar event color", "Tomato"),
	})
	// A colorId as events show it (palette setting, dark theme).
	function swatchColor(id) {
		if (!id) {
			var calendar = calendarSelector.selectedCalendar
			return appletConfig.eventColor(calendar && calendar.backgroundColor || "")
		}
		if (plasmoid.configuration.googleColorPalette === 'classic') {
			var classic = ColorIdMap.colorIdMap.event[id]
			return appletConfig.eventColor(classic ? classic.background : "")
		}
		return appletConfig.eventColor(GooglePalette.eventColor(id))
	}
	//--- Reminders (Google): the calendar's defaults, or the event's own notification times
	property bool remindersCustom: false
	property var reminderItems: [] // [{ value, unit }]
	property var reminderOthers: [] // Other kinds (email), kept as they are
	property var initialReminders: ({ custom: false, items: [], others: [] })
	readonly property var reminderState: ({ custom: remindersCustom, items: reminderItems, others: reminderOthers })
	readonly property bool remindersChanged: !Reminders.sameAs(reminderState, initialReminders)
	readonly property bool canAddReminder: reminderItems.length + reminderOthers.length < Reminders.MAX_OVERRIDES
	function addReminder() {
		var used = reminderItems.map(Reminders.toMinutes)
		var minutes = [10, 30, 60, 1440, 5].filter(function(m) { return used.indexOf(m) < 0 })[0] || 15
		reminderItems = reminderItems.concat([Reminders.split(minutes)])
	}
	function setReminder(index, value, unit) {
		var items = reminderItems.slice()
		items[index] = { value: value, unit: unit }
		reminderItems = items
	}
	function removeReminder(index) {
		var items = reminderItems.slice()
		items.splice(index, 1)
		reminderItems = items
	}
	function fillReminders(item, asCopy) {
		var state = Reminders.fromEvent(item)
		remindersCustom = state.custom
		reminderItems = state.items
		reminderOthers = state.others
		if (!asCopy) {
			initialReminders = state
		}
	}

	//--- Show as and visibility (Google): transparency 'opaque' (busy, the default) or 'transparent'
	// (free); visibility 'default' (the calendar's), 'public', 'private' (or 'confidential', kept).
	property string initialTransparency: "opaque"
	property string transparency: "opaque"
	property string initialVisibility: "default"
	property string visibility: "default"
	// New events and copies start from the defaults, so only other values are sent.
	function fillAvailability(item, asCopy) {
		transparency = item.transparency === 'transparent' ? 'transparent' : 'opaque'
		visibility = item.visibility || 'default'
		if (!asCopy) {
			initialTransparency = transparency
			initialVisibility = visibility
		}
	}
	function addAvailabilityArgs(args) {
		if (!supportsRecurrence) {
			return
		}
		if (transparency !== initialTransparency) {
			args.transparency = transparency
		}
		if (visibility !== initialVisibility) {
			args.visibility = visibility
		}
	}

	//--- Event type (Google): new events on a primary calendar can be out of office or focus time.
	// An existing one keeps its type; its settings (auto-decline, chat status) can be changed.
	property string eventType: "default"
	property string autoDeclineMode: "declineNone"
	property string declineMessage: ""
	property string chatStatus: "doNotDisturb"
	readonly property bool canSetType: isNew && supportsRecurrence && !!calendarSelector.selectedCalendar
		&& calendarSelector.selectedCalendar.primary === true
	readonly property string effectiveType: isNew ? (canSetType ? eventType : "default") : eventType
	// Existing event: its settings as loaded (JSON of EventTypes.properties), '' until known (a copy
	// from the disk cache doesn't have them: they come from the server copy).
	property string initialTypeProperties: ""
	// No guests, video call, location or free time on these (Google refuses them), nor all day.
	readonly property bool isSpecialType: EventTypes.isSpecial(effectiveType)
	onIsSpecialTypeChanged: {
		if (isSpecialType) {
			allDayCheckBox.checked = false
		}
	}
	function setEventType(type) {
		// A title for an empty one, as Google Calendar does.
		var defaultTitles = ['', i18n("Out of office"), i18n("Focus time")]
		if (defaultTitles.indexOf(titleField.text.trim()) >= 0) {
			titleField.text = type === 'outOfOffice' ? defaultTitles[1] : (type === 'focusTime' ? defaultTitles[2] : '')
		}
		eventType = type
	}
	function typeOptions() {
		return {
			autoDeclineMode: autoDeclineMode,
			declineMessage: declineMessage,
			chatStatus: chatStatus,
		}
	}
	function addTypeArgs(data) {
		EventTypes.applyTo(data, effectiveType, typeOptions())
	}
	// Existing out of office / focus time event: its changed settings.
	function addTypePropertiesArgs(args) {
		if (isNew || !isSpecialType || !initialTypeProperties) {
			return
		}
		var props = EventTypes.properties(effectiveType, typeOptions())
		if (JSON.stringify(props) !== initialTypeProperties) {
			args[effectiveType === 'outOfOffice' ? 'outOfOfficeProperties' : 'focusTimeProperties'] = props
		}
	}
	function loadTypeOptions(item, asCopy) {
		var options = EventTypes.optionsOf(item)
		if (!options) {
			return
		}
		eventType = options.type
		autoDeclineMode = options.autoDeclineMode
		declineMessage = options.declineMessage
		chatStatus = options.chatStatus
		if (!asCopy) {
			initialTypeProperties = JSON.stringify(EventTypes.properties(options.type, options))
		}
	}

	//--- Video conferencing (Google Meet)
	readonly property bool hadConference: !isNew && !!(eventItem.hangoutLink || eventItem.conferenceData)
	property string conferenceAction: "" // '', 'add' or 'remove'
	readonly property bool hasConference: conferenceAction === 'add' || (hadConference && conferenceAction !== 'remove')
	readonly property var conferenceLink: hadConference ? MeetingLink.find(eventItem) : null
	// Unknown (calendar list saved before this was kept): offered, Google says if it can't.
	readonly property bool meetAllowed: {
		var calendar = calendarSelector.selectedCalendar
		var types = calendar && calendar.conferenceTypes
		return !types || Shared.toArray(types).indexOf('hangoutsMeet') >= 0
	}
	onMeetAllowedChanged: {
		if (!meetAllowed && conferenceAction === 'add') {
			conferenceAction = '' // Another calendar picked for a new event
		}
	}
	// Changes conferenceData: Google only reads it with conferenceDataVersion=1 (see requestParams).
	function addConferenceArgs(args) {
		if (conferenceAction === 'add' && !hadConference) {
			args.conferenceData = {
				createRequest: {
					requestId: Pkce.generateOpaqueToken(32),
					conferenceSolutionKey: { type: 'hangoutsMeet' },
				},
			}
		} else if (conferenceAction === 'remove' && hadConference) {
			args.conferenceData = null
		}
	}
	// Query params for the request: conferenceDataVersion when conferenceData is sent, and whether
	// guests get emails (asked before saving, see guestNoticeNeeded).
	function requestParams(args) {
		var params = {}
		if (sendUpdatesChoice) {
			params.sendUpdates = sendUpdatesChoice
		}
		if (typeof args.conferenceData !== 'undefined') {
			params.conferenceDataVersion = 1
		}
		return params
	}

	//--- Guests (Google): attendee objects, people only (rooms are kept as they are on save).
	property var initialGuests: []
	property var guests: []
	property var knownGuests: [] // Suggestions, from the loaded events
	property string guestError: ""
	// Invited by someone else: only the organizer changes the video call, and the guest list unless
	// guests may.
	readonly property bool isInvited: !isNew && !!eventModel.selfAttendee(eventItem)
	readonly property bool canEditGuests: !isInvited || !!eventItem.guestsCanModify
	readonly property bool guestsChanged: canEditGuests && Guests.emailsDiffer(initialGuests, guests)
	readonly property var guestSuggestions: Guests.suggest(knownGuests, guestField.text, guests, 5)
	function addGuest(email) {
		var result = Guests.addGuest(guests, email)
		if (result.error === 'invalid') {
			guestError = i18n("Enter an email address, like name@example.com")
			return false
		}
		guestError = ""
		guests = result.list
		guestField.text = ""
		return true
	}
	function addGuestFromField() {
		var text = guestField.text.trim()
		if (!text) {
			return
		}
		// A partly typed name or address: the first suggestion.
		if (!Guests.isValidEmail(text) && guestSuggestions.length) {
			text = guestSuggestions[0].email
		}
		addGuest(text)
	}
	function removeGuest(email) {
		guests = Guests.removeGuest(guests, email)
	}

	//--- Find a time (Google): the guests' busy times on the event's day, to pick a free slot.
	property bool findTimeOpen: false
	readonly property var otherGuests: guests.filter(function(guest) { return !guest.self && guest.email })
	readonly property bool canFindTime: supportsRecurrence && !isSpecialType && !allDayCheckBox.checked
		&& otherGuests.length > 0 && !!calendarSelector.selectedCalendarId
		&& !!eventModel.supportsFreeBusy && eventModel.supportsFreeBusy(calendarSelector.selectedCalendarId)
	function openFindTime() {
		findTimeOpen = true
	}
	// You in Find a time: the primary calendar of the selected calendar's account (its id is the
	// account's email), else Google's 'primary' (of that account: freeBusy goes through it).
	function ownFreeBusyId() {
		var id = String(calendarSelector.selectedCalendarId || '')
		return eventModel.ownFreeBusyId ? eventModel.ownFreeBusyId(id) : 'primary'
	}
	function findTimePeople() {
		var people = [{ id: ownFreeBusyId(), name: i18nc("you, in Find a time", "You") }]
		otherGuests.forEach(function(guest) {
			if (guest.email !== people[0].id) {
				people.push({ id: guest.email, name: guest.displayName || guest.email, email: guest.email })
			}
		})
		return people
	}
	// A slot picked in Find a time: same length, starting then.
	function pickSlot(start) {
		var length = endInstant().getTime() - startInstant().getTime()
		var s = new Date(start)
		durationSelector.startDateTime = toWall(s)
		durationSelector.endDateTime = toWall(new Date(s.getTime() + length))
		findTimeOpen = false
	}

	// Whether to ask before saving if guests get emails: 'invite' (new event with guests), 'update'
	// (guests changed, or the event has guests and its time, place or video call changed) or ''.
	property string sendUpdatesChoice: "" // 'all' or 'none' once answered
	property string guestNotice: "" // Shown while asking
	function guestNoticeNeeded() {
		if (!supportsRecurrence) {
			return ''
		}
		if (isNew) {
			return guests.length && !isSpecialType ? 'invite' : ''
		}
		if (guestsChanged) {
			return 'update'
		}
		if (!Guests.hasOtherGuests(eventItem.attendees)) {
			return ''
		}
		var timeChanged = timesChanged(eventItem) || (canEditRepeat && repeatChanged)
		var placeChanged = Shared.hasChanged(eventItem.location, locationField.text)
			|| (conferenceAction === 'add' && !hadConference) || (conferenceAction === 'remove' && hadConference)
		return timeChanged || placeChanged ? 'update' : ''
	}
	onGuestNoticeChanged: guestNoticeMessage.visible = guestNotice !== ""
	function answerGuestNotice(choice) {
		sendUpdatesChoice = choice
		guestNotice = ""
		save()
	}

	// The color changed: set its colorId, or undefined (removed from the update) for the calendar color.
	function addColorArgs(args) {
		if (supportsRecurrence && colorId !== initialColorId) {
			args.colorId = colorId || undefined
		}
	}

	color: Kirigami.Theme.backgroundColor
	radius: Kirigami.Units.cornerRadius * 2
	border.width: 1
	border.color: ColorUtil.setAlpha(Kirigami.Theme.textColor, 0.15)
	implicitHeight: actionsRow.implicitHeight + Kirigami.Units.smallSpacing * 2 + fieldsColumn.implicitHeight + Kirigami.Units.largeSpacing * 2


	// Google start / end objects. All-day events end at midnight the next day. Timed ones in UTC,
	// with the editor's time zone (Google).
	function timedObj(instant) {
		var obj = { dateTime: Shared.dateTimeString(instant) }
		if (supportsTimeZone && timeZone) {
			obj.timeZone = timeZone
		}
		return obj
	}
	function startObj() {
		if (!allDayCheckBox.checked) {
			return timedObj(startInstant())
		}
		return { date: Shared.localeDateString(durationSelector.startDateTime) }
	}
	function endObj() {
		if (!allDayCheckBox.checked) {
			return timedObj(endInstant())
		}
		var dayAfter = new Date(durationSelector.endDateTime)
		dayAfter.setDate(dayAfter.getDate() + 1)
		return { date: Shared.localeDateString(dayAfter) }
	}
	// The form's times differ from those of `item` (all day, start, end or time zone).
	function timesChanged(item) {
		return EventEdit.timesChanged(item, allDayCheckBox.checked, startObj(), endObj()) || timeZoneChanged
	}
	// The changes to `item` that an event and its whole series both get: text fields, color, show
	// as / visibility, video call, type settings and reminders.
	function changedArgs(item, summary) {
		var args = EventEdit.changedFields(item, {
			summary: summary,
			location: locationField.text,
			description: descriptionField.text,
		})
		addColorArgs(args)
		addAvailabilityArgs(args)
		addConferenceArgs(args)
		addTypePropertiesArgs(args)
		if (supportsRecurrence && remindersChanged) {
			args.reminders = Reminders.toGoogle(reminderState)
		}
		return args
	}

	function save() {
		var summary = titleField.text.trim()
		if (!summary) {
			titleField.forceActiveFocus()
			return
		}
		var notice = guestNoticeNeeded()
		if (notice && !sendUpdatesChoice) {
			guestNotice = notice
			return
		}
		if (isNew) {
			var data = EventEdit.changedFields(null, {
				summary: summary,
				start: startObj(),
				end: endObj(),
				location: locationField.text,
				description: descriptionField.text,
			})
			if (supportsRecurrence && colorId) {
				data.colorId = colorId
			}
			if (supportsRecurrence && remindersCustom) {
				data.reminders = Reminders.toGoogle(reminderState)
			}
			addAvailabilityArgs(data)
			if (supportsRecurrence) {
				addConferenceArgs(data)
				if (guests.length) {
					data.attendees = Guests.newAttendees(guests)
				}
			}
			var newRule = supportsRecurrence ? repeatRule() : ''
			if (newRule) {
				data.recurrence = [newRule]
				withTimeZone(data.start)
				withTimeZone(data.end)
			}
			addTypeArgs(data)
			// A new recurring event: its occurrences come from a refetch.
			eventModel.createEventFromData(calendarSelector.selectedCalendarId, data, newRule ? refetch : null, requestParams(data))
		} else if (editSeries) {
			saveSeries(summary)
		} else {
			var args = changedArgs(eventItem, summary)
			var options = { params: requestParams(args) }
			var start = startObj()
			var end = endObj()
			if (timesChanged(eventItem)) {
				// The update replaces start / end as a whole, so switching all-day <-> timed is clean.
				args.start = start
				args.end = end
			}
			var rule = repeatRule()
			var becomesRecurring = !isOccurrence && supportsRecurrence && rule && repeatChanged
			if (becomesRecurring) {
				// A single event becomes recurring.
				args.recurrence = [rule]
				args.start = withTimeZone(start)
				args.end = withTimeZone(end)
			}
			// Guests: the changes applied to the server's list (the loaded copy may be incomplete,
			// eg: from the event cache).
			var initial = initialGuests
			var edited = guests
			var guestEdit = guestsChanged
			var buildArgs = function(serverEvent) {
				if (guestEdit) {
					args.attendees = Guests.applyChanges(serverEvent.attendees, initial, edited)
				}
				return args
			}
			if (moving) {
				// Moved: no loaded copy in the new calendar, so the changes go to its server copy.
				var eventId = eventItem.id
				var hasChanges = Object.keys(args).length > 0 || guestEdit
				afterMove(eventId, function(model, calendarId, done) {
					if (hasChanges) {
						model.updateEventFromServer(calendarId, eventId, buildArgs, done, options)
					} else {
						done()
					}
				})
			} else if (becomesRecurring || guestsChanged) {
				eventModel.updateEventFromServer(eventItem.calendarId, eventItem.id, buildArgs, refetch, options)
			} else if (Object.keys(args).length) {
				eventModel.setEventProperties(eventItem.calendarId, eventItem.id, args, options)
			}
		}
		closeRequested()
	}

	// Change the whole series of an occurrence: text fields as typed, times moved by as much as
	// this occurrence moved, and the repeat rule.
	function saveSeries(summary) {
		var item = eventItem
		var args = changedArgs(item, summary)
		var options = { params: requestParams(args) }
		var start = startObj()
		var end = endObj()
		var timeChanged = timesChanged(item)
		var occurrenceStart = new Date(item.startDateTime)
		var rule = repeatRule()
		var ruleChanged = repeatChanged
		// A series without a zone of its own gets the editor's (as withTimeZone does).
		var seriesZone = timeZone || calendarTimeZone()
		var guestEdit = guestsChanged
		var initial = initialGuests
		var edited = guests

		var buildArgs = function(series) {
			var seriesArgs = {}
			for (var key in args) {
				seriesArgs[key] = args[key]
			}
			if (timeChanged) {
				var times = SeriesEdit.shiftedTimes(series, occurrenceStart, start, end, seriesZone)
				seriesArgs.start = times.start
				seriesArgs.end = times.end
			}
			if (ruleChanged) {
				seriesArgs.recurrence = Recurrence.withRule(series.recurrence, rule)
			}
			if (guestEdit) {
				seriesArgs.attendees = Guests.applyChanges(series.attendees, initial, edited)
			}
			return seriesArgs
		}
		// Moved to another calendar: the whole series moves, then gets the changes there.
		var seriesId = item.recurringEventId
		afterMove(seriesId, function(model, calendarId, done) {
			model.updateEventFromServer(calendarId, seriesId, buildArgs, done, options)
		})
	}

	Keys.onEscapePressed: closeRequested()

	// The form from an event: the event being edited, or (asCopy) the one being duplicated, as a new
	// event: same fields, color, guests (invited again) and repeat; a new Google Meet if it had one.
	function fillFrom(item, asCopy) {
		titleField.text = item.summary || ""
		locationField.text = item.location || ""
		descriptionField.text = item.description || ""
		if (asCopy) {
			colorId = item.colorId ? String(item.colorId) : ""
			guests = Guests.people(item.attendees).filter(function(guest) {
				return !guest.self
			}).map(function(guest) {
				return guest.displayName ? { email: guest.email, displayName: guest.displayName } : { email: guest.email }
			})
			if (item.hangoutLink || item.conferenceData) {
				conferenceAction = 'add'
			}
		} else {
			initialColorId = item.colorId ? String(item.colorId) : ""
			colorId = initialColorId
			initialGuests = Guests.people(item.attendees)
			guests = initialGuests.slice()
		}
		loadTypeOptions(item, asCopy)
		if (!asCopy && item.fromCache && isSpecialType) {
			// The disk cache has no type settings: the server copy's.
			eventModel.fetchEvent(item.calendarId, item.id, function(err, serverEvent) {
				if (!err && serverEvent) {
					loadTypeOptions(serverEvent, false)
				}
			})
		}
		fillReminders(item, asCopy)
		fillAvailability(item, asCopy)
		var allDay = !!(item.start && item.start.date)
		allDayCheckBox.checked = allDay
		timeZone = defaultTimeZone(item)
		if (!asCopy) {
			initialTimeZone = timeZone
		}
		var start = new Date(item.startDateTime)
		var end = new Date(item.endDateTime)
		if (allDay) {
			end.setDate(end.getDate() - 1) // Inclusive last day in the form
			start.setHours(9, 0, 0, 0) // Times used if All day is unchecked
			end.setHours(10, 0, 0, 0)
		} else {
			start = toWall(start)
			end = toWall(end)
		}
		durationSelector.startDateTime = start
		durationSelector.endDateTime = end
		if (asCopy && item.recurrence) {
			setInitialRepeat(Recurrence.ruleOf(item.recurrence), start)
		} else if (item.recurringEventId) {
			seriesLoading = true
			eventModel.fetchEvent(item.calendarId, item.recurringEventId, function(err, series) {
				seriesLoading = false
				if (err || !series) {
					return
				}
				if (!asCopy) {
					seriesEvent = series
				}
				setInitialRepeat(Recurrence.ruleOf(series.recurrence), durationSelector.startDateTime)
			})
		}
	}

	Component.onCompleted: {
		var calendarList = eventModel.getCalendarList().filter(function(c) { return !c.isTasklist })
		// An existing event can only move within its account (populate keeps the writable ones).
		if (eventItem) {
			var prefix = accountPrefix
			calendarList = calendarList.filter(function(c) {
				return c.id === eventItem.calendarId || (prefix !== '' && String(c.id).indexOf(prefix) === 0)
			})
		}
		var initialCalendarId = eventItem ? eventItem.calendarId : plasmoid.configuration.agendaNewEventLastCalendarId
		// Duplicate: on the same calendar when it's one we can write to.
		if (templateEvent && calendarList.some(function(c) { return c.id === templateEvent.calendarId })) {
			initialCalendarId = templateEvent.calendarId
		}
		calendarSelector.populate(calendarList, initialCalendarId)

		if (eventItem) {
			fillFrom(eventItem, false)
		} else if (templateEvent) {
			fillFrom(templateEvent, true)
		} else {
			// Given start, or the next full hour on the chosen day. 1 hour long.
			var now = new Date()
			var s = initialStart
				? new Date(initialStart)
				: new Date(initialDate.getFullYear(), initialDate.getMonth(), initialDate.getDate(), now.getHours() + 1, 0)
			timeZone = defaultTimeZone(null)
			durationSelector.startDateTime = toWall(s)
			durationSelector.endDateTime = toWall(new Date(s.getTime() + 60 * 60 * 1000))
			titleField.text = initialTitle
		}
		initialized = true
		knownGuests = eventModel.knownGuestEmails ? eventModel.knownGuestEmails() : []
		titleField.forceActiveFocus()
		if (templateEvent) {
			titleField.selectAll()
		}
	}

	ColumnLayout {
		anchors.fill: parent
		spacing: 0

		// Cancel on the left, title centered, Save on the right.
		Item {
			id: actionsRow
			Layout.fillWidth: true
			Layout.margins: Kirigami.Units.smallSpacing
			implicitHeight: Math.max(cancelButton.implicitHeight, saveButton.implicitHeight, formTitle.implicitHeight)

			PlasmaComponents3.ToolButton {
				id: cancelButton
				anchors.left: parent.left
				anchors.verticalCenter: parent.verticalCenter
				icon.name: "go-previous"
				text: i18n("Cancel")
				onClicked: form.closeRequested()
			}
			Kirigami.Heading {
				id: formTitle
				anchors.centerIn: parent
				width: Math.min(implicitWidth, parent.width - Math.max(cancelButton.width, saveButton.width) * 2 - Kirigami.Units.largeSpacing * 2)
				horizontalAlignment: Text.AlignHCenter
				level: 3
				elide: Text.ElideRight
				text: form.isNew ? i18n("New Event") : i18n("Edit Event")
			}
			PlasmaComponents3.Button {
				id: saveButton
				anchors.right: parent.right
				anchors.verticalCenter: parent.verticalCenter
				icon.name: "document-save"
				text: i18n("Save")
				enabled: titleField.text.trim().length > 0 && !!calendarSelector.selectedCalendarId
				onClicked: form.save()
			}
		}

		Kirigami.Separator {
			Layout.fillWidth: true
		}

		// Asked on Save when guests would get emails.
		Kirigami.InlineMessage {
			id: guestNoticeMessage
			Layout.fillWidth: true
			Layout.margins: Kirigami.Units.smallSpacing
			visible: false // Shown by form.guestNotice (the close button hides it)
			type: Kirigami.MessageType.Information
			showCloseButton: true
			text: form.guestNotice === 'invite'
				? i18n("Send invitation emails to the guests?")
				: i18n("Send update emails to the guests?")
			actions: [
				Kirigami.Action {
					icon.name: "mail-send"
					text: form.guestNotice === 'invite' ? i18n("Send invitations") : i18nc("send update emails to guests", "Send")
					onTriggered: form.answerGuestNotice('all')
				},
				Kirigami.Action {
					text: i18nc("don't send emails to guests", "Don't send")
					onTriggered: form.answerGuestNotice('none')
				}
			]
			onVisibleChanged: {
				if (!visible) {
					form.guestNotice = ""
				}
			}
		}

		PlasmaComponents3.ScrollView {
			id: scrollView
			Layout.fillWidth: true
			Layout.fillHeight: true
			contentWidth: availableWidth
			QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

			ColumnLayout {
				id: fieldsColumn
				width: scrollView.availableWidth - Kirigami.Units.largeSpacing * 2
				x: Kirigami.Units.largeSpacing
				y: Kirigami.Units.largeSpacing
				spacing: Kirigami.Units.largeSpacing

				// Recurring event: change this occurrence or the whole series.
				RowLayout {
					visible: form.isOccurrence
					Layout.fillWidth: true
					PlasmaComponents3.Label {
						text: i18n("Change:")
					}
					FormComboBox {
						id: scopeCombo
						Layout.fillWidth: true
						model: [i18n("This event"), i18n("All events in the series")]
					}
				}

				PlasmaComponents3.TextField {
					id: titleField
					Layout.fillWidth: true
					placeholderText: i18n("Title")
					font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.3
					onAccepted: form.save()
				}

				CalendarSelector {
					id: calendarSelector
					Layout.fillWidth: true
					// Existing events: move to another calendar of the same account (see canMove).
					enabled: form.isNew || form.canMove
				}

				// Event type (new events on a primary Google calendar).
				RowLayout {
					visible: form.canSetType
					Layout.fillWidth: true
					RowIcon {
						source: form.effectiveType === 'outOfOffice' ? "user-away" : (form.effectiveType === 'focusTime' ? "audio-headphones" : "view-calendar-day")
					}
					KeyComboBox {
						id: eventTypeCombo
						Layout.fillWidth: true
						model: [
							{ key: 'default', text: i18nc("event type", "Event") },
							{ key: 'outOfOffice', text: i18nc("event type", "Out of office") },
							{ key: 'focusTime', text: i18nc("event type", "Focus time") },
						]
						currentKey: form.eventType
						onPicked: function(key) { form.setEventType(key) }
						Accessible.name: i18n("Event type")
					}
				}
				ColumnLayout {
					visible: form.isSpecialType
					// Existing event from the disk cache: until its settings are loaded.
					enabled: form.isNew || form.initialTypeProperties !== ""
					Layout.fillWidth: true
					Layout.leftMargin: form.indent
					spacing: Kirigami.Units.smallSpacing
					KeyComboBox {
						id: declineCombo
						Layout.fillWidth: true
						model: [
							{ key: 'declineNone', text: i18n("Don't decline invitations") },
							{ key: 'declineOnlyNewConflictingInvitations', text: i18n("Decline new invitations in this time") },
							{ key: 'declineAllConflictingInvitations', text: i18n("Decline new and existing invitations in this time") },
						]
						currentKey: form.autoDeclineMode
						onPicked: function(key) { form.autoDeclineMode = key }
						Accessible.name: i18n("Automatically decline")
					}
					PlasmaComponents3.TextField {
						id: declineMessageField
						visible: form.autoDeclineMode !== 'declineNone'
						Layout.fillWidth: true
						placeholderText: i18n("Message for declined invitations")
						text: form.declineMessage
						onTextEdited: form.declineMessage = text
					}
					KeyComboBox {
						visible: form.effectiveType === 'focusTime'
						Layout.fillWidth: true
						model: [
							{ key: 'doNotDisturb', text: i18nc("Google Chat status during focus time", "Do not disturb") },
							{ key: 'available', text: i18nc("Google Chat status during focus time", "Available") },
						]
						currentKey: form.chatStatus === 'available' ? 'available' : 'doNotDisturb'
						displayText: i18nc("%1 = Do not disturb or Available", "Chat status: %1", currentText)
						onPicked: function(key) { form.chatStatus = key }
						Accessible.name: i18n("Chat status")
					}
				}

				// Event color (Google): the calendar's color or one of Google's 11 event colors.
				Flow {
					id: colorRow
					visible: form.supportsRecurrence
					Layout.fillWidth: true
					spacing: Kirigami.Units.smallSpacing
					readonly property int swatchSize: Math.round(Kirigami.Units.gridUnit * 1.2)

					Repeater {
						model: [''].concat(GooglePalette.eventPalette.map(function(entry) { return entry.id }))
						QQC2.AbstractButton {
							id: swatch
							readonly property string colorId: modelData
							readonly property bool selected: form.colorId === colorId
							readonly property string name: colorId ? (form.colorNames[colorId] || colorId) : i18n("Calendar color")
							width: colorRow.swatchSize + Kirigami.Units.smallSpacing * 2
							height: width
							hoverEnabled: true
							focusPolicy: Qt.TabFocus
							Accessible.name: name
							Accessible.role: Accessible.RadioButton
							Accessible.checked: selected
							onClicked: form.colorId = colorId
							background: null
							contentItem: Item {
								// Selection ring
								Rectangle {
									anchors.fill: parent
									radius: width / 2
									color: "transparent"
									border.width: 2
									border.color: Kirigami.Theme.textColor
									visible: swatch.selected
								}
								Rectangle {
									id: swatchFill
									anchors.centerIn: parent
									width: colorRow.swatchSize
									height: width
									radius: width / 2
									color: form.swatchColor(swatch.colorId)
									border.width: swatch.hovered || swatch.visualFocus ? 2 : 1
									border.color: swatch.hovered || swatch.visualFocus ? Kirigami.Theme.highlightColor : ColorUtil.setAlpha(Kirigami.Theme.textColor, 0.2)
								}
								// The calendar color: marked, so it reads as "no color of its own".
								Kirigami.Icon {
									visible: !swatch.colorId
									anchors.centerIn: parent
									width: Kirigami.Units.iconSizes.small
									height: width
									source: "view-calendar"
									color: Shared.contrastTextColor(swatchFill.color)
									isMask: true
								}
							}
							PlasmaComponents3.ToolTip.text: name
							PlasmaComponents3.ToolTip.visible: hovered
							PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
						}
					}
				}

				PlasmaComponents3.CheckBox {
					id: allDayCheckBox
					visible: !form.isSpecialType
					text: i18n("All day")
				}

				DurationSelector {
					id: durationSelector
					Layout.fillWidth: true
					showTime: !allDayCheckBox.checked
				}

				// Time zone of the times above (Google, timed events).
				ColumnLayout {
					id: timeZoneSection
					visible: form.supportsTimeZone && !allDayCheckBox.checked
					Layout.fillWidth: true
					spacing: Kirigami.Units.smallSpacing
					property bool expanded: false

					RowLayout {
						Layout.fillWidth: true
						RowIcon {
							source: "preferences-system-time"
						}
						PlasmaComponents3.ToolButton {
							id: timeZoneButton
							Layout.fillWidth: true
							Layout.minimumWidth: 0
							checked: timeZoneSection.expanded
							onClicked: {
								timeZoneSection.expanded = !timeZoneSection.expanded
								if (timeZoneSection.expanded) {
									timeZoneSearch.text = ""
									timeZoneSearch.forceActiveFocus()
								}
							}
							contentItem: RowLayout {
								PlasmaComponents3.Label {
									Layout.fillWidth: true
									elide: Text.ElideRight
									text: {
										var zone = form.timeZone || i18n("Local time")
										var abbr = TimeZone.abbreviation(form.timeZone, form.startInstant().getTime())
										return i18nc("%1 = time zone id, eg: Europe/Warsaw", "Time zone: %1", zone.replace(/_/g, ' ')) + (abbr ? " (" + abbr + ")" : "")
									}
								}
								PlasmaComponents3.Label {
									visible: form.localTimesText !== ""
									opacity: 0.7
									text: form.localTimesText
								}
							}
							Accessible.name: i18n("Time zone")
						}
					}
					PlasmaComponents3.TextField {
						id: timeZoneSearch
						visible: timeZoneSection.expanded
						Layout.fillWidth: true
						Layout.leftMargin: form.indent
						placeholderText: i18n("Search time zones")
						Keys.onUpPressed: timeZoneList.moveUp()
						Keys.onDownPressed: timeZoneList.moveDown()
						Keys.onEscapePressed: timeZoneSection.expanded = false
						onAccepted: timeZoneList.pickCurrent()
					}
					TimeZoneList {
						id: timeZoneList
						visible: timeZoneSection.expanded
						Layout.fillWidth: true
						Layout.leftMargin: form.indent
						Layout.preferredHeight: Kirigami.Units.gridUnit * 9
						query: timeZoneSearch.text
						currentZone: form.timeZone
						referenceTime: durationSelector.startDateTime.getTime()
						onPicked: function(zone) {
							form.setTimeZone(zone)
							timeZoneSection.expanded = false
						}
					}
				}

				RowLayout {
					visible: form.supportsRecurrence
					Layout.fillWidth: true
					RowIcon {
						source: "view-refresh"
					}
					KeyComboBox {
						id: repeatCombo
						Layout.fillWidth: true
						enabled: form.canEditRepeat
						model: {
							var start = durationSelector.startDateTime
							var list = [
								{ key: 'none', text: i18n("Does not repeat") },
								{ key: 'daily', text: i18n("Daily") },
								{ key: 'weekdays', text: i18n("Every weekday (Monday to Friday)") },
								{ key: 'weekly', text: i18nc("%1 = day name", "Weekly on %1", Qt.locale().dayName(start.getDay())) },
								{ key: 'monthly', text: i18nc("%1 = day of the month", "Monthly on day %1", start.getDate()) },
								{ key: 'yearly', text: i18nc("%1 = date, eg: 16 October", "Yearly on %1", Qt.formatDate(start, "d MMMM")) },
							]
							if (form.initialRepeatKey === 'original') {
								list.push({ key: 'original', text: i18n("Custom (as set in Google Calendar)") })
							}
							list.push({ key: 'custom', text: i18n("Custom…") })
							return list
						}
						currentKey: form.repeatKey
						onPicked: function(key) {
							if (key === 'custom' && form.repeatKey !== 'custom') {
								// Start from what was picked before, eg: Weekly on Thursday.
								form.setCustom(Recurrence.customOf(form.repeatRule(), durationSelector.startDateTime))
							}
							form.repeatKey = key
						}
						displayText: form.seriesLoading ? i18n("Loading…") : currentText
					}
				}

				// Custom repeat: every N days / weeks / months / years, and the days of the week.
				ColumnLayout {
					visible: form.supportsRecurrence && form.repeatKey === 'custom'
					enabled: form.canEditRepeat
					Layout.fillWidth: true
					Layout.leftMargin: form.indent
					spacing: Kirigami.Units.smallSpacing

					RowLayout {
						Layout.fillWidth: true
						PlasmaComponents3.Label {
							text: i18nc("Repeat every [2] [weeks]", "Every")
						}
						PlasmaComponents3.SpinBox {
							from: 1
							to: 99
							value: form.customInterval
							onValueModified: form.customInterval = value
						}
						KeyComboBox {
							id: freqCombo
							Layout.fillWidth: true
							model: [
								{ key: 'DAILY', text: i18ncp("Repeat every N", "day", "days", form.customInterval) },
								{ key: 'WEEKLY', text: i18ncp("Repeat every N", "week", "weeks", form.customInterval) },
								{ key: 'MONTHLY', text: i18ncp("Repeat every N", "month", "months", form.customInterval) },
								{ key: 'YEARLY', text: i18ncp("Repeat every N", "year", "years", form.customInterval) },
							]
							currentKey: form.customFreq
							onPicked: function(key) { form.customFreq = key }
						}
					}

					// The days in the order of the week view's first day setting.
					RowLayout {
						visible: form.customFreq === 'WEEKLY'
						Layout.fillWidth: true
						spacing: 0
						Repeater {
							model: 7
							PlasmaComponents3.ToolButton {
								readonly property int firstDay: {
									var setting = plasmoid.configuration.firstDayOfWeek
									return setting >= 0 ? setting : Qt.locale().firstDayOfWeek % 7
								}
								readonly property int dayIndex: (firstDay + index) % 7
								readonly property string code: Recurrence.dayCodes[dayIndex]
								Layout.fillWidth: true
								text: Qt.locale().dayName(dayIndex, Locale.NarrowFormat)
								checked: form.customDays.indexOf(code) >= 0
								onClicked: form.toggleCustomDay(code)
								PlasmaComponents3.ToolTip.text: Qt.locale().dayName(dayIndex)
								PlasmaComponents3.ToolTip.visible: hovered
								PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
							}
						}
					}
				}

				// When a repeat ends.
				RowLayout {
					visible: form.supportsRecurrence && form.repeatKey !== 'none'
					enabled: form.canEditRepeat
					Layout.fillWidth: true
					Layout.leftMargin: form.indent
					PlasmaComponents3.Label {
						text: i18nc("Repeat ends: never / on date / after N times", "Ends:")
					}
					KeyComboBox {
						id: endCombo
						Layout.fillWidth: form.endType === 'never'
						model: [
							{ key: 'never', text: i18nc("Repeat ends", "Never") },
							{ key: 'until', text: i18nc("Repeat ends on [date]", "On") },
							{ key: 'count', text: i18nc("Repeat ends after [N] times", "After") },
						]
						currentKey: form.endType
						onPicked: function(key) {
							if (key === 'until' && !form.endDate) {
								var d = new Date(durationSelector.startDateTime)
								d.setMonth(d.getMonth() + 1)
								form.endDate = d
							}
							form.endType = key
						}
					}
					DateSelector {
						visible: form.endType === 'until'
						Layout.fillWidth: true
						dateFormat: i18nc("event editor date format", "d MMM, yyyy")
						dateTime: form.endDate || durationSelector.startDateTime
						onDateTimeShifted: function(oldDateTime, deltaDateTime, newDateTime) {
							form.endDate = newDateTime
						}
					}
					PlasmaComponents3.SpinBox {
						visible: form.endType === 'count'
						from: 1
						to: 999
						value: form.endCount
						onValueModified: form.endCount = value
					}
					PlasmaComponents3.Label {
						visible: form.endType === 'count'
						Layout.fillWidth: true
						text: i18ncp("Repeat ends after N", "time", "times", form.endCount)
					}
				}

				PlasmaComponents3.TextField {
					id: locationField
					visible: !form.isSpecialType
					Layout.fillWidth: true
					placeholderText: i18n("Location")
				}

				// Google Meet: add one, or the event's video call with a remove button.
				RowLayout {
					id: conferenceRow
					visible: form.supportsRecurrence && !form.isSpecialType && (form.hadConference || (form.meetAllowed && !form.isInvited))
					Layout.fillWidth: true
					RowIcon {
						source: "camera-web"
					}
					PlasmaComponents3.Button {
						id: addMeetButton
						visible: !form.hadConference && !form.hasConference && form.meetAllowed && !form.isInvited
						text: i18n("Add Google Meet video conferencing")
						onClicked: form.conferenceAction = 'add'
					}
					// Removed, until saved.
					PlasmaComponents3.Label {
						visible: form.hadConference && !form.hasConference
						Layout.fillWidth: true
						wrapMode: Text.Wrap
						opacity: 0.7
						text: i18n("Video conferencing will be removed when you save")
					}
					PlasmaComponents3.ToolButton {
						visible: form.hadConference && !form.hasConference
						icon.name: "edit-undo"
						text: i18n("Undo")
						onClicked: form.conferenceAction = ''
					}
					PlasmaComponents3.Label {
						id: conferenceLabel
						visible: form.hasConference
						Layout.fillWidth: true
						elide: Text.ElideRight
						textFormat: Text.StyledText
						text: {
							if (form.conferenceAction === 'add') {
								return i18n("A Google Meet link will be created when you save")
							}
							var link = form.conferenceLink
							if (!link) {
								return i18n("Video conferencing")
							}
							var shown = link.url.replace(/^https?:\/\//i, '')
							return '<a href="' + Shared.escapeHtml(link.url) + '">' + Shared.escapeHtml(link.label + ': ' + shown) + '</a>'
						}
						onLinkActivated: function(link) { Qt.openUrlExternally(link) }
						HoverHandler {
							cursorShape: conferenceLabel.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
						}
					}
					PlasmaComponents3.ToolButton {
						visible: form.hasConference && !form.isInvited
						icon.name: "edit-delete-remove"
						onClicked: form.conferenceAction = form.hadConference ? 'remove' : ''
						Accessible.name: PlasmaComponents3.ToolTip.text
						PlasmaComponents3.ToolTip.text: i18n("Remove video conferencing")
						PlasmaComponents3.ToolTip.visible: hovered
						PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
					}
				}

				// Show as busy / free, and who sees the details (Google).
				RowLayout {
					visible: form.supportsRecurrence
					Layout.fillWidth: true
					RowIcon {
						source: "view-calendar-day"
					}
					KeyComboBox {
						id: transparencyCombo
						visible: !form.isSpecialType // Always busy
						Layout.fillWidth: true
						model: [
							{ key: 'opaque', text: i18nc("show the event's time as", "Busy") },
							{ key: 'transparent', text: i18nc("show the event's time as", "Free") },
						]
						currentKey: form.transparency === 'transparent' ? 'transparent' : 'opaque'
						displayText: i18nc("%1 = Busy or Free", "Show as: %1", currentText)
						onPicked: function(key) { form.transparency = key }
						Accessible.name: i18n("Show as")
					}
					KeyComboBox {
						id: visibilityCombo
						Layout.fillWidth: true
						model: [
							{ key: 'default', text: i18nc("event visibility", "Calendar default") },
							{ key: 'public', text: i18nc("event visibility", "Public") },
							{ key: 'private', text: i18nc("event visibility", "Private") },
						]
						// 'confidential' is an old name of private.
						currentKey: form.visibility === 'public' ? 'public' : (form.visibility === 'private' || form.visibility === 'confidential' ? 'private' : 'default')
						displayText: i18nc("%1 = Calendar default, Public or Private", "Visibility: %1", currentText)
						onPicked: function(key) {
							// Keep 'confidential' unless another choice than Private is picked.
							if (!(key === 'private' && form.visibility === 'confidential')) {
								form.visibility = key
							}
						}
						Accessible.name: i18n("Visibility")
					}
				}

				// Reminders: the calendar's defaults, or this event's own notification times.
				ColumnLayout {
					visible: form.supportsRecurrence
					Layout.fillWidth: true
					spacing: Kirigami.Units.smallSpacing

					RowLayout {
						Layout.fillWidth: true
						RowIcon {
							source: "notifications"
						}
						PlasmaComponents3.Label {
							text: i18n("Reminders")
						}
						KeyComboBox {
							Layout.fillWidth: true
							model: [
								{ key: 'default', text: i18n("Calendar's default") },
								{ key: 'custom', text: i18n("Set for this event") },
							]
							currentKey: form.remindersCustom ? 'custom' : 'default'
							onPicked: function(key) {
								form.remindersCustom = key === 'custom'
								if (form.remindersCustom && !form.reminderItems.length && !form.reminderOthers.length) {
									form.addReminder()
								}
							}
						}
					}
					Repeater {
						model: form.remindersCustom ? form.reminderItems : []
						RowLayout {
							Layout.fillWidth: true
							Layout.leftMargin: form.indent
							readonly property int itemIndex: index
							PlasmaComponents3.SpinBox {
								from: 1
								to: 999
								value: modelData.value
								onValueModified: form.setReminder(parent.itemIndex, value, modelData.unit)
							}
							KeyComboBox {
								Layout.fillWidth: true
								model: [
									{ key: 'minutes', text: i18ncp("reminder: N … before the event", "minute before", "minutes before", modelData.value) },
									{ key: 'hours', text: i18ncp("reminder: N … before the event", "hour before", "hours before", modelData.value) },
									{ key: 'days', text: i18ncp("reminder: N … before the event", "day before", "days before", modelData.value) },
									{ key: 'weeks', text: i18ncp("reminder: N … before the event", "week before", "weeks before", modelData.value) },
								]
								currentKey: modelData.unit
								onPicked: function(key) { form.setReminder(parent.itemIndex, modelData.value, key) }
							}
							PlasmaComponents3.ToolButton {
								icon.name: "edit-delete-remove"
								onClicked: form.removeReminder(parent.itemIndex)
								Accessible.name: PlasmaComponents3.ToolTip.text
								PlasmaComponents3.ToolTip.text: i18n("Remove reminder")
								PlasmaComponents3.ToolTip.visible: hovered
								PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
							}
						}
					}
					PlasmaComponents3.Label {
						visible: form.remindersCustom && form.reminderItems.length === 0
						Layout.leftMargin: form.indent
						text: i18n("No notification reminders")
						opacity: 0.7
					}
					PlasmaComponents3.ToolButton {
						visible: form.remindersCustom
						enabled: form.canAddReminder
						Layout.leftMargin: Kirigami.Units.iconSizes.small
						icon.name: "list-add"
						text: i18n("Add Reminder")
						onClicked: form.addReminder()
					}
				}

				// Guests: add by email (with suggestions), remove with the chips' close button.
				ColumnLayout {
					id: guestsSection
					visible: form.supportsRecurrence && !form.isSpecialType
					Layout.fillWidth: true
					spacing: Kirigami.Units.smallSpacing

					RowLayout {
						Layout.fillWidth: true
						RowIcon {
							source: "group"
						}
						PlasmaComponents3.Label {
							text: i18n("Guests")
						}
						PlasmaComponents3.Label {
							visible: !form.canEditGuests
							Layout.fillWidth: true
							elide: Text.ElideRight
							opacity: 0.7
							text: i18n("Only the organizer can change the guest list")
						}
					}

					RowLayout {
						visible: form.canEditGuests
						Layout.fillWidth: true
						Layout.leftMargin: form.indent
						PlasmaComponents3.TextField {
							id: guestField
							Layout.fillWidth: true
							placeholderText: i18n("Add guests by email")
							inputMethodHints: Qt.ImhEmailCharactersOnly | Qt.ImhNoAutoUppercase
							onAccepted: form.addGuestFromField()
							onTextChanged: form.guestError = ""
						}
						PlasmaComponents3.Button {
							text: i18nc("add a guest", "Add")
							icon.name: "list-add-user"
							enabled: guestField.text.trim().length > 0
							onClicked: form.addGuestFromField()
						}
					}

					// Suggestions from the loaded events' guests.
					ColumnLayout {
						visible: form.canEditGuests && guestField.activeFocus && form.guestSuggestions.length > 0
						Layout.fillWidth: true
						Layout.leftMargin: form.indent
						spacing: 0
						Repeater {
							model: form.guestSuggestions
							PlasmaComponents3.ItemDelegate {
								Layout.fillWidth: true
								focusPolicy: Qt.NoFocus // Keep the field focused (and this list shown)
								icon.name: "user"
								text: modelData.name ? i18nc("guest suggestion: %1 = name, %2 = email", "%1 <%2>", modelData.name, modelData.email) : modelData.email
								onClicked: form.addGuest(modelData.email)
							}
						}
					}

					PlasmaComponents3.Label {
						visible: form.guestError !== ""
						Layout.fillWidth: true
						Layout.leftMargin: form.indent
						wrapMode: Text.Wrap
						color: Kirigami.Theme.negativeTextColor
						text: form.guestError
					}

					PlasmaComponents3.Button {
						visible: form.canFindTime
						Layout.leftMargin: form.indent
						icon.name: "view-calendar-day"
						text: i18n("Find a Time")
						onClicked: form.openFindTime()
					}

					Flow {
						visible: form.guests.length > 0
						Layout.fillWidth: true
						Layout.leftMargin: form.indent
						spacing: Kirigami.Units.smallSpacing
						Repeater {
							model: form.guests
							Kirigami.Chip {
								readonly property string name: modelData.displayName || modelData.email
								text: modelData.self ? name + " (" + i18nc("the current user in a guest list", "you") + ")" : name
								icon.name: Guests.responseIcon(modelData.responseStatus)
								checkable: false
								closable: form.canEditGuests && !modelData.self
								onRemoved: form.removeGuest(modelData.email)
								PlasmaComponents3.ToolTip.text: modelData.email
								PlasmaComponents3.ToolTip.visible: hovered && modelData.email !== text
								PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
							}
						}
					}
				}

				PlasmaComponents3.TextArea {
					id: descriptionField
					Layout.fillWidth: true
					Layout.preferredHeight: Kirigami.Units.gridUnit * 5
					placeholderText: i18n("Description")
					wrapMode: TextEdit.Wrap
				}
			}
		}
	}

	// Find a time: a card over the form.
	Loader {
		anchors.fill: parent
		active: form.findTimeOpen
		z: 10
		sourceComponent: Item {
			Rectangle {
				anchors.fill: parent
				radius: form.radius
				color: Kirigami.Theme.backgroundColor
				opacity: 0.85
			}
			MouseArea { // Around the card (the card keeps its own clicks)
				anchors.fill: parent
				onClicked: form.findTimeOpen = false
			}
			FindTimeView {
				anchors.centerIn: parent
				width: parent.width - Kirigami.Units.gridUnit
				height: Math.min(implicitHeight, parent.height - Kirigami.Units.gridUnit)
				calendarId: calendarSelector.selectedCalendarId || ""
				people: form.findTimePeople()
				timeZone: TimeZone.knows(form.timeZone) ? form.timeZone : ""
				day: durationSelector.startDateTime // The wall date in the editor's zone
				duration: form.endInstant().getTime() - form.startInstant().getTime()
				selectedStart: form.startInstant().getTime()
				onSlotPicked: function(start) { form.pickSlot(start) }
				onCloseRequested: form.findTimeOpen = false
			}
		}
	}
}
