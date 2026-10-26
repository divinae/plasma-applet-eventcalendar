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

	text: label.replace(/&/g, "&&") // Escaped: no mnemonic from the user's "&"
	Accessible.name: label

	contentItem: RowLayout {
		Item {
			Layout.preferredWidth: (plainItem.ListView.view && plainItem.ListView.view.hasCheckables) || plainItem.checkable
				? plainItem.indicator.width : Kirigami.Units.smallSpacing
		}
		Kirigami.Icon {
			Layout.alignment: Qt.AlignVCenter
			visible: (plainItem.ListView.view && plainItem.ListView.view.hasIcons) || plainItem.icon.name.length > 0 || String(plainItem.icon.source).length > 0
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
