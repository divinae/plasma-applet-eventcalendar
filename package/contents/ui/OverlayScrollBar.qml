import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A thin, rounded scroll bar without a track: hidden until the view scrolls or the pointer comes
// near its edge, a bit wider on hover and while dragged, then it fades out again.
// On a Flickable (ScrollBar.vertical): laid over the content's edge. In a ScrollView: set view to
// it (the view doesn't place a replacement bar itself); the view keeps a lane as wide as the bar
// for it (its rightPadding), unless the view sets rightPadding: 0 to have it over the content.
T.ScrollBar {
	id: bar

	property Item view: null
	readonly property real thinWidth: 4
	readonly property real wideWidth: 8
	property real thickness: interactive && (hovered || pressed) ? wideWidth : thinWidth
	Behavior on thickness {
		NumberAnimation { duration: Kirigami.Units.shortDuration }
	}

	Binding {
		when: !!bar.view
		target: bar
		property: "parent"
		value: bar.view
	}
	Binding {
		when: !!bar.view
		target: bar
		property: "x"
		value: bar.view ? (bar.view.mirrored ? 0 : bar.view.width - bar.width) : 0
	}
	Binding {
		when: !!bar.view
		target: bar
		property: "y"
		value: bar.view ? bar.view.topPadding : 0
	}
	Binding {
		when: !!bar.view
		target: bar
		property: "height"
		value: bar.view ? bar.view.availableHeight : 0
	}

	visible: policy === T.ScrollBar.AlwaysOn || (policy === T.ScrollBar.AsNeeded && size > 0 && size < 1)
	implicitWidth: wideWidth + 4
	implicitHeight: implicitWidth
	hoverEnabled: true
	// The handle stays grabbable on a long list.
	minimumSize: height > 0 ? Math.min(1, Kirigami.Units.gridUnit * 2 / height) : 0
	// The handle along the outer edge, 2 px in.
	topPadding: 2
	bottomPadding: 2
	leftPadding: mirrored ? 2 : width - 2 - thickness
	rightPadding: mirrored ? width - 2 - thickness : 2

	background: Item {}
	contentItem: Rectangle {
		id: handle
		implicitWidth: bar.thinWidth
		implicitHeight: implicitWidth
		radius: width / 2
		color: Kirigami.Theme.textColor
		opacity: 0
		states: State {
			name: "shown"
			when: bar.policy === T.ScrollBar.AlwaysOn || (bar.active && bar.size < 1)
			PropertyChanges {
				target: handle
				opacity: bar.pressed ? 0.6 : bar.hovered ? 0.5 : 0.35
			}
		}
		transitions: [
			Transition {
				to: "shown"
				NumberAnimation { property: "opacity"; duration: Kirigami.Units.shortDuration }
			},
			// Stays a moment after the scrolling stopped.
			Transition {
				from: "shown"
				SequentialAnimation {
					PauseAnimation { duration: 800 }
					NumberAnimation { property: "opacity"; duration: Kirigami.Units.longDuration }
				}
			}
		]
	}
}
