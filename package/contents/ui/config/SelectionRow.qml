import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kirigamiaddons.formcard as FormCard

import "../lib/ColorUtil.js" as ColorUtil

// A calendar or task list the user can show in the widget, as a FormCard check row: color swatch
// (or icon), name, a lock when it's read-only, and an edit button when it's editable.
FormCard.FormCheckDelegate {
	id: row

	property string name
	property color swatchColor: "transparent"
	property url iconSource
	property bool readOnly: false
	property bool editable: false

	signal editRequested()

	text: name

	leading: Item {
		implicitWidth: Kirigami.Units.iconSizes.small
		implicitHeight: Kirigami.Units.iconSizes.small
		Rectangle {
			anchors.fill: parent
			visible: !row.iconSource.toString()
			radius: 4
			color: row.swatchColor
			border.width: 1
			border.color: ColorUtil.setAlpha(Kirigami.Theme.textColor, 0.3)
		}
		Image {
			anchors.fill: parent
			visible: !!row.iconSource.toString()
			source: row.iconSource
			smooth: true
		}
	}
	// The delegate manages the trailing item's own visibility, so the lock and button are children of it.
	trailing: Item {
		implicitWidth: trailingRow.implicitWidth
		implicitHeight: trailingRow.implicitHeight
		RowLayout {
			id: trailingRow
			anchors.fill: parent
			spacing: Kirigami.Units.smallSpacing
			Item {
				Layout.preferredWidth: Kirigami.Units.iconSizes.small
				Layout.preferredHeight: Kirigami.Units.iconSizes.small
				LockIcon {
					anchors.fill: parent
					visible: row.readOnly
				}
			}
			ToolButton {
				visible: row.editable
				icon.name: "document-edit"
				display: AbstractButton.IconOnly
				text: i18n("Edit calendar…")
				onClicked: row.editRequested()
				ToolTip.text: text
				ToolTip.visible: hovered
				ToolTip.delay: Kirigami.Units.toolTipDelay
			}
		}
	}

	Accessible.name: name
}
