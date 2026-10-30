import QtQuick
import org.kde.kirigami as Kirigami

import "lib/ColorUtil.js" as ColorUtil

// A card centered over the dimmed popup content (search, event details, quick add, import, event form).
// Clicking outside the card emits outsideClicked. The card frame (background, rounded border) is drawn
// here; framed: false for cards that still draw their own.
Item {
	id: overlay

	property Component cardComponent
	property bool framed: true
	// Shown while open, and while it fades out after closing.
	property bool open: false
	visible: open || closeAnimation.running
	readonly property Item card: cardLoader.item
	signal outsideClicked()

	// Opening: the overlay fades in and the card grows into place from a little smaller.
	Scale {
		id: cardScale
		origin.x: cardLoader.width / 2
		origin.y: cardLoader.height / 2
	}
	ParallelAnimation {
		id: openAnimation
		NumberAnimation { target: overlay; property: "opacity"; from: 0; to: 1; duration: appletConfig.shortDuration; easing.type: Easing.OutCubic }
		NumberAnimation { target: cardScale; property: "xScale"; from: 0.96; to: 1; duration: appletConfig.longDuration; easing.type: Easing.OutCubic }
		NumberAnimation { target: cardScale; property: "yScale"; from: 0.96; to: 1; duration: appletConfig.longDuration; easing.type: Easing.OutCubic }
	}
	onOpenChanged: {
		if (open) {
			closeAnimation.stop()
			if (appletConfig.animations) {
				openAnimation.restart()
			} else {
				overlay.opacity = 1
			}
		} else if (appletConfig.animations) {
			openAnimation.stop()
			closeAnimation.restart()
		}
	}
	// Closing: a short fade out (the card keeps what it showed meanwhile, see PopupView's held values).
	NumberAnimation {
		id: closeAnimation
		target: overlay
		property: "opacity"
		to: 0
		duration: appletConfig.shortDuration
		easing.type: Easing.InCubic
	}

	// Strong backdrop so the card doesn't blend into the view behind it.
	Rectangle {
		anchors.fill: parent
		color: Kirigami.Theme.backgroundColor
		opacity: 0.85
	}
	MouseArea {
		anchors.fill: parent
		onClicked: overlay.outsideClicked()
	}
	Kirigami.ShadowedRectangle {
		anchors.fill: cardLoader
		transform: cardScale
		visible: !!cardLoader.item
		radius: Kirigami.Units.cornerRadius * 2
		color: "transparent"
		shadow.size: Kirigami.Units.gridUnit
		shadow.color: Qt.rgba(0, 0, 0, 0.25)
		shadow.yOffset: 2
	}
	Rectangle {
		anchors.fill: cardLoader
		transform: cardScale
		visible: overlay.framed && !!cardLoader.item
		color: Kirigami.Theme.backgroundColor
		radius: Kirigami.Units.cornerRadius * 2
		border.width: 1
		border.color: ColorUtil.setAlpha(Kirigami.Theme.textColor, 0.15)
	}
	Loader {
		id: cardLoader
		anchors.centerIn: parent
		transform: cardScale
		width: Math.min(Kirigami.Units.gridUnit * 30, overlay.width - Kirigami.Units.gridUnit * 2)
		height: item ? Math.min(item.implicitHeight, overlay.height - Kirigami.Units.gridUnit * 2) : 0
		sourceComponent: overlay.cardComponent
	}

	// Give keyboard focus (Esc) back to the card, eg: after a card above it closes.
	function focusCard() {
		if (card) {
			card.forceActiveFocus()
		}
	}
}
