import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "Shared.js" as Shared
import "EventSearch.js" as EventSearch
import "lib/ColorUtil.js" as ColorUtil

// Search events by title, location and description: the loaded events right away, then Google
// Calendar a year back and ahead (the server also matches guests and other fields).
Rectangle {
	id: searchView

	signal closeRequested()
	signal eventClicked(var eventItem)

	property alias searchText: searchField.text
	readonly property string query: searchField.text.trim()
	readonly property int remoteRangeDays: 365
	readonly property int resultLimit: 100

	property var remoteResults: []
	property string remoteQuery: ""
	property bool searching: false
	property bool remoteFailed: false
	property int generation: 0 // Answers to older queries are ignored.
	property bool canSearchRemote: false // Any calendar that can be searched on the server (Google)

	readonly property var localResults: {
		var _ = eventModel.eventsData // Search again when events are refetched.
		var items = eventModel.eventsData ? eventModel.eventsData.items : []
		return EventSearch.searchLocal(items, query, timeModel.currentTime, resultLimit)
	}
	readonly property var results: {
		// Google results for an older query: keep the ones that still match while typing on.
		var remote = remoteResults
		if (remoteQuery !== query) {
			var queryTokens = EventSearch.tokens(query)
			remote = remote.filter(function(e) { return EventSearch.matches(e, queryTokens) })
		}
		return EventSearch.merge(localResults, remote, timeModel.currentTime, resultLimit)
	}

	color: Kirigami.Theme.backgroundColor
	radius: Kirigami.Units.cornerRadius * 2
	border.width: 1
	border.color: ColorUtil.setAlpha(Kirigami.Theme.textColor, 0.15)
	// With a query the card takes the available height, so it doesn't jump while results come in.
	implicitHeight: actionsRow.implicitHeight + Kirigami.Units.smallSpacing * 2
		+ (query ? Kirigami.Units.gridUnit * 40 : resultsColumn.implicitHeight + Kirigami.Units.largeSpacing)

	onQueryChanged: {
		generation += 1
		searching = false
		remoteFailed = false
		if (canSearchRemote && query.length >= 2) {
			remoteTimer.restart()
		} else {
			remoteTimer.stop()
			remoteResults = []
			remoteQuery = ""
		}
	}

	Timer {
		id: remoteTimer
		interval: 400 // Search once typing pauses.
		onTriggered: searchView.searchRemote()
	}

	function searchRemote() {
		var q = query
		var gen = generation
		var now = new Date()
		var timeMin = new Date(now.getTime() - remoteRangeDays * 86400000)
		var timeMax = new Date(now.getTime() + remoteRangeDays * 86400000)
		searching = true
		eventModel.searchEvents(q, timeMin, timeMax, function(err, items) {
			if (gen !== searchView.generation) {
				return
			}
			searchView.searching = false
			searchView.remoteFailed = !!err
			searchView.remoteResults = items || []
			searchView.remoteQuery = q
		})
	}

	function isAllDay(e) {
		return !!(e.start && e.start.date)
	}
	// "Fri 23 Oct · 12:30 – 13:30", "Fri 23 Oct · All day", or a span of days.
	function whenText(e) {
		var now = timeModel.currentTime
		var span = Shared.eventSpan(e, appletConfig.timeFormat, now)
		if (span.multiDay) {
			return i18nc("event span, %1 = start, %2 = end", "%1 – %2", span.startText, span.endText)
		}
		var start = new Date(e.startDateTime)
		var day = Qt.formatDate(start, 'ddd ' + Shared.spanDateFormat(start, start, now))
		if (span.allDay) {
			return i18nc("search result, %1 = date", "%1 · All day", day)
		}
		return i18nc("search result, %1 = date, %2 = start time, %3 = end time", "%1 · %2 – %3", day, span.startText, span.endText)
	}

	Keys.onEscapePressed: closeRequested()
	Component.onCompleted: {
		canSearchRemote = eventModel.calendarManagerList.some(function(m) {
			return typeof m.searchEvents === 'function'
		})
		searchField.forceActiveFocus()
	}

	ColumnLayout {
		anchors.fill: parent
		spacing: 0

		// Back, then the search field.
		RowLayout {
			id: actionsRow
			Layout.fillWidth: true
			Layout.margins: Kirigami.Units.smallSpacing
			spacing: Kirigami.Units.smallSpacing

			PlasmaComponents3.ToolButton {
				icon.name: "go-previous"
				display: QQC2.AbstractButton.IconOnly
				text: i18n("Back")
				onClicked: searchView.closeRequested()
				PlasmaComponents3.ToolTip.text: text
				PlasmaComponents3.ToolTip.visible: hovered
				PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
			}
			Kirigami.SearchField {
				id: searchField
				Layout.fillWidth: true
				placeholderText: i18n("Search events…")
				delaySearch: false
				autoAccept: false
				Keys.onEscapePressed: searchView.closeRequested()
				// Enter opens the first result.
				onAccepted: {
					if (searchView.results.length > 0) {
						searchView.eventClicked(searchView.results[0])
					}
				}
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
				id: resultsColumn
				width: scrollView.availableWidth
				spacing: 0

				PlasmaComponents3.Label {
					visible: searchView.results.length === 0
					Layout.fillWidth: true
					Layout.margins: Kirigami.Units.largeSpacing * 2
					horizontalAlignment: Text.AlignHCenter
					wrapMode: Text.Wrap
					opacity: 0.6
					text: {
						if (!searchView.query) {
							return i18n("Type to search event titles, places and descriptions")
						}
						if (searchView.searching || remoteTimer.running) {
							return i18n("Searching…")
						}
						return i18n("No events found")
					}
				}

				Repeater {
					model: searchView.results
					// Event tile in the event color (outlined, striped or struck through by the user's
					// answer), like the agenda.
					Rectangle {
						id: eventRow
						readonly property var eventItem: modelData
						readonly property EventStyle eventStyle: EventStyle {
							eventItem: eventRow.eventItem
						}
						readonly property color textColor: eventStyle.textColor
						readonly property bool past: eventItem.endDateTime < timeModel.currentTime
						Layout.fillWidth: true
						Layout.leftMargin: Kirigami.Units.largeSpacing
						Layout.rightMargin: Kirigami.Units.largeSpacing
						Layout.topMargin: index === 0 ? Kirigami.Units.largeSpacing : Kirigami.Units.smallSpacing
						implicitHeight: tileColumn.implicitHeight + Kirigami.Units.smallSpacing * 2 + 2
						radius: 8
						color: eventStyle.fillColor
						border.width: 1
						border.color: eventStyle.outlineColor
						opacity: (past ? 0.6 : 1) * (tileMouse.containsMouse ? 0.85 : 1)

						StripeFill {
							visible: eventRow.eventStyle.striped
							anchors.fill: parent
							anchors.margins: 1
							radius: eventRow.radius - 1
							stripeColor: eventRow.eventStyle.stripeColor
						}

						ColumnLayout {
							id: tileColumn
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
								font.strikeout: eventRow.eventStyle.declined
							}
							PlasmaComponents3.Label {
								Layout.fillWidth: true
								elide: Text.ElideRight
								text: {
									var parts = [searchView.whenText(eventRow.eventItem)]
									if (eventRow.eventItem.location) {
										parts.push(eventRow.eventItem.location)
									}
									return parts.join(' · ')
								}
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
									searchView.eventClicked(eventRow.eventItem)
								}
							}
						}
					}
				}

				// Google is still being searched, or couldn't be.
				RowLayout {
					visible: searchView.canSearchRemote && searchView.query.length >= 2 && searchView.results.length > 0
						&& (searchView.searching || remoteTimer.running || searchView.remoteFailed)
					Layout.alignment: Qt.AlignHCenter
					Layout.margins: Kirigami.Units.largeSpacing
					PlasmaComponents3.BusyIndicator {
						visible: !searchView.remoteFailed
						Layout.preferredWidth: Kirigami.Units.iconSizes.small
						Layout.preferredHeight: Kirigami.Units.iconSizes.small
						running: visible
					}
					PlasmaComponents3.Label {
						opacity: 0.6
						font: Kirigami.Theme.smallFont
						text: searchView.remoteFailed
							? i18n("Couldn't search Google Calendar")
							: i18n("Searching Google Calendar…")
					}
				}
			}
		}
	}
}
