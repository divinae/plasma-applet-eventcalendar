import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "Shared.js" as Shared
import "LocaleFuncs.js" as LocaleFuncs

// The notification when a meeting starts, full screen (Settings > Events > When an Event Starts >
// Style): the screen in the theme's background, the meeting large in its middle (its calendar's
// color, title, time, where it's held) and Join, Snooze 1 min, Dismiss. Esc dismisses, Return
// joins. Shared by the alert windows (plain, blurred, layer-shell), like the Fokus plasmoid's break
// overlay.
Item {
	id: content

	property var eventItem: null
	property var meetingLink: null // MeetingLink.find(eventItem), or null

	signal joinRequested()
	signal snoozeRequested()
	signal closeRequested()

	// Dark whatever the theme (Plasma's complementary colors: dark with light text), as Fokus'
	// dark overlay: a light screen over a blurred desktop was glaring.
	Kirigami.Theme.inherit: false
	Kirigami.Theme.colorSet: Kirigami.Theme.Complementary

	focus: true
	// The keys from the start, without a click first.
	Component.onCompleted: forceActiveFocus()
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
			// The calendar's color in a light ring: a dark calendar color still stands out on the dark
			// screen.
			Rectangle {
				Layout.alignment: Qt.AlignVCenter
				implicitWidth: Math.round(startingLabel.font.pixelSize * 1.1)
				implicitHeight: implicitWidth
				radius: width / 2
				color: content.eventItem ? appletConfig.eventColor(content.eventItem.backgroundColor) : Kirigami.Theme.highlightColor
				border.width: Math.max(2, Math.round(width / 7))
				border.color: Qt.alpha(Kirigami.Theme.textColor, 0.85)
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

		// The camera check before you join (Settings > Events > Full Screen > Camera check): the
		// camera as a mirror, for a meeting with a link, on the first screen only (a camera serves
		// one window), while the alert is shown; "Microphone and speaker" adds the camera's choice,
		// the microphone's level, sensitivity and "hear yourself", the speaker and its test (the
		// microphone is used only then). CameraMirror.qml, MicMeter.qml, loaded by URL: they need
		// Qt Multimedia (the sound part plasma-pa).
		ColumnLayout {
			id: cameraCheck
			readonly property bool wanted: plasmoid.configuration.meetingAlertCamera && !!content.meetingLink
				&& root.cameraCheckAvailable && Qt.application.screens.length > 0 && Screen.name === Qt.application.screens[0].name
			readonly property bool soundAvailable: wanted && root.moduleAvailable("PlasmaPaProbe.qml")
			property bool expanded: false
			readonly property real pictureWidth: Kirigami.Units.gridUnit * 12
			visible: wanted
			Layout.alignment: Qt.AlignHCenter
			Layout.topMargin: Kirigami.Units.gridUnit
			spacing: Kirigami.Units.largeSpacing

			// Expanded: the controls on a card in the window's colors (the lists and sliders draw
			// light frames: on the alert's dark colors their text didn't read). Collapsed: the
			// picture alone, no card.
			Rectangle {
				id: cameraCard
				readonly property real pad: cameraCheck.expanded ? Kirigami.Units.largeSpacing * 1.5 : 0
				Layout.alignment: Qt.AlignHCenter
				Layout.preferredWidth: (cameraCheck.expanded ? Kirigami.Units.gridUnit * 24 : cameraCheck.pictureWidth) + pad * 2
				Layout.preferredHeight: cameraCardColumn.implicitHeight + pad * 2
				radius: Kirigami.Units.cornerRadius * 3
				Kirigami.Theme.inherit: false
				Kirigami.Theme.colorSet: Kirigami.Theme.Window
				color: cameraCheck.expanded ? Kirigami.Theme.backgroundColor : "transparent"
				ColumnLayout {
					id: cameraCardColumn
					anchors.fill: parent
					anchors.margins: cameraCard.pad
					spacing: Kirigami.Units.largeSpacing
					Loader {
						Layout.fillWidth: true
						active: cameraCheck.wanted
						source: "CameraMirror.qml"
						onLoaded: {
							item.pictureMaxWidth = Qt.binding(function() { return cameraCheck.pictureWidth })
							item.running = Qt.binding(function() { return content.visible })
							item.showControls = Qt.binding(function() { return cameraCheck.expanded })
						}
					}
					Loader {
						Layout.fillWidth: true
						active: cameraCheck.expanded && cameraCheck.soundAvailable
						source: "MicMeter.qml"
						onLoaded: item.running = Qt.binding(function() { return content.visible })
					}
				}
			}
			AlertButton {
				Layout.alignment: Qt.AlignHCenter
				compact: true
				iconName: cameraCheck.expanded ? "go-up-symbolic" : "audio-input-microphone-symbolic"
				text: cameraCheck.expanded ? i18n("Show Less")
					: cameraCheck.soundAvailable ? i18n("Microphone and Speaker…") : i18n("Choose the Camera…")
				onClicked: {
					cameraCheck.expanded = !cameraCheck.expanded
					content.forceActiveFocus() // Esc and Return stay the alert's
				}
			}
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
		// A smaller one (the camera check's "Microphone and Speaker…"), below the main buttons.
		property bool compact: false
		property string iconName: ""
		readonly property color fg: accent ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
		Accessible.name: text
		hoverEnabled: true
		padding: compact ? Kirigami.Units.smallSpacing * 1.5 : Kirigami.Units.largeSpacing * 1.5
		leftPadding: compact ? Kirigami.Units.gridUnit : Kirigami.Units.gridUnit * 1.5
		rightPadding: compact ? Kirigami.Units.gridUnit : Kirigami.Units.gridUnit * 1.5
		background: Rectangle {
			radius: height / 2
			// The accent one darker / lighter; the others a stronger tint (lighter() does nothing to a
			// light, translucent tint).
			color: alertButton.accent
				? (alertButton.pressed ? Qt.darker(Kirigami.Theme.highlightColor, 1.15)
					: alertButton.hovered ? Qt.lighter(Kirigami.Theme.highlightColor, 1.12) : Kirigami.Theme.highlightColor)
				: Qt.alpha(Kirigami.Theme.textColor, alertButton.pressed ? 0.28 : alertButton.hovered ? 0.18 : 0.08)
			Behavior on color {
				ColorAnimation { duration: Kirigami.Units.shortDuration }
			}
			border.width: alertButton.visualFocus ? 2 : 0
			border.color: Kirigami.Theme.focusColor
		}
		contentItem: RowLayout {
			spacing: Kirigami.Units.largeSpacing
			Kirigami.Icon {
				implicitWidth: alertButton.compact ? Kirigami.Units.iconSizes.small : Kirigami.Units.iconSizes.smallMedium
				implicitHeight: implicitWidth
				source: alertButton.iconName
				isMask: true
				color: alertButton.fg
			}
			PlasmaComponents3.Label {
				text: alertButton.text
				textFormat: Text.PlainText
				color: alertButton.fg
				font.pointSize: Kirigami.Theme.defaultFont.pointSize * (alertButton.compact ? 1 : 1.3)
				font.weight: alertButton.accent ? Font.DemiBold : Font.Normal
			}
		}
	}
}
