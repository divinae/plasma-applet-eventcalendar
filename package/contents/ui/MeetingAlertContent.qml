import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "Shared.js" as Shared
import "LocaleFuncs.js" as LocaleFuncs

// What a full-screen meeting alert shows (Settings > Events > Full-screen alert): the screen in the
// theme's background, the meeting large in its middle (its calendar's color, title, time, where
// it's held) and Join, Snooze 1 min, Dismiss. Esc dismisses, Return joins. Shared by the plain and the layer-shell
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

	// The screen in the theme's background color (as Fokus' break overlay): nearly opaque, or
	// translucent over the blur a blurring window draws (backgroundOpacity 0: the window paints it).
	property real backgroundOpacity: 0.94
	Rectangle {
		anchors.fill: parent
		visible: content.backgroundOpacity > 0
		color: Qt.alpha(Kirigami.Theme.backgroundColor, content.backgroundOpacity)
	}

	// Centered and large: read from across the room.
	ColumnLayout {
		id: cardColumn
		anchors.centerIn: parent
		width: Math.min(parent.width - Kirigami.Units.gridUnit * 6, Kirigami.Units.gridUnit * 50)
		spacing: Kirigami.Units.largeSpacing

		// "Starting now", after a dot in the calendar's color.
		RowLayout {
			Layout.alignment: Qt.AlignHCenter
			spacing: Kirigami.Units.largeSpacing
			Rectangle {
				Layout.alignment: Qt.AlignVCenter
				implicitWidth: Math.round(startingLabel.font.pixelSize * 0.8)
				implicitHeight: implicitWidth
				radius: width / 2
				color: content.eventItem ? appletConfig.eventBarColor(appletConfig.eventColor(content.eventItem.backgroundColor)) : Kirigami.Theme.highlightColor
			}
			PlasmaComponents3.Label {
				id: startingLabel
				text: content.eventItem && content.eventItem.startDateTime > new Date() ? i18n("Starting soon") : i18n("Starting now")
				textFormat: Text.PlainText
				font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.6
				font.weight: Font.DemiBold
				opacity: 0.75
			}
		}
		PlasmaComponents3.Label {
			Layout.fillWidth: true
			horizontalAlignment: Text.AlignHCenter
			text: content.eventItem ? content.eventItem.summary || "" : ""
			textFormat: Text.PlainText // User text: never parsed as HTML
			font.pointSize: Kirigami.Theme.defaultFont.pointSize * 4
			font.weight: Font.Bold
			wrapMode: Text.Wrap
			maximumLineCount: 3
			elide: Text.ElideRight
		}
		PlasmaComponents3.Label {
			Layout.fillWidth: true
			horizontalAlignment: Text.AlignHCenter
			text: {
				var item = content.eventItem
				if (!item) {
					return ""
				}
				var range = Shared.formatTimeRange(item.startDateTime, item.endDateTime, appletConfig.timeFormat)
				return content.meetingLink && content.meetingLink.label ? range + " · " + content.meetingLink.label : range
			}
			textFormat: Text.PlainText
			font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.6
			opacity: 0.75
		}

		RowLayout {
			Layout.alignment: Qt.AlignHCenter
			Layout.topMargin: Kirigami.Units.gridUnit * 2
			spacing: Kirigami.Units.largeSpacing
			// Join: the accent button, the one Return presses.
			AlertButton {
				visible: !!content.meetingLink
				accent: true
				text: content.meetingLink && content.meetingLink.label ? i18nc("%1 = Google Meet, Zoom, ...", "Join %1", content.meetingLink.label) : i18n("Join")
				iconName: "call-start"
				onClicked: content.joinRequested()
			}
			AlertButton {
				text: i18n("Snooze 1 min")
				iconName: "player-time"
				onClicked: content.snoozeRequested()
			}
			AlertButton {
				text: i18n("Dismiss")
				iconName: "window-close-symbolic"
				onClicked: content.closeRequested()
			}
		}
		PlasmaComponents3.Label {
			Layout.alignment: Qt.AlignHCenter
			Layout.topMargin: Kirigami.Units.largeSpacing
			text: content.meetingLink ? i18n("Return: join · Esc: dismiss") : i18n("Esc: dismiss")
			textFormat: Text.PlainText
			opacity: 0.5
		}
	}

	// A large pill button: the accent color (Join) or a soft tint of the text color.
	component AlertButton: QQC2.AbstractButton {
		id: alertButton
		property bool accent: false
		property string iconName: ""
		readonly property color fg: accent ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
		Accessible.name: text
		hoverEnabled: true
		padding: Kirigami.Units.largeSpacing * 1.5
		leftPadding: Kirigami.Units.gridUnit * 1.5
		rightPadding: Kirigami.Units.gridUnit * 1.5
		background: Rectangle {
			radius: height / 2
			readonly property color base: alertButton.accent ? Kirigami.Theme.highlightColor : Qt.alpha(Kirigami.Theme.textColor, 0.08)
			color: alertButton.pressed ? Qt.darker(base, 1.15) : alertButton.hovered ? Qt.lighter(base, 1.08) : base
			border.width: alertButton.visualFocus ? 2 : 0
			border.color: Kirigami.Theme.focusColor
		}
		contentItem: RowLayout {
			spacing: Kirigami.Units.largeSpacing
			Kirigami.Icon {
				implicitWidth: Kirigami.Units.iconSizes.smallMedium
				implicitHeight: implicitWidth
				source: alertButton.iconName
				isMask: true
				color: alertButton.fg
			}
			PlasmaComponents3.Label {
				text: alertButton.text
				textFormat: Text.PlainText
				color: alertButton.fg
				font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.3
				font.weight: alertButton.accent ? Font.DemiBold : Font.Normal
			}
		}
	}
}
