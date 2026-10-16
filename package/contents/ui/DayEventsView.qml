import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "Shared.js" as Shared
import "lib/ColorUtil.js" as ColorUtil

// A day's events as a list card (month view: click a day).
Rectangle {
	id: dayView

	property date date: new Date()
	signal closeRequested()
	signal eventClicked(var eventItem)
	signal addRequested()

	color: Kirigami.Theme.backgroundColor
	radius: Kirigami.Units.cornerRadius * 2
	border.width: 1
	border.color: ColorUtil.setAlpha(Kirigami.Theme.textColor, 0.15)
	implicitHeight: actionsRow.implicitHeight + Kirigami.Units.smallSpacing * 2 + eventsColumn.implicitHeight + Kirigami.Units.largeSpacing

	readonly property var events: {
		var _ = eventModel.eventsData // Rebuild when events are refetched.
		var items = eventModel.eventsData ? eventModel.eventsData.items : []
		var dayStart = Shared.startOfDay(date).getTime()
		var dayEnd = new Date(date.getFullYear(), date.getMonth(), date.getDate() + 1).getTime()
		var list = []
		for (var i = 0; i < items.length; i++) {
			var e = items[i]
			if (!e.startDateTime || !e.endDateTime) {
				continue
			}
			var start = e.startDateTime.getTime()
			var end = e.endDateTime.getTime()
			if (end <= start) {
				end = start + (isAllDay(e) ? 24 * 60 * 60 * 1000 : 1)
			}
			if (start < dayEnd && end > dayStart) {
				list.push(e)
			}
		}
		// All-day first, then by start time.
		list.sort(function(a, b) {
			var aAllDay = isAllDay(a)
			var bAllDay = isAllDay(b)
			if (aAllDay !== bAllDay) {
				return aAllDay ? -1 : 1
			}
			return a.startDateTime - b.startDateTime
		})
		return list
	}

	function isAllDay(e) {
		return !!(e.start && e.start.date)
	}
	// "All day", "09:45 – 10:00", or with dates for multi-day events.
	function timeText(e) {
		var span = Shared.eventSpan(e, appletConfig.timeFormat, timeModel.currentTime)
		if (span.allDay && !span.multiDay) {
			return i18n("All day")
		}
		return i18nc("event span, %1 = start, %2 = end", "%1 – %2", span.startText, span.endText)
	}

	Keys.onEscapePressed: closeRequested()
	Component.onCompleted: forceActiveFocus()

	ColumnLayout {
		anchors.fill: parent
		spacing: 0

		// Back on the left, date centered, Add Event on the right.
		Item {
			id: actionsRow
			Layout.fillWidth: true
			Layout.margins: Kirigami.Units.smallSpacing
			implicitHeight: Math.max(backButton.implicitHeight, addButton.implicitHeight, dayTitle.implicitHeight)

			PlasmaComponents3.ToolButton {
				id: backButton
				anchors.left: parent.left
				anchors.verticalCenter: parent.verticalCenter
				icon.name: "go-previous"
				text: i18n("Back")
				onClicked: dayView.closeRequested()
			}
			Kirigami.Heading {
				id: dayTitle
				anchors.centerIn: parent
				width: Math.min(implicitWidth, parent.width - Math.max(backButton.width, addButton.width) * 2 - Kirigami.Units.largeSpacing * 2)
				horizontalAlignment: Text.AlignHCenter
				level: 3
				elide: Text.ElideRight
				font.capitalization: Font.Capitalize
				text: Qt.formatDate(dayView.date, Qt.locale().dateFormat(Locale.LongFormat))
			}
			PlasmaComponents3.Button {
				id: addButton
				anchors.right: parent.right
				anchors.verticalCenter: parent.verticalCenter
				icon.name: "list-add"
				text: i18n("Add Event")
				onClicked: dayView.addRequested()
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
				id: eventsColumn
				width: scrollView.availableWidth
				spacing: 0

				PlasmaComponents3.Label {
					visible: dayView.events.length === 0
					Layout.fillWidth: true
					Layout.margins: Kirigami.Units.largeSpacing * 2
					horizontalAlignment: Text.AlignHCenter
					text: i18n("No events")
					opacity: 0.6
				}

				Repeater {
					model: dayView.events
					// Event tile in the event color, like the week view.
					Rectangle {
						id: eventRow
						readonly property var eventItem: modelData
						readonly property color tileColor: appletConfig.eventColor(eventItem.backgroundColor)
						readonly property color textColor: Shared.contrastTextColor(tileColor)
						readonly property bool inProgress: !dayView.isAllDay(eventItem)
							&& eventItem.startDateTime <= timeModel.currentTime && timeModel.currentTime < eventItem.endDateTime
						Layout.fillWidth: true
						Layout.leftMargin: Kirigami.Units.largeSpacing
						Layout.rightMargin: Kirigami.Units.largeSpacing
						Layout.topMargin: index === 0 ? Kirigami.Units.largeSpacing : Kirigami.Units.smallSpacing
						implicitHeight: tileColumn.implicitHeight + Kirigami.Units.smallSpacing * 2 + 2
						radius: 8
						color: tileColor
						border.width: 1
						border.color: appletConfig.eventBorderColor
						opacity: tileMouse.containsMouse ? 0.85 : 1

						ColumnLayout {
							id: tileColumn
							z: 1 // Above the tile's mouse area: location links take their clicks
							anchors.left: parent.left
							anchors.right: parent.right
							anchors.verticalCenter: parent.verticalCenter
							anchors.leftMargin: Kirigami.Units.largeSpacing
							anchors.rightMargin: Kirigami.Units.largeSpacing
							spacing: 1
							PlasmaComponents3.Label {
								Layout.fillWidth: true
								wrapMode: Text.Wrap
								text: eventRow.eventItem.summary
								color: eventRow.textColor
								font.bold: eventRow.inProgress
							}
							PlasmaComponents3.Label {
								Layout.fillWidth: true
								elide: Text.ElideRight
								// The location opens in Google Maps.
								text: {
									var parts = [Shared.escapeHtml(dayView.timeText(eventRow.eventItem))]
									if (eventRow.eventItem.location) {
										parts.push(Shared.locationLink(eventRow.eventItem.location))
									}
									return parts.join(' · ')
								}
								textFormat: Text.StyledText
								linkColor: eventRow.textColor
								onLinkActivated: function(link) { Shared.openExternalUrl(link) }
								color: eventRow.textColor
								opacity: 0.85
								font: Kirigami.Theme.smallFont
							}
						}

						MouseArea {
							id: tileMouse
							anchors.fill: parent
							hoverEnabled: true
							cursorShape: Qt.PointingHandCursor
							acceptedButtons: Qt.LeftButton | Qt.RightButton
							onClicked: function(mouse) {
								if (mouse.button === Qt.RightButton) {
									popup.showEventMenu(eventRow.eventItem, eventRow, mouse.x, mouse.y)
								} else {
									dayView.eventClicked(eventRow.eventItem)
								}
							}
						}
					}
				}
			}
		}
	}
}
