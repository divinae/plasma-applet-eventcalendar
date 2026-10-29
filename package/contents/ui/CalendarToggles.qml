import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "Shared.js" as Shared

// Popup header button: the calendars selected in settings, with a checkbox each to show or hide
// them in the views (hiddenCalendarIds). A view filter: the selection in settings stays, the
// events are still fetched and their reminders still come.
PlasmaComponents3.ToolButton {
	id: calendarToggles

	readonly property var hiddenIds: plasmoid.configuration.hiddenCalendarIds || []
	readonly property var clockHiddenIds: plasmoid.configuration.clockHiddenCalendarIds || []
	property var calendars: [] // eventModel.getSelectedCalendars(), read when opened
	readonly property bool anyHidden: {
		for (var i = 0; i < calendars.length; i++) {
			if (Shared.isHiddenCalendar(calendars[i].id, hiddenIds)) {
				return true
			}
		}
		return false
	}

	icon.name: "view-calendar-list"
	down: pressed || calendarPopup.visible
	onClicked: {
		if (calendarPopup.visible) {
			calendarPopup.close()
		} else {
			open()
		}
	}
	PlasmaComponents3.ToolTip.text: i18n("Calendars")
	PlasmaComponents3.ToolTip.visible: hovered && !calendarPopup.visible
	Accessible.name: i18n("Calendars")

	// The item the list opens under: this button, or another one when it's hidden (the header's
	// menu of actions in a small popup).
	property Item anchorItem: calendarToggles
	function open(item) {
		anchorItem = item || calendarToggles
		calendars = eventModel.getSelectedCalendars()
		calendarPopup.open()
	}

	function toggledIds(currentIds, calendarId, hide) {
		return Shared.toggledCalendarIds(currentIds, calendarId, hide, calendars.map(function(calendar) { return calendar.id }))
	}
	function setHidden(calendarId, hide) {
		plasmoid.configuration.hiddenCalendarIds = toggledIds(hiddenIds, calendarId, hide)
	}
	// The next-event chip by the clock only; the views and reminders are unaffected.
	function setClockHidden(calendarId, hide) {
		plasmoid.configuration.clockHiddenCalendarIds = toggledIds(clockHiddenIds, calendarId, hide)
	}

	PlasmaComponents3.Popup {
		id: calendarPopup
		parent: calendarToggles.anchorItem
		x: calendarToggles.mirrored ? 0 : (parent ? parent.width : 0) - width
		y: parent ? parent.height : 0
		// Stays open while toggling several calendars; closes on a click outside or Escape.
		closePolicy: PlasmaComponents3.Popup.CloseOnEscape | PlasmaComponents3.Popup.CloseOnPressOutsideParent
		padding: Kirigami.Units.smallSpacing * 2

		// Solid, like the widget's other cards: the theme's translucent frame has no blur here, so
		// the views showed through it.
		background: Kirigami.ShadowedRectangle {
			color: Kirigami.Theme.backgroundColor
			radius: Kirigami.Units.cornerRadius * 2
			border.width: 1
			border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
			shadow.size: Kirigami.Units.gridUnit
			shadow.color: Qt.rgba(0, 0, 0, 0.25)
			shadow.yOffset: 2
		}

		contentItem: ColumnLayout {
			spacing: 0

			PlasmaComponents3.Label {
				visible: !calendarToggles.calendars.length
				Layout.margins: Kirigami.Units.smallSpacing
				text: i18n("No calendars selected in the settings.")
				opacity: 0.7
			}

			Repeater {
				model: calendarToggles.calendars
				ColumnLayout {
					id: calendarRow
					Layout.fillWidth: true
					spacing: 0
					readonly property bool groupStart: index === 0 || calendarToggles.calendars[index - 1].group !== modelData.group
					readonly property bool shown: !Shared.isHiddenCalendar(modelData.id, calendarToggles.hiddenIds)
					// The account's only calendar, named like it (a Google account's main calendar): no heading
					// that just repeats the name, a separator instead.
					readonly property bool headingRepeats: groupStart && modelData.name === modelData.group
						&& (index === calendarToggles.calendars.length - 1 || calendarToggles.calendars[index + 1].group !== modelData.group)

					// Account heading, when the calendars come from more than one place.
					PlasmaComponents3.Label {
						visible: calendarRow.groupStart && !!modelData.group && !calendarRow.headingRepeats
						Layout.fillWidth: true
						Layout.topMargin: index > 0 ? Kirigami.Units.smallSpacing : 0
						Layout.leftMargin: Kirigami.Units.smallSpacing
						text: modelData.group
						font.bold: true
						elide: Text.ElideRight
					}
					Kirigami.Separator {
						visible: calendarRow.groupStart && (!modelData.group || calendarRow.headingRepeats) && index > 0
						Layout.fillWidth: true
						Layout.topMargin: Kirigami.Units.smallSpacing
						Layout.bottomMargin: Kirigami.Units.smallSpacing
					}

					RowLayout {
						Layout.fillWidth: true
						Layout.maximumWidth: Kirigami.Units.gridUnit * 20
						spacing: Kirigami.Units.smallSpacing

						PlasmaComponents3.CheckBox {
							id: calendarCheck
							checked: calendarRow.shown
							onToggled: calendarToggles.setHidden(modelData.id, !checked)
							Accessible.name: modelData.name
						}
						Rectangle {
							implicitWidth: Kirigami.Units.iconSizes.small * 0.75
							implicitHeight: implicitWidth
							radius: width / 2
							color: modelData.color || Kirigami.Theme.highlightColor
							opacity: calendarRow.shown ? 1 : 0.4
						}
						PlasmaComponents3.Label {
							Layout.fillWidth: true
							text: modelData.name
							textFormat: Text.PlainText // User text: never parsed as HTML
							elide: Text.ElideRight
							opacity: calendarRow.shown ? 1 : 0.6
							MouseArea {
								anchors.fill: parent
								onClicked: calendarToggles.setHidden(modelData.id, calendarRow.shown)
							}
						}
						PlasmaComponents3.ToolButton {
							readonly property bool onClock: !Shared.isHiddenCalendar(modelData.id, calendarToggles.clockHiddenIds)
							visible: plasmoid.configuration.clockShowNextEvent
							icon.name: "clock"
							checkable: true
							checked: onClock
							opacity: onClock ? 1 : 0.4
							onToggled: {
								var calendarId = modelData.id
								calendarToggles.setClockHidden(calendarId, !checked)
								checked = Qt.binding(function() { return !Shared.isHiddenCalendar(calendarId, calendarToggles.clockHiddenIds) })
							}
							PlasmaComponents3.ToolTip.text: onClock
								? i18n("In the clock's countdown. Click to leave it out.")
								: i18n("Left out of the clock's countdown. Click to include it.")
							PlasmaComponents3.ToolTip.visible: hovered
							Accessible.name: i18nc("%1 = calendar name", "Include %1 in the clock's countdown", modelData.name)
						}
					}
				}
			}

			PlasmaComponents3.ToolButton {
				visible: calendarToggles.anyHidden
				Layout.topMargin: Kirigami.Units.smallSpacing
				Layout.alignment: Qt.AlignRight
				icon.name: "view-visible"
				text: i18n("Show All")
				onClicked: plasmoid.configuration.hiddenCalendarIds = []
			}
		}
	}
}
