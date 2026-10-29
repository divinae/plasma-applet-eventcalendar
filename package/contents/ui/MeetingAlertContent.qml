import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "Shared.js" as Shared
import "LocaleFuncs.js" as LocaleFuncs

// What a full-screen meeting alert shows (Settings > Events > Full-screen alert): a dimmed screen
// and a card with the meeting (its calendar's color, title, time, where it's held) and Join,
// Snooze 1 min, Dismiss. Esc dismisses, Return joins. Shared by the plain and the layer-shell
// window (MeetingAlertWindow, MeetingAlertLayer), like the Fokus plasmoid's break overlay.
Item {
	id: content

	property var eventItem: null
	property var meetingLink: null // MeetingLink.find(eventItem), or null

	signal joinRequested()
	signal snoozeRequested()
	signal closeRequested()

	focus: true
	Keys.onEscapePressed: content.closeRequested()
	Keys.onReturnPressed: content.meetingLink ? content.joinRequested() : content.closeRequested()
	Keys.onEnterPressed: content.meetingLink ? content.joinRequested() : content.closeRequested()

	// A click beside the card does nothing (it's not a dismissal by mistake).
	MouseArea {
		anchors.fill: parent
		onClicked: content.forceActiveFocus()
	}

	Rectangle {
		id: card
		anchors.centerIn: parent
		width: Math.min(parent.width - Kirigami.Units.gridUnit * 4, Kirigami.Units.gridUnit * 30)
		height: cardColumn.implicitHeight + Kirigami.Units.gridUnit * 4
		radius: Kirigami.Units.cornerRadius * 3
		color: Kirigami.Theme.backgroundColor
		border.width: 1
		border.color: Qt.alpha(Kirigami.Theme.textColor, 0.15)

		// The calendar's color along the left edge.
		Rectangle {
			anchors.left: parent.left
			anchors.top: parent.top
			anchors.bottom: parent.bottom
			anchors.margins: Kirigami.Units.gridUnit
			width: 5
			radius: 2.5
			color: content.eventItem ? appletConfig.eventBarColor(appletConfig.eventColor(content.eventItem.backgroundColor)) : Kirigami.Theme.highlightColor
		}

		ColumnLayout {
			id: cardColumn
			anchors.left: parent.left
			anchors.right: parent.right
			anchors.verticalCenter: parent.verticalCenter
			anchors.leftMargin: Kirigami.Units.gridUnit * 2
			anchors.rightMargin: Kirigami.Units.gridUnit * 1.5
			spacing: Kirigami.Units.smallSpacing

			PlasmaComponents3.Label {
				Layout.fillWidth: true
				text: content.eventItem && content.eventItem.startDateTime > new Date() ? i18n("Starting soon") : i18n("Starting now")
				textFormat: Text.PlainText
				color: Kirigami.Theme.highlightColor
				font.weight: Font.DemiBold
			}
			Kirigami.Heading {
				Layout.fillWidth: true
				level: 1
				font.pointSize: Kirigami.Theme.defaultFont.pointSize * 2
				text: content.eventItem ? content.eventItem.summary || "" : ""
				textFormat: Text.PlainText // User text: never parsed as HTML
				wrapMode: Text.Wrap
				maximumLineCount: 3
				elide: Text.ElideRight
			}
			PlasmaComponents3.Label {
				Layout.fillWidth: true
				text: {
					var item = content.eventItem
					if (!item) {
						return ""
					}
					var range = Shared.formatTimeRange(item.startDateTime, item.endDateTime, appletConfig.timeFormat)
					return content.meetingLink && content.meetingLink.label ? range + " · " + content.meetingLink.label : range
				}
				textFormat: Text.PlainText
				opacity: 0.85
			}

			RowLayout {
				Layout.topMargin: Kirigami.Units.gridUnit
				spacing: Kirigami.Units.smallSpacing
				// Join: the accent button, the one Return presses.
				QQC2.AbstractButton {
					id: joinButton
					visible: !!content.meetingLink
					text: content.meetingLink && content.meetingLink.label ? i18nc("%1 = Google Meet, Zoom, ...", "Join %1", content.meetingLink.label) : i18n("Join")
					Accessible.name: text
					hoverEnabled: true
					padding: Kirigami.Units.largeSpacing
					leftPadding: Kirigami.Units.gridUnit
					rightPadding: Kirigami.Units.gridUnit
					onClicked: content.joinRequested()
					background: Rectangle {
						radius: Kirigami.Units.cornerRadius * 2
						color: joinButton.pressed ? Qt.darker(Kirigami.Theme.highlightColor, 1.15)
							: joinButton.hovered ? Qt.lighter(Kirigami.Theme.highlightColor, 1.08) : Kirigami.Theme.highlightColor
					}
					contentItem: RowLayout {
						spacing: Kirigami.Units.smallSpacing
						Kirigami.Icon {
							implicitWidth: Kirigami.Units.iconSizes.small
							implicitHeight: implicitWidth
							source: "call-start"
							isMask: true
							color: Kirigami.Theme.highlightedTextColor
						}
						PlasmaComponents3.Label {
							text: joinButton.text
							textFormat: Text.PlainText
							color: Kirigami.Theme.highlightedTextColor
							font.weight: Font.DemiBold
						}
					}
				}
				PlasmaComponents3.Button {
					text: i18n("Snooze 1 min")
					icon.name: "player-time"
					onClicked: content.snoozeRequested()
				}
				PlasmaComponents3.Button {
					text: i18n("Dismiss")
					icon.name: "dialog-close"
					onClicked: content.closeRequested()
				}
			}
		}
	}
}
