import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

// A menu item showing user text (a list, account or task name): set label, not text. Shown as
// plain text (never HTML), and a "&" in it is a "&", not a mnemonic.
// Laid out like Plasma's MenuItem: the check's room, the icon, the text.
PlasmaComponents3.MenuItem {
	id: plainItem

	property string label: ""
	// A task list: its mark (ListMark: its emoji or a dot in markColor) in the icon's place.
	property var list: null
	property color markColor: "transparent"

	text: label.replace(/&/g, "&&") // Escaped: no mnemonic from the user's "&"
	Accessible.name: label

	contentItem: RowLayout {
		Item {
			Layout.preferredWidth: (plainItem.ListView.view && plainItem.ListView.view.hasCheckables) || plainItem.checkable
				? plainItem.indicator.width : Kirigami.Units.smallSpacing
		}
		Item {
			visible: !!plainItem.list
			Layout.alignment: Qt.AlignVCenter
			Layout.preferredHeight: Math.max(plainLabel.height, Kirigami.Units.iconSizes.small)
			Layout.preferredWidth: Layout.preferredHeight
			ListMark {
				anchors.centerIn: parent
				list: plainItem.list
				size: Math.round(Kirigami.Units.iconSizes.small * 0.6)
				color: plainItem.markColor
			}
		}
		Kirigami.Icon {
			Layout.alignment: Qt.AlignVCenter
			visible: !plainItem.list && ((plainItem.ListView.view && plainItem.ListView.view.hasIcons) || plainItem.icon.name.length > 0 || String(plainItem.icon.source).length > 0)
			source: plainItem.icon.name || plainItem.icon.source
			Layout.preferredHeight: Math.max(plainLabel.height, Kirigami.Units.iconSizes.small)
			Layout.preferredWidth: Layout.preferredHeight
		}
		PlasmaComponents3.Label {
			id: plainLabel
			Layout.alignment: Qt.AlignVCenter
			Layout.fillWidth: true
			text: plainItem.label
			textFormat: Text.PlainText // User text
			font: plainItem.font
			elide: Text.ElideRight
			visible: plainItem.label.length > 0
			horizontalAlignment: Text.AlignLeft
			verticalAlignment: Text.AlignVCenter
		}
	}
}
