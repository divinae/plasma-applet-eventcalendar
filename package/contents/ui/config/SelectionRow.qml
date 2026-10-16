import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import "../lib/ColorUtil.js" as ColorUtil

// A calendar or task list the user can show in the widget: checkbox, color swatch (or icon), name,
// and a lock when it's read-only.
CheckDelegate {
	id: row

	property string name
	property color swatchColor: "transparent"
	property url iconSource
	property bool readOnly: false

	hoverEnabled: true
	highlighted: hovered
	padding: Kirigami.Units.smallSpacing
	text: name

	contentItem: RowLayout {
		spacing: Kirigami.Units.smallSpacing

		Rectangle {
			visible: !row.iconSource.toString()
			Layout.preferredWidth: Kirigami.Units.iconSizes.small
			Layout.preferredHeight: Layout.preferredWidth
			radius: 4
			color: row.swatchColor
			border.width: 1
			border.color: ColorUtil.setAlpha(Kirigami.Theme.textColor, 0.3)
		}
		Image {
			visible: !!row.iconSource.toString()
			source: row.iconSource
			smooth: true
			Layout.preferredWidth: Kirigami.Units.iconSizes.small
			Layout.preferredHeight: Layout.preferredWidth
		}
		Label {
			Layout.fillWidth: true
			text: row.name
			elide: Text.ElideRight
		}
		LockIcon {
			visible: row.readOnly
			Layout.preferredWidth: Kirigami.Units.iconSizes.small
			Layout.preferredHeight: Layout.preferredWidth
		}
	}

	Accessible.name: name
}
