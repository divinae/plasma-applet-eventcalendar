import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

// The top row of an overlay card: Cancel (back) on the left, the title centered, the card's
// action (Add, Import, Save) on the right.
Item {
	id: cardHeader

	property alias title: titleLabel.text
	property alias cancelText: cancelButton.text
	property alias actionText: actionButton.text
	property alias actionIcon: actionButton.icon.name
	property alias actionEnabled: actionButton.enabled
	signal cancelClicked()
	signal actionClicked()

	implicitHeight: Math.max(cancelButton.implicitHeight, actionButton.implicitHeight, titleLabel.implicitHeight)

	PlasmaComponents3.ToolButton {
		id: cancelButton
		anchors.left: parent.left
		anchors.verticalCenter: parent.verticalCenter
		icon.name: "go-previous"
		text: i18n("Cancel")
		onClicked: cardHeader.cancelClicked()
	}
	Kirigami.Heading {
		id: titleLabel
		anchors.centerIn: parent
		width: Math.min(implicitWidth, parent.width - Math.max(cancelButton.width, actionButton.width) * 2 - Kirigami.Units.largeSpacing * 2)
		horizontalAlignment: Text.AlignHCenter
		level: 3
		elide: Text.ElideRight
	}
	PlasmaComponents3.Button {
		id: actionButton
		anchors.right: parent.right
		anchors.verticalCenter: parent.verticalCenter
		onClicked: cardHeader.actionClicked()
	}
}
