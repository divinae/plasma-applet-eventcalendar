import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "LocaleFuncs.js" as LocaleFuncs
import "EventSearch.js" as EventSearch
import "Tasks.js" as Tasks

// Search events by title, location and description: the loaded events right away, then Google
// Calendar a year back and ahead (the server also matches guests and other fields). The loaded
// tasks that match (title, notes) come first, as task rows (a click opens the task).
Item {
	id: searchView

	signal closeRequested()
	signal eventClicked(var eventItem)

	property alias searchText: searchField.text
	readonly property string query: searchField.text.trim()
	readonly property int remoteRangeDays: 365
	readonly property int resultLimit: 100
	// The tiles built: the first 30, more on "Show more" (each key typed rebuilt up to 100).
	property int shownResults: 30
	readonly property var shownResultList: results.slice(0, shownResults)

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
	readonly property int taskLimit: 30
	readonly property var taskResults: {
		var _ = eventModel.eventsData // Search again when events are refetched.
		var items = eventModel.eventsData ? eventModel.eventsData.items : []
		return EventSearch.searchTasks(items, query, taskLimit)
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

	// With a query the card takes the available height, so it doesn't jump while results come in.
	implicitHeight: actionsRow.implicitHeight + Kirigami.Units.smallSpacing * 2
		+ (query ? Kirigami.Units.gridUnit * 40 : resultsColumn.implicitHeight + Kirigami.Units.largeSpacing)

	onQueryChanged: {
		shownResults = 30
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

	// "Fri 23 Oct · 12:30 – 13:30", "Fri 23 Oct · All day", or a span of days.
	function whenText(e) {
		return LocaleFuncs.formatWhen(e, appletConfig.timeFormat, timeModel.currentTime)
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
				placeholderText: i18n("Search events and tasks…")
				delaySearch: false
				autoAccept: false
				Keys.onEscapePressed: searchView.closeRequested()
				// Enter opens the first result (a task first).
				onAccepted: {
					if (searchView.taskResults.length > 0) {
						popup.activateEvent(searchView.taskResults[0])
					} else if (searchView.results.length > 0) {
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
			QQC2.ScrollBar.vertical: OverlayScrollBar {
				view: scrollView
			}

			ColumnLayout {
				id: resultsColumn
				width: scrollView.availableWidth
				spacing: 0

				PlasmaComponents3.Label {
					visible: searchView.results.length === 0 && searchView.taskResults.length === 0
					Layout.fillWidth: true
					Layout.margins: Kirigami.Units.largeSpacing * 2
					horizontalAlignment: Text.AlignHCenter
					wrapMode: Text.Wrap
					opacity: 0.6
					text: {
						if (!searchView.query) {
							return i18n("Type to search events and tasks")
						}
						if (searchView.searching || remoteTimer.running) {
							return i18n("Searching…")
						}
						return i18n("No events found")
					}
				}

				// Tasks: a heading, then the rows (like the Tasks tab's).
				PlasmaComponents3.Label {
					visible: searchView.taskResults.length > 0
					Layout.fillWidth: true
					Layout.leftMargin: Kirigami.Units.largeSpacing * 2
					Layout.rightMargin: Kirigami.Units.largeSpacing
					Layout.topMargin: Kirigami.Units.largeSpacing
					text: i18n("Tasks")
					textFormat: Text.PlainText
					font.weight: Font.DemiBold
					opacity: 0.85
				}
				Repeater {
					model: searchView.taskResults
					TaskRow {
						Layout.fillWidth: true
						Layout.leftMargin: Kirigami.Units.smallSpacing
						Layout.rightMargin: Kirigami.Units.smallSpacing
						eventItem: modelData
						today: Tasks.dayString(timeModel.currentTime)
						showNotes: true
					}
				}
				PlasmaComponents3.Label {
					visible: searchView.taskResults.length > 0 && searchView.results.length > 0
					Layout.fillWidth: true
					Layout.leftMargin: Kirigami.Units.largeSpacing * 2
					Layout.rightMargin: Kirigami.Units.largeSpacing
					Layout.topMargin: Kirigami.Units.largeSpacing
					text: i18n("Events")
					textFormat: Text.PlainText
					font.weight: Font.DemiBold
					opacity: 0.85
				}

				Repeater {
					model: searchView.shownResultList
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
						border.color: eventStyle.showBar ? "transparent" : eventStyle.outlineColor // ColorBarFill draws it
						opacity: (past ? 0.6 : 1) * (tileMouse.containsMouse ? 0.85 : 1)

						ColorBarFill {
							visible: eventRow.eventStyle.showBar // "Bar" event look
							barColor: eventRow.eventStyle.barColor
							outlined: eventRow.eventStyle.unconfirmed
							fillColor: eventRow.eventStyle.fillColor
							borderColor: eventRow.eventStyle.outlineColor
							topLeftRadius: eventRow.radius
							bottomLeftRadius: eventRow.radius
							topRightRadius: eventRow.radius
							bottomRightRadius: eventRow.radius
						}
						StripeFill {
							visible: eventRow.eventStyle.striped
							anchors.fill: parent
							anchors.margins: 1
							anchors.leftMargin: eventRow.eventStyle.showBar ? 5 : 1
							radius: eventRow.radius - 1
							stripeColor: eventRow.eventStyle.stripeColor
						}

						ColumnLayout {
							id: tileColumn
							anchors.left: parent.left
							anchors.right: parent.right
							anchors.verticalCenter: parent.verticalCenter
							anchors.leftMargin: Kirigami.Units.largeSpacing + (eventRow.eventStyle.showBar ? 4 : 0)
							anchors.rightMargin: Kirigami.Units.largeSpacing
							spacing: 1
							PlasmaComponents3.Label {
								Layout.fillWidth: true
								wrapMode: Text.Wrap
								text: eventRow.eventItem.summary
								textFormat: Text.PlainText // User text: never parsed as HTML
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

				PlasmaComponents3.ToolButton {
					visible: searchView.results.length > searchView.shownResults
					Layout.alignment: Qt.AlignHCenter
					Layout.topMargin: Kirigami.Units.smallSpacing
					icon.name: "arrow-down"
					text: i18n("Show more")
					onClicked: searchView.shownResults += 30
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
