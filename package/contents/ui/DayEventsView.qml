import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "Shared.js" as Shared

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
	border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
	implicitHeight: actionsRow.implicitHeight + Kirigami.Units.smallSpacing * 2 + eventsColumn.implicitHeight + Kirigami.Units.largeSpacing

	readonly property var events: {
		var _ = eventModel.eventsData // Rebuild when events are refetched.
		var items = eventModel.eventsData ? eventModel.eventsData.items : []
		var dayStart = new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime()
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
	function timeText(e) {
		if (isAllDay(e)) {
			return i18n("All day")
		}
		var format = appletConfig.clock24h ? 'HH:mm' : 'h:mm AP'
		// Events spanning several days: show the dates too, eg: "14 Oct 22:00 – 16 Oct 02:00".
		if (!Shared.isSameDate(e.startDateTime, e.endDateTime)) {
			var dateFormat = 'd MMM '
			return Qt.formatDateTime(e.startDateTime, dateFormat + format) + ' – ' + Qt.formatDateTime(e.endDateTime, dateFormat + format)
		}
		return Qt.formatTime(e.startDateTime, format) + ' – ' + Qt.formatTime(e.endDateTime, format)
	}

	Keys.onEscapePressed: closeRequested()
	Component.onCompleted: forceActiveFocus()

	ColumnLayout {
		anchors.fill: parent
		spacing: 0

		RowLayout {
			id: actionsRow
			Layout.fillWidth: true
			Layout.margins: Kirigami.Units.smallSpacing
			PlasmaComponents3.ToolButton {
				icon.name: "go-previous"
				text: i18n("Back")
				onClicked: dayView.closeRequested()
			}
			Kirigami.Heading {
				Layout.fillWidth: true
				Layout.leftMargin: Kirigami.Units.smallSpacing
				level: 3
				elide: Text.ElideRight
				font.capitalization: Font.Capitalize
				text: Qt.formatDate(dayView.date, Qt.locale().dateFormat(Locale.LongFormat))
			}
			PlasmaComponents3.Button {
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
					PlasmaComponents3.ItemDelegate {
						id: eventRow
						readonly property var eventItem: modelData
						readonly property bool inProgress: !dayView.isAllDay(eventItem)
							&& eventItem.startDateTime <= timeModel.currentTime && timeModel.currentTime < eventItem.endDateTime
						Layout.fillWidth: true
						onClicked: dayView.eventClicked(eventItem)

						contentItem: RowLayout {
							spacing: Kirigami.Units.largeSpacing
							PlasmaComponents3.Label {
								Layout.preferredWidth: Kirigami.Units.gridUnit * 6
								wrapMode: Text.Wrap
								Layout.alignment: Qt.AlignTop
								text: dayView.timeText(eventRow.eventItem)
								opacity: 0.7
							}
							Rectangle {
								Layout.fillHeight: true
								Layout.preferredWidth: 4
								radius: 2
								color: eventRow.eventItem.backgroundColor || Kirigami.Theme.highlightColor
							}
							ColumnLayout {
								Layout.fillWidth: true
								spacing: 0
								PlasmaComponents3.Label {
									Layout.fillWidth: true
									wrapMode: Text.Wrap
									text: eventRow.eventItem.summary
									font.bold: eventRow.inProgress
								}
								PlasmaComponents3.Label {
									visible: !!eventRow.eventItem.location
									Layout.fillWidth: true
									elide: Text.ElideRight
									text: eventRow.eventItem.location || ""
									font: Kirigami.Theme.smallFont
									opacity: 0.7
								}
							}
						}
					}
				}
			}
		}
	}
}
