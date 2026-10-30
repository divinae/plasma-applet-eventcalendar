import QtQuick
import org.kde.kirigami as Kirigami

// Content that just appeared (a view switched to, a month paged to) fades in and slides into place
// from a little to the side or below: run(dx, dy) with the direction it comes from (+1 from the
// right / below, -1 from the left / above, 0 none). Opacity and a Translate only (no layout), as
// long as Plasma's animation speed says (instant: no animation).
ParallelAnimation {
	id: slideIn

	property Item target: null
	property Translate shift: null // The target's transform
	property real distance: Kirigami.Units.gridUnit * 1.2

	function run(dx, dy) {
		if (!target || !appletConfig.animations) {
			return
		}
		stop()
		// Right to left: "from the right" is from the left.
		var mirror = Qt.application.layoutDirection === Qt.RightToLeft ? -1 : 1
		xMove.from = shift ? (dx || 0) * mirror * distance : 0
		yMove.from = shift ? (dy || 0) * distance * 0.5 : 0
		start()
	}

	NumberAnimation {
		target: slideIn.target
		property: "opacity"
		from: 0
		to: 1
		duration: appletConfig.longDuration
		easing.type: Easing.OutCubic
	}
	NumberAnimation {
		id: xMove
		target: slideIn.shift
		property: "x"
		to: 0
		duration: appletConfig.longDuration
		easing.type: Easing.OutCubic
	}
	NumberAnimation {
		id: yMove
		target: slideIn.shift
		property: "y"
		to: 0
		duration: appletConfig.longDuration
		easing.type: Easing.OutCubic
	}
}
