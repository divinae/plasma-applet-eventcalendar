import QtQuick
import org.kde.kirigami as Kirigami

// A card centered over the dimmed popup content (event details, day list, event form).
// Clicking outside the card emits outsideClicked.
Item {
	id: overlay

	property Component cardComponent
	readonly property Item card: cardLoader.item
	signal outsideClicked()

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
		visible: !!cardLoader.item
		radius: Kirigami.Units.cornerRadius * 2
		color: "transparent"
		shadow.size: Kirigami.Units.gridUnit
		shadow.color: Qt.rgba(0, 0, 0, 0.25)
		shadow.yOffset: 2
	}
	Loader {
		id: cardLoader
		anchors.centerIn: parent
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
