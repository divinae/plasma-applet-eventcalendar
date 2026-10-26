import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

// A small icon button of a TaskRow's hover buttons, its text as the tooltip.
PlasmaComponents3.ToolButton {
	icon.width: Kirigami.Units.iconSizes.small
	icon.height: Kirigami.Units.iconSizes.small
	display: QQC2.AbstractButton.IconOnly
	padding: 3
	Accessible.name: text
	PlasmaComponents3.ToolTip.text: text
	PlasmaComponents3.ToolTip.visible: hovered
	PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
}
