import QtQuick
import org.kde.plasma.components as PlasmaComponents3

// Plasma's ScrollBar without the separator line the Breeze theme draws next to it
// (the line runs the full height of a list and looks like a border).
PlasmaComponents3.ScrollBar {
	id: scrollBar
	Component.onCompleted: {
		// The separator is a 1 px Rectangle child, not exposed as a property.
		for (var i = 0; i < scrollBar.children.length; i++) {
			var child = scrollBar.children[i]
			if (child !== scrollBar.background && child !== scrollBar.contentItem && child.implicitWidth === 1 && child.implicitHeight === 1) {
				child.visible = false
			}
		}
	}
}
