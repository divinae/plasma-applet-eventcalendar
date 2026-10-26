import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

// When a task is due, as a small rounded chip: dim, red-tinted when overdue, in the accent color
// for today. Its background is solid (the theme's background, tinted), so it reads the same on
// the popup's translucent background as on an opaque one.
Rectangle {
	id: chip

	property string text: ""
	// Tasks.dueInfo's kind: 'overdue', 'today', …
	property string kind: ""
	property font font: Kirigami.Theme.smallFont

	readonly property bool accented: kind === 'overdue' || kind === 'today'
	readonly property color tint: kind === 'overdue' ? Kirigami.Theme.negativeTextColor
		: kind === 'today' ? Kirigami.Theme.highlightColor
		: Kirigami.Theme.textColor

	implicitWidth: label.implicitWidth + Kirigami.Units.smallSpacing * 3
	implicitHeight: label.implicitHeight + 2
	radius: height / 2
	color: Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.backgroundColor, tint, accented ? 0.2 : 0.12)
	border.width: 1
	border.color: Qt.rgba(tint.r, tint.g, tint.b, accented ? 0.3 : 0.15)

	PlasmaComponents3.Label {
		id: label
		anchors.centerIn: parent
		text: chip.text
		textFormat: Text.PlainText
		font: chip.font
		color: chip.kind === 'overdue' ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
		opacity: chip.accented ? 1 : 0.85
	}
}
