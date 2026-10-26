import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

// "Completed · Undo" for a few seconds after a task was checked (Tasks view, Day view's tasks), like
// TickTick's: a small pill, Undo unchecks it again. offer(item) shows it (a newer one replaces it);
// it stays while the pointer is on it.
Rectangle {
	id: undoBar

	property var eventModel: null
	property var item: null
	property int timeout: 5000

	function offer(task) {
		item = task
		shown = true
		timer.restart()
	}
	function undo() {
		var task = item
		shown = false
		item = null
		if (task && eventModel) {
			eventModel.toggleTask(task, false)
		}
	}

	property bool shown: false
	visible: shown || opacity > 0
	opacity: shown ? 1 : 0
	Behavior on opacity {
		NumberAnimation { duration: Kirigami.Units.shortDuration }
	}

	implicitWidth: row.implicitWidth + Kirigami.Units.largeSpacing * 2
	implicitHeight: row.implicitHeight + Kirigami.Units.smallSpacing * 2
	radius: height / 2
	// Solid: reads the same over the tasks below it.
	color: Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.backgroundColor, Kirigami.Theme.textColor, 0.08)
	border.width: 1
	border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.18)

	HoverHandler {
		id: hover
	}
	Timer {
		id: timer
		interval: undoBar.timeout
		running: undoBar.shown && !hover.hovered
		onTriggered: undoBar.shown = false
	}

	RowLayout {
		id: row
		anchors.centerIn: parent
		spacing: Kirigami.Units.smallSpacing
		Kirigami.Icon {
			implicitWidth: Kirigami.Units.iconSizes.small
			implicitHeight: implicitWidth
			source: "task-complete"
			color: Kirigami.Theme.positiveTextColor
			isMask: true
		}
		PlasmaComponents3.Label {
			text: i18nc("a task was checked", "Completed")
			textFormat: Text.PlainText
		}
		PlasmaComponents3.Label {
			text: "·"
			textFormat: Text.PlainText
			opacity: 0.6
		}
		PlasmaComponents3.ToolButton {
			text: i18n("Undo")
			icon.name: "edit-undo"
			icon.width: Kirigami.Units.iconSizes.small
			icon.height: Kirigami.Units.iconSizes.small
			topPadding: 2
			bottomPadding: 2
			onClicked: undoBar.undo()
		}
	}
}
