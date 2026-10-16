import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kirigamiaddons.formcard as FormCard

import "../lib/ColorUtil.js" as ColorUtil

// A calendar or task list the user can show in the widget, as a FormCard check row: color swatch
// (or icon), name, and a lock when it's read-only.
FormCard.FormCheckDelegate {
	id: row

	property string name
	property color swatchColor: "transparent"
	property url iconSource
	property bool readOnly: false

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
	// The delegate manages the trailing item's own visibility, so the lock is a child of it.
	trailing: Item {
		implicitWidth: Kirigami.Units.iconSizes.small
		implicitHeight: Kirigami.Units.iconSizes.small
		LockIcon {
			anchors.fill: parent
			visible: row.readOnly
		}
	}

	Accessible.name: name
}
