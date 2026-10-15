import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "Shared.js" as Shared

// Form to create a new event (eventItem == null) or edit an existing one.
Rectangle {
	id: form

	property var eventItem: null
	property date initialDate: new Date() // New events: day to create on
	readonly property bool isNew: !eventItem
	signal closeRequested()

	color: Kirigami.Theme.backgroundColor
	radius: Kirigami.Units.cornerRadius * 2
	border.width: 1
	border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
	implicitHeight: actionsRow.implicitHeight + Kirigami.Units.smallSpacing * 2 + fieldsColumn.implicitHeight + Kirigami.Units.largeSpacing * 2

	function isEmpty(s) {
		return typeof s === "undefined" || s === null || s === ""
	}
	function hasChanged(a, b) {
		return a != b && !(isEmpty(a) && isEmpty(b))
	}

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
			eventModel.createEventFromData(calendarSelector.selectedCalendarId, data)
		} else {
			var args = {}
			if (hasChanged(eventItem.summary, summary)) {
				args.summary = summary
			}
			if (hasChanged(eventItem.location, locationField.text)) {
				args.location = locationField.text
			}
			if (hasChanged(eventItem.description, descriptionField.text)) {
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
			if (Object.keys(args).length) {
				eventModel.setEventProperties(eventItem.calendarId, eventItem.id, args)
			}
		}
		closeRequested()
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
		} else {
			// Next full hour on the chosen day, 1 hour long.
			var now = new Date()
			var s = new Date(initialDate.getFullYear(), initialDate.getMonth(), initialDate.getDate(), now.getHours() + 1, 0)
			durationSelector.startDateTime = s
			durationSelector.endDateTime = new Date(s.getTime() + 60 * 60 * 1000)
		}
		titleField.forceActiveFocus()
	}

	ColumnLayout {
		anchors.fill: parent
		spacing: 0

		RowLayout {
			id: actionsRow
			Layout.fillWidth: true
			Layout.margins: Kirigami.Units.smallSpacing
			PlasmaComponents3.ToolButton {
				icon.name: "go-previous"
				text: i18n("Cancel")
				onClicked: form.closeRequested()
			}
			Kirigami.Heading {
				Layout.fillWidth: true
				Layout.leftMargin: Kirigami.Units.smallSpacing
				level: 3
				elide: Text.ElideRight
				text: form.isNew ? i18n("New Event") : i18n("Edit Event")
			}
			PlasmaComponents3.Button {
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
