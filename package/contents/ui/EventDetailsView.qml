import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "LocaleFuncs.js" as LocaleFuncs
import "MeetingLink.js" as MeetingLink
import "Shared.js" as Shared

// Event details shown inside the popup, like mobile calendar apps.
Rectangle {
	id: details

	property var eventItem: null
	signal closeRequested()

	color: Kirigami.Theme.backgroundColor
	radius: Kirigami.Units.cornerRadius * 2
	border.width: 1
	border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
	// Content height, so the card can be sized to fit (it scrolls when taller than the popup).
	implicitHeight: actionsRow.implicitHeight + Kirigami.Units.smallSpacing * 2 + contentColumn.implicitHeight + Kirigami.Units.largeSpacing

	readonly property var meetingLink: eventItem ? MeetingLink.find(eventItem) : null
	readonly property var calendar: eventItem && typeof eventModel !== "undefined" ? eventModel.getCalendar(eventItem.calendarId) : null
	readonly property color eventColor: eventItem && eventItem.backgroundColor ? eventItem.backgroundColor : Kirigami.Theme.highlightColor
	readonly property bool isAllDay: !!(eventItem && eventItem.start && eventItem.start.date)
	readonly property var attendees: eventItem ? Shared.toArray(eventItem.attendees) : []
	property bool confirmingDelete: false
	onEventItemChanged: confirmingDelete = false

	function isUrl(text) {
		return /^https?:\/\/\S+$/i.test(String(text || '').trim())
	}

	function attendeeIcon(status) {
		switch (status) {
			case 'accepted': return "dialog-ok-apply"
			case 'declined': return "dialog-cancel"
			case 'tentative': return "question"
			default: return "clock"
		}
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
		return i18np("1 guest", "%1 guests", attendees.length) + (parts.length ? " (" + parts.join(", ") + ")" : "")
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

			PlasmaComponents3.Label {
				visible: details.confirmingDelete
				text: i18n("Delete this event?")
			}
			PlasmaComponents3.Button {
				visible: details.confirmingDelete
				icon.name: "edit-delete"
				text: i18n("Delete")
				onClicked: {
					eventModel.deleteEvent(details.eventItem.calendarId, details.eventItem.id)
					details.closeRequested()
				}
			}
			PlasmaComponents3.ToolButton {
				visible: details.confirmingDelete
				text: i18n("Cancel")
				onClicked: details.confirmingDelete = false
			}

			PlasmaComponents3.ToolButton {
				visible: !details.confirmingDelete && !!(details.eventItem && details.eventItem.htmlLink)
				icon.name: "internet-web-browser"
				text: i18n("Open in Google Calendar")
				display: QQC2.AbstractButton.IconOnly
				onClicked: Qt.openUrlExternally(details.eventItem.htmlLink)
				PlasmaComponents3.ToolTip.text: text
				PlasmaComponents3.ToolTip.visible: hovered
			}
			PlasmaComponents3.ToolButton {
				visible: !details.confirmingDelete && !!(details.eventItem && details.eventItem.canEdit)
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

			ColumnLayout {
				id: contentColumn
				width: scrollView.availableWidth
				spacing: Kirigami.Units.largeSpacing

				// Title with color bar
				RowLayout {
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
						Kirigami.Heading {
							Layout.fillWidth: true
							level: 2
							wrapMode: Text.Wrap
							text: details.eventItem ? details.eventItem.summary : ""
						}
						PlasmaComponents3.Label {
							Layout.fillWidth: true
							wrapMode: Text.Wrap
							text: {
								if (!details.eventItem) {
									return ""
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
							opacity: 0.8
						}
					}
				}

				// Join
				PlasmaComponents3.Button {
					visible: !!details.meetingLink
					Layout.leftMargin: Kirigami.Units.largeSpacing
					icon.name: "call-start"
					text: details.meetingLink ? i18nc("%1 = Google Meet, Zoom, ...", "Join %1", details.meetingLink.label) : ""
					onClicked: Qt.openUrlExternally(details.meetingLink.url)
				}

				// Properties: icon + text rows
				GridLayout {
					Layout.fillWidth: true
					Layout.leftMargin: Kirigami.Units.largeSpacing
					Layout.rightMargin: Kirigami.Units.largeSpacing
					columns: 2
					columnSpacing: Kirigami.Units.largeSpacing
					rowSpacing: Kirigami.Units.smallSpacing

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
						visible: !!location
						Layout.fillWidth: true
						wrapMode: Text.Wrap
						textFormat: Text.StyledText
						text: details.isUrl(location) ? '<a href="' + location + '">' + location + '</a>' : location
						linkColor: Kirigami.Theme.linkColor
						onLinkActivated: function(link) { Qt.openUrlExternally(link) }
					}

					// Calendar
					Rectangle {
						visible: calendarLabel.visible
						Layout.preferredWidth: Kirigami.Units.iconSizes.small
						Layout.preferredHeight: Kirigami.Units.iconSizes.small
						Layout.alignment: Qt.AlignTop
						radius: width / 2
						color: details.calendar && details.calendar.backgroundColor ? details.calendar.backgroundColor : details.eventColor
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
							return parts.length === 2 && parts[0] === parts[1] ? parts[0] : name
						}
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

					// Guests
					Kirigami.Icon {
						visible: details.attendees.length > 0
						source: "group"
						Layout.preferredWidth: Kirigami.Units.iconSizes.small
						Layout.preferredHeight: Kirigami.Units.iconSizes.small
						Layout.alignment: Qt.AlignTop
					}
					ColumnLayout {
						visible: details.attendees.length > 0
						Layout.fillWidth: true
						spacing: 2
						PlasmaComponents3.Label {
							Layout.fillWidth: true
							wrapMode: Text.Wrap
							text: details.attendeeSummary()
						}
						Repeater {
							model: details.attendees
							RowLayout {
								Layout.fillWidth: true
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
					}
				}

				// Description
				PlasmaComponents3.Label {
					readonly property string description: details.eventItem && details.eventItem.description ? details.eventItem.description : ""
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
					onLinkActivated: function(link) { Qt.openUrlExternally(link) }
				}
			}
		}
	}
}
