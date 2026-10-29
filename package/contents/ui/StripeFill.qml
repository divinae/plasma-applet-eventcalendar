import QtQuick
import org.kde.kirigami as Kirigami

// Diagonal stripes for an event the user answered "maybe" to (or out of office), like Google
// Calendar. Fill the event tile with it, under the text.
// Scene graph items, not a Canvas: a Canvas paints with QPainter on the GUI thread during the
// layout, and its rounded clip hung Plasma in the raster engine while the Agenda opened (#3). The
// stripes are thin rotated rectangles; ShadowedTexture rounds their corners.
Item {
	id: stripeFill
	property color stripeColor: "gray"
	property real radius: 0

	// Lines 3 px wide every 9 px along the width (as the Canvas drew them): 9 / sqrt(2) apart across.
	readonly property real spacing: 9 / Math.SQRT2
	readonly property real span: width + height

	Item {
		id: stripes
		anchors.fill: parent
		visible: false
		layer.enabled: stripeFill.width > 0 && stripeFill.height > 0
		clip: true

		// Bars side by side, turned 45° (bottom left to top right), over the whole tile.
		Item {
			width: stripeFill.span
			height: stripeFill.span
			anchors.centerIn: parent
			rotation: -45
			Repeater {
				model: Math.ceil(stripeFill.span / stripeFill.spacing) + 1
				Rectangle {
					x: index * stripeFill.spacing
					width: 3 // Across the stripe
					height: parent.height
					color: Qt.rgba(stripeFill.stripeColor.r, stripeFill.stripeColor.g, stripeFill.stripeColor.b, 0.35)
					antialiasing: true
				}
			}
		}
	}

	Kirigami.ShadowedTexture {
		anchors.fill: parent
		visible: stripes.layer.enabled
		source: stripes
		radius: stripeFill.radius
		color: "transparent"
	}
}
