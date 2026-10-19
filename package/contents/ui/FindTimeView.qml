import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "FreeSlots.js" as FreeSlots
import "LocaleFuncs.js" as LocaleFuncs
import "Shared.js" as Shared
import "TimeZone.js" as TimeZone
import "lib/ColorUtil.js" as ColorUtil

// Find a time (in the event editor): the busy times of you and the guests on a day, within the
// working hours (settings), from Google's freeBusy, and free slots for the event's length. The day,
// the working hours and the times shown are in the editor's time zone.
Rectangle {
	id: findTime

	property string calendarId: "" // Any calendar of the Google account
	property var people: [] // [{ id: a calendar id (email), name, email (guests) }]
	property string timeZone: "" // The editor's zone ('' or unknown: local time)
	property date day: new Date() // The day: its local date fields are the date in timeZone
	property double duration: 3600000 // The event's length, ms
	property double selectedStart: 0 // The event's start, ms (outlined)
	signal slotPicked(double start)
	signal closeRequested()

	readonly property int startHour: plasmoid.configuration.weekViewStartHour
	readonly property int endHour: Math.max(startHour + 1, plasmoid.configuration.weekViewEndHour)
	readonly property bool zoned: TimeZone.knows(timeZone)
	readonly property double rangeStart: instantAt(day, startHour)
	readonly property double rangeEnd: instantAt(day, endHour)
	// Slots every 30 minutes, or 15 for short events.
	readonly property double step: duration < 30 * 60000 ? 15 * 60000 : 30 * 60000

	property bool loading: false
	property string error: ""
	property var results: ({}) // id -> { busy: [{ start, end }], error }
	property int requestId: 0

	readonly property bool loaded: !loading && !error
	// The people whose busy times we don't have (their calendar isn't shared, unknown...): the
	// suggestions don't count them, and say so.
	readonly property var notCounted: {
		if (!loaded) {
			return []
		}
		return people.filter(function(person) {
			var result = results[person.id]
			return !result || !!result.error
		}).map(function(person) { return person.name })
	}
	// Suggestions only when we know the busy times of at least one guest (people[0] is you).
	readonly property bool hasGuestData: {
		for (var i = 1; i < people.length; i++) {
			var result = results[people[i].id]
			if (result && !result.error) {
				return true
			}
		}
		return false
	}
	readonly property var suggestions: {
		if (!loaded || !hasGuestData) {
			return []
		}
		var lists = []
		for (var i = 0; i < people.length; i++) {
			var result = results[people[i].id]
			if (result && !result.error) {
				lists.push(result.busy)
			}
		}
		return FreeSlots.freeSlots(lists, rangeStart, rangeEnd, duration, step, Date.now(), 8)
	}
	readonly property string suggestionsText: {
		var names = notCounted.join(i18nc("separator of names in a list", ", "))
		if (!hasGuestData) {
			return i18n("No suggestions: the guests' busy times aren't available.")
		} else if (suggestions.length) {
			return names
				? i18nc("%1 = names of people", "Suggested times (not counting %1):", names)
				: i18n("Suggested times:")
		}
		return names
			? i18nc("%1 = names of people", "No time free in the working hours of this day (not counting %1).", names)
			: i18n("No time free for everyone in the working hours of this day.")
	}

	color: Kirigami.Theme.backgroundColor
	radius: Kirigami.Units.cornerRadius * 2
	border.width: 1
	border.color: ColorUtil.setAlpha(Kirigami.Theme.textColor, 0.15)
	implicitHeight: content.implicitHeight + Kirigami.Units.largeSpacing * 2

	function fetch() {
		var ids = people.map(function(person) { return person.id })
		var id = ++requestId
		loading = true
		error = ""
		results = ({})
		eventModel.freeBusy(calendarId, ids, new Date(rangeStart), new Date(rangeEnd), function(err, data) {
			if (id !== findTime.requestId) {
				return // Another day was asked for since
			}
			loading = false
			if (err) {
				error = String(err)
				return
			}
			results = FreeSlots.parseResponse(data, ids)
		})
	}
	// The instant of `hour`:00 on the date of `wallDay` in the zone.
	function instantAt(wallDay, hour) {
		var y = wallDay.getFullYear()
		var m = wallDay.getMonth()
		var d = wallDay.getDate()
		return zoned ? TimeZone.toUtc(timeZone, y, m, d, hour, 0, 0) : new Date(y, m, d, hour).getTime()
	}
	// Where `hour`:00 of the day is in the range (0..1), by its real instant like the busy blocks:
	// a daylight saving day has an hour more or less. -1 for an hour the day doesn't have (spring
	// forward).
	function hourPosition(hour) {
		var at = instantAt(day, hour)
		var wall = zoned ? TimeZone.wallClock(timeZone, at) : null
		if ((wall ? wall.hours : new Date(at).getHours()) !== hour % 24) {
			return -1
		}
		return (at - rangeStart) / (rangeEnd - rangeStart)
	}
	function shiftDay(days) {
		day = new Date(day.getFullYear(), day.getMonth(), day.getDate() + days, 12)
		fetch()
	}
	// An instant's clock time in the zone.
	function timeText(ms) {
		var wall = zoned ? TimeZone.wallClock(timeZone, ms) : null
		var d = wall ? new Date(2000, 0, 1, wall.hours, wall.minutes) : new Date(ms)
		return LocaleFuncs.formatEventTime(d, { clock24h: appletConfig.clock24h })
	}
	function errorText(reason) {
		return reason === 'notFound' || reason === 'notFoundOrNoAccess'
			? i18nc("someone's calendar in Find a time", "Not available")
			: i18nc("someone's calendar in Find a time: %1 = Google's reason", "Not available (%1)", reason)
	}

	Component.onCompleted: {
		fetch()
		forceActiveFocus()
	}
	Keys.onEscapePressed: closeRequested()
	Keys.onLeftPressed: shiftDay(-1)
	Keys.onRightPressed: shiftDay(1)

	// Clicks on the card stay in it (the editor closes the card on clicks around it) and give the
	// keys back to it.
	MouseArea {
		anchors.fill: parent
		acceptedButtons: Qt.AllButtons
		onPressed: findTime.forceActiveFocus()
	}

	ColumnLayout {
		id: content
		anchors.fill: parent
		anchors.margins: Kirigami.Units.largeSpacing
		spacing: Kirigami.Units.largeSpacing

		RowLayout {
			Layout.fillWidth: true
			PlasmaComponents3.ToolButton {
				icon.name: "go-previous"
				text: i18n("Back")
				onClicked: findTime.closeRequested()
			}
			Kirigami.Heading {
				Layout.fillWidth: true
				level: 3
				elide: Text.ElideRight
				horizontalAlignment: Text.AlignHCenter
				text: i18n("Find a Time")
			}
			PlasmaComponents3.ToolButton {
				icon.name: "go-previous-symbolic"
				display: QQC2.AbstractButton.IconOnly
				text: i18n("Previous day")
				onClicked: findTime.shiftDay(-1)
				PlasmaComponents3.ToolTip.text: text
				PlasmaComponents3.ToolTip.visible: hovered
				PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
			}
			PlasmaComponents3.Label {
				text: Qt.formatDate(findTime.day, i18nc("Find a time: the day shown", "ddd, d MMM"))
			}
			PlasmaComponents3.ToolButton {
				icon.name: "go-next-symbolic"
				display: QQC2.AbstractButton.IconOnly
				text: i18n("Next day")
				onClicked: findTime.shiftDay(1)
				PlasmaComponents3.ToolTip.text: text
				PlasmaComponents3.ToolTip.visible: hovered
				PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
			}
		}

		// People's busy times over the working hours.
		ColumnLayout {
			id: grid
			Layout.fillWidth: true
			spacing: Kirigami.Units.smallSpacing
			readonly property int nameWidth: Math.min(Kirigami.Units.gridUnit * 8, findTime.width / 3)
			readonly property int stripHeight: Math.round(Kirigami.Units.gridUnit * 1.4)

			// Hour scale
			Item {
				Layout.fillWidth: true
				Layout.preferredHeight: hourMetrics.height
				Item {
					id: hourScale
					x: grid.nameWidth + grid.spacing
					width: parent.width - x
					height: parent.height
					FontMetrics {
						id: hourMetrics
						font: Kirigami.Theme.smallFont
					}
					Repeater {
						model: findTime.endHour - findTime.startHour + 1
						PlasmaComponents3.Label {
							readonly property int hour: findTime.startHour + index
							readonly property int every: findTime.endHour - findTime.startHour > 12 ? 2 : 1
							readonly property double position: findTime.hourPosition(hour)
							visible: (hour - findTime.startHour) % every === 0 && position >= 0
							x: Math.max(0, Math.min(hourScale.width - width, position * hourScale.width - width / 2))
							font: Kirigami.Theme.smallFont
							opacity: 0.6
							text: Qt.formatTime(new Date(2000, 0, 1, hour), appletConfig.clock24h ? "HH" : "h AP")
						}
					}
				}
			}

			Repeater {
				model: findTime.people
				delegate: RowLayout {
					id: personRow
					required property var modelData
					readonly property var result: findTime.results[modelData.id] || null
					Layout.fillWidth: true
					spacing: Kirigami.Units.smallSpacing

					PlasmaComponents3.Label {
						Layout.preferredWidth: grid.nameWidth
						Layout.preferredHeight: grid.stripHeight
						verticalAlignment: Text.AlignVCenter
						elide: Text.ElideRight
						text: personRow.modelData.name
						PlasmaComponents3.ToolTip.text: personRow.modelData.email || ""
						PlasmaComponents3.ToolTip.visible: nameHover.hovered && !!personRow.modelData.email
						HoverHandler {
							id: nameHover
						}
					}
					Rectangle {
						id: strip
						Layout.fillWidth: true
						Layout.preferredHeight: grid.stripHeight
						radius: Kirigami.Units.cornerRadius
						color: ColorUtil.setAlpha(Kirigami.Theme.textColor, 0.06)
						clip: true

						// Hour lines
						Repeater {
							model: findTime.endHour - findTime.startHour - 1
							Rectangle {
								readonly property double position: findTime.hourPosition(findTime.startHour + index + 1)
								visible: position >= 0
								x: position * strip.width
								width: 1
								height: strip.height
								color: ColorUtil.setAlpha(Kirigami.Theme.textColor, 0.08)
							}
						}
						Repeater {
							model: personRow.result && !personRow.result.error ? FreeSlots.blocks(personRow.result.busy, findTime.rangeStart, findTime.rangeEnd) : []
							Rectangle {
								x: modelData.x * strip.width
								width: Math.max(2, modelData.width * strip.width)
								height: strip.height
								radius: Kirigami.Units.cornerRadius
								color: Kirigami.Theme.highlightColor
								opacity: 0.75
							}
						}
						// The event's time
						Rectangle {
							readonly property var block: FreeSlots.blocks([{ start: findTime.selectedStart, end: findTime.selectedStart + findTime.duration }], findTime.rangeStart, findTime.rangeEnd)[0]
							visible: !!block
							x: block ? block.x * strip.width : 0
							width: block ? Math.max(2, block.width * strip.width) : 0
							height: strip.height
							radius: Kirigami.Units.cornerRadius
							color: "transparent"
							border.width: 2
							border.color: Kirigami.Theme.positiveTextColor
						}
						PlasmaComponents3.Label {
							visible: !!personRow.result && personRow.result.error !== ""
							anchors.centerIn: parent
							width: Math.min(implicitWidth, parent.width)
							elide: Text.ElideRight
							font: Kirigami.Theme.smallFont
							opacity: 0.7
							text: personRow.result && personRow.result.error ? findTime.errorText(personRow.result.error) : ""
						}
					}
				}
			}
		}

		PlasmaComponents3.BusyIndicator {
			visible: findTime.loading
			running: visible
			Layout.alignment: Qt.AlignHCenter
		}
		PlasmaComponents3.Label {
			visible: findTime.error !== ""
			Layout.fillWidth: true
			wrapMode: Text.Wrap
			color: Kirigami.Theme.negativeTextColor
			text: findTime.error
		}

		// Free for everyone (we know the busy times of)
		PlasmaComponents3.Label {
			visible: findTime.loaded
			Layout.fillWidth: true
			wrapMode: Text.Wrap
			text: findTime.suggestionsText
			opacity: findTime.suggestions.length ? 1 : 0.7
		}
		Flow {
			visible: findTime.suggestions.length > 0
			Layout.fillWidth: true
			spacing: Kirigami.Units.smallSpacing
			Repeater {
				model: findTime.suggestions
				PlasmaComponents3.Button {
					text: findTime.timeText(modelData.start) + " – " + findTime.timeText(modelData.end)
					onClicked: findTime.slotPicked(modelData.start)
				}
			}
		}
	}
}
