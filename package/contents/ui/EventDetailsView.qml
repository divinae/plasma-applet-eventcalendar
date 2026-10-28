import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "Attachments.js" as Attachments
import "EventTypes.js" as EventTypes
import "LocaleFuncs.js" as LocaleFuncs
import "MeetingLink.js" as MeetingLink
import "Responses.js" as Responses
import "Guests.js" as Guests
import "Shared.js" as Shared
import "Tasks.js" as Tasks
import "TimeZone.js" as TimeZone
import "lib/ColorUtil.js" as ColorUtil
import "code/GooglePalette.js" as GooglePalette

// Event details shown inside the popup, like mobile calendar apps.
Rectangle {
	id: details

	property var eventItem: null
	signal closeRequested()
	signal editRequested()
	signal duplicateRequested()

	color: Kirigami.Theme.backgroundColor
	radius: Kirigami.Units.cornerRadius * 2
	border.width: 1
	border.color: ColorUtil.setAlpha(Kirigami.Theme.textColor, 0.15)
	// Content height, so the card can be sized to fit (it scrolls when taller than the popup).
	implicitHeight: actionsRow.implicitHeight + Kirigami.Units.smallSpacing * 2 + contentColumn.implicitHeight + Kirigami.Units.largeSpacing

	readonly property var meetingLink: eventItem ? MeetingLink.find(eventItem) : null
	readonly property var calendar: eventItem && typeof eventModel !== "undefined" ? eventModel.getCalendar(eventItem.calendarId) : null
	readonly property color eventColor: eventItem && eventItem.backgroundColor ? eventItem.backgroundColor : Kirigami.Theme.highlightColor
	readonly property bool isAllDay: !!(eventItem && eventItem.start && eventItem.start.date)
	readonly property var allAttendees: eventItem ? Shared.toArray(eventItem.attendees) : []
	// Rooms and other resources are listed as attendees by Google; show them as rooms, not people.
	readonly property var rooms: allAttendees.filter(function(a) { return !!a.resource })
	readonly property var attendees: {
		var order = { accepted: 2, tentative: 3, needsAction: 4, declined: 5 }
		function rank(a) {
			return a.organizer ? 0 : a.self ? 1 : (order[a.responseStatus] || 4)
		}
		return allAttendees.filter(function(a) { return !a.resource }).sort(function(a, b) {
			return rank(a) - rank(b)
		})
	}
	readonly property var attachments: Attachments.list(eventItem)
	readonly property bool isOutOfOffice: EventTypes.isOutOfOffice(eventItem)
	readonly property bool isFocusTime: EventTypes.isFocusTime(eventItem)
	// "Email Guests…": everyone invited except you and rooms.
	readonly property string mailtoUrl: Guests.eventMailtoUrl(eventItem)
	readonly property int collapsedGuestCount: 5
	property bool showAllGuests: false
	property bool confirmingDelete: false
	readonly property bool isRecurring: !!(eventItem && eventItem.recurringEventId)

	//--- Tasks: done / not done, the due day, the list and the notes (no time, guests or place).
	readonly property bool isTask: Tasks.isTask(eventItem)
	readonly property bool isDone: isTask && Tasks.isDone(eventItem)
	readonly property bool isOverdue: isTask && Tasks.isOverdue(eventItem, timeModel.currentTime)
	// Tasks: TickTick's checklist ({ id, title, done }), Google's subtasks (the list's tasks with
	// this one as their parent, made again when the list changes).
	readonly property var checklist: isTask ? Tasks.cleanSubtasks(eventItem.subtasks) : []
	property int listRevision: 0
	readonly property var childTasks: {
		listRevision // Depends on it
		if (!isTask || !eventItem.id || typeof eventModel === "undefined" || !eventModel) {
			return []
		}
		var calendar = eventModel.loadedCalendar(eventItem.calendarId)
		var items = calendar && calendar.items ? calendar.items : []
		return items.filter(function(item) {
			return Tasks.isTask(item) && item.parentId === eventItem.id
		})
	}
	Connections {
		target: details.isTask && typeof eventModel !== "undefined" ? eventModel : null
		ignoreUnknownSignals: true
		function onCalendarFetched(calendarId, data) { details.listChanged(calendarId) }
		function onEventAdded(calendarId, data) { details.listChanged(calendarId) }
		function onEventRemoved(calendarId, eventId, data) { details.listChanged(calendarId) }
		function onEventUpdated(calendarId, eventId, data) { details.listChanged(calendarId) }
	}
	function listChanged(calendarId) {
		if (eventItem && calendarId === eventItem.calendarId) {
			listRevision++
		}
	}
	// When the task is due, in words: "Today, 14:00", "Tomorrow", "Wednesday, 28 October", with
	// "Overdue · " before a past day.
	readonly property string dueText: {
		var info = isTask ? Tasks.dueInfo(eventItem, timeModel.currentTime) : { kind: 'none' }
		if (info.kind === 'none') {
			return i18n("No due date")
		}
		var parts = info.day.split('-')
		var date = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
		var dateText = info.kind === 'today' ? i18nc("tasks filter", "Today")
			: info.kind === 'tomorrow' ? i18nc("tasks filter", "Tomorrow")
			: Shared.formatDate(date, i18nc("a task's due date in its details", "dddd, d MMMM"))
		if (eventItem.dueTime) { // Timed TickTick tasks
			var time = eventItem.dueTime.split(':')
			dateText = i18nc("date (%1) with time (%2)", "%1, %2", dateText,
				Shared.formatTime(new Date(2000, 0, 1, Number(time[0]), Number(time[1])), appletConfig.timeFormat))
		}
		return info.kind === 'overdue' ? i18n("Overdue") + " · " + dateText : dateText
	}
	readonly property bool taskInProgress: isTask && Tasks.isInProgress(eventItem, plasmoid.configuration.tasksInProgress)
	readonly property string taskPriority: isTask ? Tasks.priorityKey(eventItem) : 'none'
	function toggleDone() {
		eventModel.toggleTask(eventItem, !isDone)
	}

	onEventItemChanged: {
		confirmingDelete = false
		showAllGuests = false
		pendingResponse = ""
	}

	//--- RSVP: only the signed-in user's own response, on events they were invited to.
	readonly property var selfAttendee: eventItem && typeof eventModel !== "undefined" ? eventModel.selfAttendee(eventItem) : null
	readonly property bool canRespond: !!eventItem && typeof eventModel !== "undefined" && eventModel.canRespond(eventItem)
	property string pendingResponse: "" // Shown right away, until the refetch brings the saved one
	readonly property string currentResponse: pendingResponse || (selfAttendee ? selfAttendee.responseStatus || "" : "")
	function respond(status) {
		if (isRecurring) {
			rsvpScopeMenu.status = status
			rsvpScopeMenu.popup()
		} else {
			saveResponse(status, false)
		}
	}
	function saveResponse(status, series) {
		pendingResponse = status
		eventModel.respondToEvent(eventItem, status, series) // The saved response comes with the refetch
	}
	PlasmaComponents3.Menu {
		id: rsvpScopeMenu
		property string status
		PlasmaComponents3.MenuItem {
			text: i18n("This event")
			onTriggered: details.saveResponse(rsvpScopeMenu.status, false)
		}
		PlasmaComponents3.MenuItem {
			text: i18n("All events in the series")
			onTriggered: details.saveResponse(rsvpScopeMenu.status, true)
		}
	}

	function attendeeIcon(status) {
		return Guests.responseIcon(status)
	}

	function attendeeSummary() {
		var yes = 0, no = 0, maybe = 0, waiting = 0
		for (var i = 0; i < attendees.length; i++) {
			switch (attendees[i].responseStatus) {
				case 'accepted': yes++; break
				case 'declined': no++; break
				case 'tentative': maybe++; break
				default: waiting++
			}
		}
		var parts = []
		if (yes) parts.push(i18nc("guests who accepted", "%1 yes", yes))
		if (maybe) parts.push(i18nc("guests who said maybe", "%1 maybe", maybe))
		if (no) parts.push(i18nc("guests who declined", "%1 no", no))
		if (waiting) parts.push(i18nc("guests who haven't responded", "%1 awaiting", waiting))
		return i18np("1 guest", "%1 guests", attendees.length) + (parts.length ? " · " + parts.join(", ") : "")
	}

	function reminderText() {
		var list = eventItem ? Shared.toArray(eventItem.reminderMinutes) : []
		if (!list.length) {
			return ""
		}
		var parts = list.sort(function(a, b) { return b - a }).map(function(m) {
			return m > 0 ? LocaleFuncs.durationShortFormat(m * 60) : i18nc("reminder at event start", "at start")
		})
		return i18nc("%1 = 10m, 2m", "Reminders: %1 before", parts.join(", "))
	}

	Keys.onEscapePressed: closeRequested()
	Component.onCompleted: forceActiveFocus()

	ColumnLayout {
		anchors.fill: parent
		spacing: 0

		// Actions
		RowLayout {
			id: actionsRow
			Layout.fillWidth: true
			Layout.margins: Kirigami.Units.smallSpacing

			PlasmaComponents3.ToolButton {
				icon.name: "go-previous"
				text: i18n("Back")
				onClicked: details.closeRequested()
			}
			Item { Layout.fillWidth: true }

			// (A task: Edit / Delete at the bottom of its card.)
			PlasmaComponents3.Label {
				visible: details.confirmingDelete && !details.isTask
				text: details.isRecurring ? i18n("Delete:") : i18n("Delete this event?")
			}
			PlasmaComponents3.Button {
				visible: details.confirmingDelete && !details.isTask
				icon.name: "edit-delete"
				text: details.isRecurring ? i18n("This Occurrence") : i18n("Delete")
				onClicked: {
					popup.deleteWithUndo(details.eventItem, false)
					details.closeRequested()
				}
			}
			// Repeating events: delete every occurrence (the series).
			PlasmaComponents3.Button {
				visible: details.confirmingDelete && details.isRecurring
				icon.name: "edit-delete"
				text: i18n("All Events")
				onClicked: {
					popup.deleteWithUndo(details.eventItem, true)
					details.closeRequested()
				}
				PlasmaComponents3.ToolTip.text: i18n("Deletes every occurrence of this repeating event.")
				PlasmaComponents3.ToolTip.visible: hovered
			}
			PlasmaComponents3.ToolButton {
				visible: details.confirmingDelete && !details.isTask
				text: i18n("Cancel")
				onClicked: details.confirmingDelete = false
			}

			PlasmaComponents3.ToolButton {
				// (A task: at the bottom of its card.)
				visible: !details.confirmingDelete && !details.isTask && !!(details.eventItem && details.eventItem.htmlLink)
				icon.name: "globe" // Native action icon (internet-web-browser is a colored app icon)
				text: details.isTask
					? (details.eventItem && details.eventItem.calendarManagerId === "TickTick" ? i18n("Open in TickTick") : i18n("Open in Google Tasks"))
					: i18n("Open in Google Calendar")
				display: QQC2.AbstractButton.IconOnly
				onClicked: Shared.openExternalUrl(details.eventItem.htmlLink)
				PlasmaComponents3.ToolTip.text: text
				PlasmaComponents3.ToolTip.visible: hovered
			}
			PlasmaComponents3.ToolButton {
				visible: !details.confirmingDelete && !details.isTask && !!(details.eventItem && details.eventItem.canEdit)
				icon.name: "document-edit"
				text: i18n("Edit")
				onClicked: details.editRequested()
			}
			PlasmaComponents3.ToolButton {
				visible: !details.confirmingDelete && !!details.eventItem && !details.isTask
				icon.name: "edit-copy"
				text: i18n("Duplicate")
				display: QQC2.AbstractButton.IconOnly
				onClicked: details.duplicateRequested()
				PlasmaComponents3.ToolTip.text: text
				PlasmaComponents3.ToolTip.visible: hovered
			}
			PlasmaComponents3.ToolButton {
				visible: !details.confirmingDelete && !details.isTask && !!(details.eventItem && details.eventItem.canEdit)
				icon.name: "edit-delete"
				text: i18n("Delete")
				display: QQC2.AbstractButton.IconOnly
				onClicked: details.confirmingDelete = true
				PlasmaComponents3.ToolTip.text: text
				PlasmaComponents3.ToolTip.visible: hovered
			}
		}

		PlasmaComponents3.ScrollView {
			id: scrollView
			Layout.fillWidth: true
			Layout.fillHeight: true
			contentWidth: availableWidth
			QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff
			QQC2.ScrollBar.vertical: OverlayScrollBar {
				view: scrollView
			}

			ColumnLayout {
				id: contentColumn
				width: scrollView.availableWidth
				spacing: Kirigami.Units.largeSpacing

				// A task: its own layout (title with its check, a row per property, the notes).
				TaskDetailsBody {
					visible: details.isTask
					Layout.fillWidth: true
					details: details
				}

				// Title with color bar (an event; a task has TaskDetailsBody)
				RowLayout {
					visible: !details.isTask
					Layout.fillWidth: true
					Layout.leftMargin: Kirigami.Units.largeSpacing
					Layout.rightMargin: Kirigami.Units.largeSpacing
					spacing: Kirigami.Units.largeSpacing
					Rectangle {
						Layout.fillHeight: true
						Layout.preferredWidth: 6
						radius: 3
						color: details.eventColor
					}
					ColumnLayout {
						Layout.fillWidth: true
						spacing: Kirigami.Units.smallSpacing
						RowLayout {
							Layout.fillWidth: true
							Kirigami.Heading {
								Layout.fillWidth: true
								level: 2
								wrapMode: Text.Wrap
								text: details.eventItem ? details.eventItem.summary : ""
								textFormat: Text.PlainText // User text: never parsed as HTML
								font.strikeout: details.isDone
								opacity: details.isDone ? 0.7 : 1
							}
							// Private event (Google visibility): only you see its details.
							Kirigami.Icon {
								id: privateIcon
								readonly property string visibility: details.eventItem && details.eventItem.visibility || ""
								visible: visibility === 'private' || visibility === 'confidential'
								source: "object-locked"
								Layout.preferredWidth: Kirigami.Units.iconSizes.small
								Layout.preferredHeight: Kirigami.Units.iconSizes.small
								Layout.alignment: Qt.AlignTop
								opacity: 0.7
								Accessible.name: i18n("Private event")
								HoverHandler {
									id: privateHover
								}
								PlasmaComponents3.ToolTip.text: i18n("Private event")
								PlasmaComponents3.ToolTip.visible: privateHover.hovered
								PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
							}
						}
						PlasmaComponents3.Label {
							Layout.fillWidth: true
							wrapMode: Text.Wrap
							textFormat: Text.PlainText
							text: {
								if (!details.eventItem) {
									return ""
								}
								if (details.isTask) {
									return details.dueText
								}
								var when = LocaleFuncs.formatEventDuration(details.eventItem, {
									relativeDate: timeModel.currentTime,
									clock24h: appletConfig.clock24h,
								})
								if (details.isAllDay) {
									when += " · " + i18n("All day")
								}
								if (details.eventItem.recurringEventId) {
									when += " · " + i18n("Repeats")
								}
								return when
							}
							color: details.isOverdue ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
							opacity: details.isOverdue ? 1 : 0.8
						}
						// The event's own time zone, when its clock differs from the local one.
						PlasmaComponents3.Label {
							readonly property string zone: details.eventItem && !details.isAllDay && details.eventItem.start
								&& details.eventItem.start.timeZone ? String(details.eventItem.start.timeZone) : ""
							readonly property double startMs: details.eventItem ? new Date(details.eventItem.startDateTime).getTime() : 0
							visible: text !== ""
							Layout.fillWidth: true
							wrapMode: Text.Wrap
							opacity: 0.6
							text: {
								if (!zone || !TimeZone.knows(zone) || TimeZone.matchesLocal(zone, startMs)) {
									return ""
								}
								var format = { clock24h: appletConfig.clock24h }
								var start = TimeZone.toWallDate(zone, startMs)
								var end = TimeZone.toWallDate(zone, new Date(details.eventItem.endDateTime).getTime())
								return i18nc("%1 = start and end time, %2 = city, %3 = time zone id", "%1 %2 time (%3)",
									LocaleFuncs.formatEventTime(start, format) + "–" + LocaleFuncs.formatEventTime(end, format),
									TimeZone.cityName(zone), zone)
							}
						}
					}
				}

				// Join
				PlasmaComponents3.Button {
					visible: !!details.meetingLink && !details.isTask
					Layout.leftMargin: Kirigami.Units.largeSpacing
					icon.name: "call-start"
					text: details.meetingLink ? i18nc("%1 = Google Meet, Zoom, ...", "Join %1", details.meetingLink.label) : ""
					onClicked: meetingOpener.open(details.meetingLink.url)
				}

				// RSVP
				RowLayout {
					visible: details.canRespond && !details.isTask
					Layout.fillWidth: true
					Layout.leftMargin: Kirigami.Units.largeSpacing
					Layout.rightMargin: Kirigami.Units.largeSpacing
					spacing: Kirigami.Units.smallSpacing
					PlasmaComponents3.Label {
						text: i18nc("RSVP to an invitation", "Going?")
						Layout.rightMargin: Kirigami.Units.smallSpacing
					}
					Repeater {
						model: Responses.choices()
						PlasmaComponents3.ToolButton {
							text: modelData.text
							icon.name: modelData.icon
							checkable: true
							checked: details.currentResponse === modelData.status
							// A click sets the response; the check follows currentResponse.
							onClicked: {
								checked = Qt.binding(function() { return details.currentResponse === modelData.status })
								details.respond(modelData.status)
							}
						}
					}
					Item { Layout.fillWidth: true }
				}

				Kirigami.Separator {
					visible: !details.isTask
					Layout.fillWidth: true
				}

				// Properties: icon + text rows (an event's)
				GridLayout {
					visible: !details.isTask
					Layout.fillWidth: true
					Layout.leftMargin: Kirigami.Units.largeSpacing
					Layout.rightMargin: Kirigami.Units.largeSpacing
					columns: 2
					columnSpacing: Kirigami.Units.largeSpacing
					rowSpacing: Kirigami.Units.largeSpacing

					// Out of office / focus time (Google event types), with their auto-decline.
					Kirigami.Icon {
						visible: eventTypeLabel.visible
						source: details.isOutOfOffice ? Shared.EVENT_INDICATOR_ICONS.outOfOffice : Shared.EVENT_INDICATOR_ICONS.focusTime
						Layout.preferredWidth: Kirigami.Units.iconSizes.small
						Layout.preferredHeight: Kirigami.Units.iconSizes.small
						Layout.alignment: Qt.AlignTop
					}
					PlasmaComponents3.Label {
						id: eventTypeLabel
						readonly property var decline: EventTypes.autoDecline(details.eventItem)
						visible: details.isOutOfOffice || details.isFocusTime
						Layout.fillWidth: true
						wrapMode: Text.Wrap
						text: {
							var lines = [details.isOutOfOffice ? i18n("Out of office") : i18n("Focus time")]
							if (decline.declines === 'all') {
								lines.push(i18n("Declines all meetings at this time"))
							} else if (decline.declines === 'new') {
								lines.push(i18n("Declines new invitations at this time"))
							}
							if (decline.message) {
								lines.push(i18nc("%1 = message sent when declining", "Message: “%1”", decline.message))
							}
							return lines.join("\n")
						}
					}

					// Overlapping meetings
					Kirigami.Icon {
						visible: conflictLabel.visible
						source: Shared.EVENT_INDICATOR_ICONS.conflict
						Layout.preferredWidth: Kirigami.Units.iconSizes.small
						Layout.preferredHeight: Kirigami.Units.iconSizes.small
						Layout.alignment: Qt.AlignTop
					}
					PlasmaComponents3.Label {
						id: conflictLabel
						readonly property var titles: Shared.conflictTitles(details.eventItem)
						visible: titles.length > 0
						Layout.fillWidth: true
						wrapMode: Text.Wrap
						text: i18nc("%1 = titles of other events at the same time", "Overlaps with: %1", titles.join(", "))
						textFormat: Text.PlainText // User text: never parsed as HTML
					}

					// Location
					Kirigami.Icon {
						visible: locationLabel.visible
						source: "mark-location"
						Layout.preferredWidth: Kirigami.Units.iconSizes.small
						Layout.preferredHeight: Kirigami.Units.iconSizes.small
						Layout.alignment: Qt.AlignTop
					}
					PlasmaComponents3.Label {
						id: locationLabel
						readonly property string location: details.eventItem && details.eventItem.location ? details.eventItem.location : ""
						visible: !!location && !details.isTask
						Layout.fillWidth: true
						wrapMode: Text.Wrap
						textFormat: Text.StyledText
						text: Shared.locationLink(location) // Google Maps, or the URL itself
						linkColor: Kirigami.Theme.linkColor
						onLinkActivated: function(link) { Shared.openExternalUrl(link) }
					}

					// Rooms
					Kirigami.Icon {
						visible: roomsLabel.visible
						source: "go-home"
						Layout.preferredWidth: Kirigami.Units.iconSizes.small
						Layout.preferredHeight: Kirigami.Units.iconSizes.small
						Layout.alignment: Qt.AlignTop
					}
					PlasmaComponents3.Label {
						id: roomsLabel
						readonly property string location: details.eventItem && details.eventItem.location ? details.eventItem.location : ""
						// Skip rooms already named in the location.
						readonly property var extraRooms: details.rooms.filter(function(r) {
							var name = r.displayName || r.email || ""
							return name && location.indexOf(name) < 0
						})
						visible: extraRooms.length > 0
						Layout.fillWidth: true
						wrapMode: Text.Wrap
						text: extraRooms.map(function(r) { return r.displayName || r.email }).join(", ")
						textFormat: Text.PlainText // User text: never parsed as HTML
					}

					// Calendar
					Rectangle {
						visible: calendarLabel.visible
						Layout.preferredWidth: Kirigami.Units.iconSizes.small
						Layout.preferredHeight: Kirigami.Units.iconSizes.small
						Layout.alignment: Qt.AlignTop
						radius: width / 2
						color: details.calendar && details.calendar.backgroundColor
							? GooglePalette.displayCalendarColor(details.calendar, plasmoid.configuration.googleColorPalette)
							: details.eventColor
					}
					PlasmaComponents3.Label {
						id: calendarLabel
						visible: !!(details.calendar && details.calendar.summary)
						Layout.fillWidth: true
						wrapMode: Text.Wrap
						text: {
							var name = details.calendar ? String(details.calendar.summary) : ""
							// Primary calendars are named after the account: "a@x.com - a@x.com".
							var parts = name.split(" - ")
							if (details.isTask && parts.length > 1) {
								return parts.slice(1).join(" - ") // A task list: "TickTick - Work" is "Work"
							}
							return parts.length === 2 && parts[0] === parts[1] ? parts[0] : name
						}
						textFormat: Text.PlainText
					}

					// Reminders
					Kirigami.Icon {
						visible: reminderLabel.visible
						source: "notifications"
						Layout.preferredWidth: Kirigami.Units.iconSizes.small
						Layout.preferredHeight: Kirigami.Units.iconSizes.small
						Layout.alignment: Qt.AlignTop
					}
					PlasmaComponents3.Label {
						id: reminderLabel
						visible: !!text
						Layout.fillWidth: true
						wrapMode: Text.Wrap
						text: details.reminderText()
					}

					// File attachments (Google Drive): each opens in the browser.
					Kirigami.Icon {
						visible: attachmentList.visible
						source: "mail-attachment"
						Layout.preferredWidth: Kirigami.Units.iconSizes.small
						Layout.preferredHeight: Kirigami.Units.iconSizes.small
						Layout.alignment: Qt.AlignTop
					}
					ColumnLayout {
						id: attachmentList
						visible: details.attachments.length > 0
						Layout.fillWidth: true
						spacing: Kirigami.Units.smallSpacing
						Repeater {
							model: details.attachments
							RowLayout {
								Layout.fillWidth: true
								spacing: Kirigami.Units.smallSpacing
								Kirigami.Icon {
									source: modelData.icon
									fallback: "text-x-generic"
									Layout.preferredWidth: Kirigami.Units.iconSizes.small
									Layout.preferredHeight: Kirigami.Units.iconSizes.small
								}
								PlasmaComponents3.Label {
									Layout.fillWidth: true
									elide: Text.ElideMiddle
									text: modelData.title
									textFormat: Text.PlainText // User text: never parsed as HTML
									color: Kirigami.Theme.linkColor
									font.underline: attachmentMouse.containsMouse
									MouseArea {
										id: attachmentMouse
										anchors.fill: parent
										hoverEnabled: true
										cursorShape: Qt.PointingHandCursor
										onClicked: Shared.openExternalUrl(modelData.url)
									}
									Accessible.role: Accessible.Link
									Accessible.name: modelData.title
								}
							}
						}
					}

				}


				// Guests
				ColumnLayout {
					visible: details.attendees.length > 0 && !details.isTask
					Layout.fillWidth: true
					Layout.leftMargin: Kirigami.Units.largeSpacing
					Layout.rightMargin: Kirigami.Units.largeSpacing
					spacing: Kirigami.Units.smallSpacing

					Kirigami.Separator {
						Layout.fillWidth: true
						Layout.leftMargin: -Kirigami.Units.largeSpacing
						Layout.rightMargin: -Kirigami.Units.largeSpacing
						Layout.bottomMargin: Kirigami.Units.smallSpacing
					}
					RowLayout {
						Layout.fillWidth: true
						spacing: Kirigami.Units.largeSpacing
						Kirigami.Icon {
							source: "group"
							Layout.preferredWidth: Kirigami.Units.iconSizes.small
							Layout.preferredHeight: Kirigami.Units.iconSizes.small
						}
						PlasmaComponents3.Label {
							Layout.fillWidth: true
							wrapMode: Text.Wrap
							font.weight: Font.DemiBold
							text: details.attendeeSummary()
						}
						PlasmaComponents3.ToolButton {
							visible: !!details.mailtoUrl
							icon.name: "mail-message-new"
							text: i18n("Email Guests…")
							display: details.width < Kirigami.Units.gridUnit * 22 ? QQC2.AbstractButton.IconOnly : QQC2.AbstractButton.TextBesideIcon
							onClicked: Shared.openMailtoUrl(details.mailtoUrl)
							PlasmaComponents3.ToolTip.text: i18n("Write an email to the guests")
							PlasmaComponents3.ToolTip.visible: hovered
						}
					}
					Repeater {
						model: details.showAllGuests ? details.attendees : details.attendees.slice(0, details.collapsedGuestCount)
						RowLayout {
							Layout.fillWidth: true
							Layout.leftMargin: Kirigami.Units.iconSizes.small + Kirigami.Units.largeSpacing
							spacing: Kirigami.Units.smallSpacing
							Kirigami.Icon {
								source: details.attendeeIcon(modelData.responseStatus)
								Layout.preferredWidth: Kirigami.Units.iconSizes.small
								Layout.preferredHeight: Kirigami.Units.iconSizes.small
							}
							PlasmaComponents3.Label {
								Layout.fillWidth: true
								elide: Text.ElideRight
								text: {
									var name = modelData.displayName || modelData.email || ""
									var tags = []
									if (modelData.organizer) {
										tags.push(i18nc("event organizer", "organizer"))
									}
									if (modelData.self) {
										tags.push(i18nc("the current user in a guest list", "you"))
									}
									return tags.length ? name + " (" + tags.join(", ") + ")" : name
								}
								opacity: modelData.responseStatus === 'declined' ? 0.6 : 1
							}
						}
					}
					PlasmaComponents3.ToolButton {
						visible: details.attendees.length > details.collapsedGuestCount
						Layout.leftMargin: Kirigami.Units.iconSizes.small
						text: details.showAllGuests ? i18n("Show less") : i18np("Show 1 more", "Show all %1", details.attendees.length)
						icon.name: details.showAllGuests ? "go-up" : "go-down"
						onClicked: details.showAllGuests = !details.showAllGuests
					}
				}

				Kirigami.Separator {
					visible: subtasksColumn.visible
					Layout.fillWidth: true
				}

				// Tasks: the subtasks, each with its check (Google's: a task row, opens it).
				ColumnLayout {
					id: subtasksColumn
					visible: details.checklist.length > 0 || details.childTasks.length > 0
					Layout.fillWidth: true
					Layout.leftMargin: Kirigami.Units.largeSpacing
					Layout.rightMargin: Kirigami.Units.largeSpacing
					spacing: 2
					PlasmaComponents3.Label {
						readonly property var progress: Tasks.subtaskProgress(details.eventItem)
						Layout.fillWidth: true
						// Both kinds (a checklist and child tasks): no count for half of them.
						text: details.checklist.length > 0 && details.childTasks.length === 0
							? i18nc("checklist items done: %1 of %2", "%1 of %2 subtasks done", progress.done, progress.total)
							: i18n("Subtasks")
						textFormat: Text.PlainText
						font.weight: Font.DemiBold
						opacity: 0.8
					}
					Repeater {
						model: details.checklist
						RowLayout {
							id: checklistRow
							readonly property var subtask: modelData
							Layout.fillWidth: true
							spacing: Kirigami.Units.smallSpacing * 2
							TaskCheck {
								id: checklistCheck
								Layout.alignment: Qt.AlignVCenter
								size: 2 * Math.round(checklistLabel.implicitHeight / 2)
								eventItem: details.eventItem
								subtaskId: checklistRow.subtask.id
								subtaskDone: !!checklistRow.subtask.done
								color: details.eventColor
								square: appletConfig.islands
							}
							PlasmaComponents3.Label {
								id: checklistLabel
								Layout.fillWidth: true
								Layout.minimumWidth: 0
								text: checklistRow.subtask.title
								textFormat: Text.PlainText // User text: never parsed as HTML
								opacity: checklistCheck.done ? 0.55 : 1
								font.strikeout: checklistCheck.done
								wrapMode: Text.Wrap
							}
						}
					}
					Repeater {
						model: details.childTasks
						TaskRow {
							Layout.fillWidth: true
							eventItem: modelData
							today: Tasks.dayString(timeModel.currentTime)
							compact: true
							actionsEnabled: false
						}
					}
				}

				Kirigami.Separator {
					visible: descriptionLabel.visible
					Layout.fillWidth: true
				}

				// Description
				PlasmaComponents3.Label {
					id: descriptionLabel
					// Tasks: their notes.
					// (A task's notes are in TaskDetailsBody.)
					readonly property string description: !details.eventItem || details.isTask ? ""
						: details.eventItem.description ? details.eventItem.description : ""
					visible: !!description
					Layout.fillWidth: true
					Layout.leftMargin: Kirigami.Units.largeSpacing
					Layout.rightMargin: Kirigami.Units.largeSpacing
					Layout.bottomMargin: Kirigami.Units.largeSpacing
					wrapMode: Text.Wrap
					textFormat: Text.RichText
					// Plain-text descriptions: keep their line breaks (rich text ignores \n).
					text: {
						var html = Shared.renderText(description)
						return /<(br|p|div|li)\b/i.test(description) ? html : html.replace(/\n/g, '<br>')
					}
					linkColor: Kirigami.Theme.linkColor
					onLinkActivated: function(link) { Shared.openExternalUrl(link) }
				}

				// A task: under a thin line, quiet buttons - Edit, Open in TickTick / Google Tasks and
				// Delete (red; asks here first).
				Kirigami.Separator {
					visible: details.isTask
					Layout.fillWidth: true
					Layout.topMargin: Kirigami.Units.smallSpacing
				}
				RowLayout {
					visible: details.isTask
					Layout.fillWidth: true
					Layout.leftMargin: Kirigami.Units.smallSpacing
					Layout.rightMargin: Kirigami.Units.smallSpacing
					Layout.topMargin: -Kirigami.Units.smallSpacing
					Layout.bottomMargin: Kirigami.Units.smallSpacing
					spacing: 0
					PlasmaComponents3.ToolButton {
						visible: !details.confirmingDelete && !!(details.eventItem && details.eventItem.canEdit)
						icon.name: "document-edit"
						text: i18n("Edit")
						onClicked: details.editRequested()
					}
					PlasmaComponents3.ToolButton {
						visible: !details.confirmingDelete && !!(details.eventItem && details.eventItem.htmlLink)
						icon.name: "globe"
						text: details.eventItem && details.eventItem.calendarManagerId === "TickTick" ? i18n("Open in TickTick") : i18n("Open in Google Tasks")
						onClicked: Shared.openExternalUrl(details.eventItem.htmlLink)
					}
					PlasmaComponents3.Label {
						visible: details.confirmingDelete
						Layout.fillWidth: true
						Layout.leftMargin: Kirigami.Units.smallSpacing
						text: i18n("Delete this task?")
						textFormat: Text.PlainText
						elide: Text.ElideRight
					}
					Item {
						visible: !details.confirmingDelete
						Layout.fillWidth: true
					}
					PlasmaComponents3.ToolButton {
						visible: !!(details.eventItem && details.eventItem.canEdit)
						icon.name: "edit-delete"
						text: i18n("Delete")
						display: details.confirmingDelete ? QQC2.AbstractButton.TextBesideIcon : QQC2.AbstractButton.IconOnly
						onClicked: {
							if (!details.confirmingDelete) {
								details.confirmingDelete = true
								return
							}
							popup.deleteWithUndo(details.eventItem, false)
							details.closeRequested()
						}
						PlasmaComponents3.ToolTip.text: text
						PlasmaComponents3.ToolTip.visible: hovered && !details.confirmingDelete
					}
					PlasmaComponents3.ToolButton {
						visible: details.confirmingDelete
						text: i18n("Cancel")
						onClicked: details.confirmingDelete = false
					}
				}
			}
		}
	}
}
