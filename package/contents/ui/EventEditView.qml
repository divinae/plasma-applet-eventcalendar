import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "Recurrence.js" as Recurrence
import "Shared.js" as Shared
import "lib/ColorUtil.js" as ColorUtil

// Form to create a new event (eventItem == null) or edit an existing one.
Rectangle {
	id: form

	property var eventItem: null
	property date initialDate: new Date() // New events: day to create on
	property var initialStart: null // New events: exact start time (eg: clicked week view slot)
	readonly property bool isNew: !eventItem
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
	property string repeatKey: "none"
	readonly property bool supportsRecurrence: !!calendarSelector.selectedCalendarId
		&& eventModel.supportsRecurrence(calendarSelector.selectedCalendarId)
	readonly property bool canEditRepeat: supportsRecurrence && !seriesLoading && (!isOccurrence || editSeries)

	function repeatRule() {
		if (repeatKey === 'custom') {
			return originalRule
		}
		return Recurrence.presetRule(repeatKey, durationSelector.startDateTime)
	}
	function setInitialRepeat(rule, start) {
		originalRule = rule
		var key = Recurrence.matchPreset(rule, start) || 'custom'
		initialRepeatKey = key
		// The rule a preset would have at the original date: moving the event to another weekday
		// (weekly) or day (monthly) changes it, and the series' rule follows.
		initialRepeatRule = key === 'custom' ? rule : Recurrence.presetRule(key, start)
		repeatKey = key
	}
	readonly property bool repeatChanged: repeatKey !== initialRepeatKey || repeatRule() !== initialRepeatRule
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
		if (obj.dateTime) {
			obj.timeZone = calendarTimeZone()
		}
		return obj
	}
	function refetch() {
		logic.update()
	}

	color: Kirigami.Theme.backgroundColor
	radius: Kirigami.Units.cornerRadius * 2
	border.width: 1
	border.color: ColorUtil.setAlpha(Kirigami.Theme.textColor, 0.15)
	implicitHeight: actionsRow.implicitHeight + Kirigami.Units.smallSpacing * 2 + fieldsColumn.implicitHeight + Kirigami.Units.largeSpacing * 2


	// Google start / end objects. All-day events end at midnight the next day.
	function startObj() {
		if (!allDayCheckBox.checked) {
			return { dateTime: Shared.dateTimeString(durationSelector.startDateTime) }
		}
		return { date: Shared.localeDateString(durationSelector.startDateTime) }
	}
	function endObj() {
		if (!allDayCheckBox.checked) {
			return { dateTime: Shared.dateTimeString(durationSelector.endDateTime) }
		}
		var dayAfter = new Date(durationSelector.endDateTime)
		dayAfter.setDate(dayAfter.getDate() + 1)
		return { date: Shared.localeDateString(dayAfter) }
	}
	function dateObjChanged(oldObj, newObj) {
		oldObj = oldObj || {}
		if (newObj.date) {
			return oldObj.date !== newObj.date
		}
		// Compare instants: Google returns dateTime with an offset, we send UTC.
		return !oldObj.dateTime || new Date(oldObj.dateTime).getTime() !== new Date(newObj.dateTime).getTime()
	}

	function save() {
		var summary = titleField.text.trim()
		if (!summary) {
			titleField.forceActiveFocus()
			return
		}
		if (isNew) {
			var data = {
				summary: summary,
				start: startObj(),
				end: endObj(),
			}
			if (locationField.text) {
				data.location = locationField.text
			}
			if (descriptionField.text) {
				data.description = descriptionField.text
			}
			var newRule = supportsRecurrence ? repeatRule() : ''
			if (newRule) {
				data.recurrence = [newRule]
				withTimeZone(data.start)
				withTimeZone(data.end)
			}
			// A new recurring event: its occurrences come from a refetch.
			eventModel.createEventFromData(calendarSelector.selectedCalendarId, data, newRule ? refetch : null)
		} else if (editSeries) {
			saveSeries(summary)
		} else {
			var args = {}
			if (Shared.hasChanged(eventItem.summary, summary)) {
				args.summary = summary
			}
			if (Shared.hasChanged(eventItem.location, locationField.text)) {
				args.location = locationField.text
			}
			if (Shared.hasChanged(eventItem.description, descriptionField.text)) {
				args.description = descriptionField.text
			}
			var start = startObj()
			var end = endObj()
			var wasAllDay = !!(eventItem.start && eventItem.start.date)
			if (wasAllDay !== allDayCheckBox.checked || dateObjChanged(eventItem.start, start) || dateObjChanged(eventItem.end, end)) {
				// The update replaces start / end as a whole, so switching all-day <-> timed is clean.
				args.start = start
				args.end = end
			}
			var rule = repeatRule()
			if (!isOccurrence && supportsRecurrence && rule && repeatChanged) {
				// A single event becomes recurring.
				args.recurrence = [rule]
				args.start = withTimeZone(start)
				args.end = withTimeZone(end)
				eventModel.updateEventFromServer(eventItem.calendarId, eventItem.id, function() { return args }, refetch)
			} else if (Object.keys(args).length) {
				eventModel.setEventProperties(eventItem.calendarId, eventItem.id, args)
			}
		}
		closeRequested()
	}

	// Change the whole series of an occurrence: text fields as typed, times moved by as much as
	// this occurrence moved, and the repeat rule.
	function saveSeries(summary) {
		var item = eventItem
		var args = {}
		if (Shared.hasChanged(item.summary, summary)) {
			args.summary = summary
		}
		if (Shared.hasChanged(item.location, locationField.text)) {
			args.location = locationField.text
		}
		if (Shared.hasChanged(item.description, descriptionField.text)) {
			args.description = descriptionField.text
		}
		var start = startObj()
		var end = endObj()
		var allDay = allDayCheckBox.checked
		var wasAllDay = !!(item.start && item.start.date)
		var timeChanged = wasAllDay !== allDay || dateObjChanged(item.start, start) || dateObjChanged(item.end, end)
		function instant(obj) {
			if (obj.dateTime) {
				return new Date(obj.dateTime).getTime()
			}
			var d = obj.date.split('-')
			return new Date(+d[0], +d[1] - 1, +d[2]).getTime()
		}
		// Days the occurrence moved, and its new time of day: applied to the series start in local
		// time, so a daylight saving change between the two dates doesn't shift the hour.
		var newStart = new Date(instant(start))
		var dayShift = Math.round((Shared.startOfDay(newStart) - Shared.startOfDay(new Date(item.startDateTime))) / 86400000)
		var duration = instant(end) - instant(start)
		var rule = repeatRule()
		var ruleChanged = repeatChanged
		var timeZone = calendarTimeZone()

		eventModel.updateEventFromServer(item.calendarId, item.recurringEventId, function(series) {
			var seriesArgs = {}
			for (var key in args) {
				seriesArgs[key] = args[key]
			}
			if (timeChanged) {
				var seriesStart = new Date(instant(series.start))
				seriesStart.setDate(seriesStart.getDate() + dayShift)
				seriesStart.setHours(newStart.getHours(), newStart.getMinutes(), 0, 0)
				var seriesEnd = new Date(seriesStart.getTime() + duration)
				var zone = (series.start && series.start.timeZone) || timeZone
				if (allDay) {
					seriesArgs.start = { date: Shared.localeDateString(seriesStart) }
					seriesArgs.end = { date: Shared.localeDateString(seriesEnd) }
				} else {
					seriesArgs.start = { dateTime: Shared.dateTimeString(seriesStart), timeZone: zone }
					seriesArgs.end = { dateTime: Shared.dateTimeString(seriesEnd), timeZone: zone }
				}
			}
			if (ruleChanged) {
				seriesArgs.recurrence = Recurrence.withRule(series.recurrence, rule)
			}
			return seriesArgs
		}, refetch)
	}

	Keys.onEscapePressed: closeRequested()

	Component.onCompleted: {
		var calendarList = eventModel.getCalendarList().filter(function(c) { return !c.isTasklist })
		var initialCalendarId = eventItem ? eventItem.calendarId : plasmoid.configuration.agendaNewEventLastCalendarId
		calendarSelector.populate(calendarList, initialCalendarId)

		if (eventItem) {
			titleField.text = eventItem.summary || ""
			locationField.text = eventItem.location || ""
			descriptionField.text = eventItem.description || ""
			var allDay = !!(eventItem.start && eventItem.start.date)
			allDayCheckBox.checked = allDay
			var start = new Date(eventItem.startDateTime)
			var end = new Date(eventItem.endDateTime)
			if (allDay) {
				end.setDate(end.getDate() - 1) // Inclusive last day in the form
				start.setHours(9, 0, 0, 0) // Times used if All day is unchecked
				end.setHours(10, 0, 0, 0)
			}
			durationSelector.startDateTime = start
			durationSelector.endDateTime = end
			if (isOccurrence) {
				seriesLoading = true
				eventModel.fetchEvent(eventItem.calendarId, eventItem.recurringEventId, function(err, series) {
					seriesLoading = false
					if (err || !series) {
						return
					}
					seriesEvent = series
					setInitialRepeat(Recurrence.ruleOf(series.recurrence), durationSelector.startDateTime)
				})
			}
		} else {
			// Given start, or the next full hour on the chosen day. 1 hour long.
			var now = new Date()
			var s = initialStart
				? new Date(initialStart)
				: new Date(initialDate.getFullYear(), initialDate.getMonth(), initialDate.getDate(), now.getHours() + 1, 0)
			durationSelector.startDateTime = s
			durationSelector.endDateTime = new Date(s.getTime() + 60 * 60 * 1000)
		}
		titleField.forceActiveFocus()
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
					enabled: form.isNew // Moving events between calendars isn't supported yet.
				}

				PlasmaComponents3.CheckBox {
					id: allDayCheckBox
					text: i18n("All day")
				}

				DurationSelector {
					id: durationSelector
					Layout.fillWidth: true
					showTime: !allDayCheckBox.checked
				}

				RowLayout {
					visible: form.supportsRecurrence
					Layout.fillWidth: true
					Kirigami.Icon {
						source: "view-refresh"
						Layout.preferredWidth: Kirigami.Units.iconSizes.small
						Layout.preferredHeight: Layout.preferredWidth
						opacity: 0.7
					}
					FormComboBox {
						id: repeatCombo
						Layout.fillWidth: true
						enabled: form.canEditRepeat
						textRole: "text"
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
							if (form.initialRepeatKey === 'custom') {
								list.push({ key: 'custom', text: i18n("Custom (as set in Google Calendar)") })
							}
							return list
						}
						function syncIndex() {
							for (var i = 0; i < model.length; i++) {
								if (model[i].key === form.repeatKey) {
									currentIndex = i
									return
								}
							}
						}
						onModelChanged: syncIndex()
						Connections {
							target: form
							function onRepeatKeyChanged() { repeatCombo.syncIndex() }
						}
						onActivated: function(index) { form.repeatKey = model[index].key }
						displayText: form.seriesLoading ? i18n("Loading…") : currentText
					}
				}

				PlasmaComponents3.TextField {
					id: locationField
					Layout.fillWidth: true
					placeholderText: i18n("Location")
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
}
