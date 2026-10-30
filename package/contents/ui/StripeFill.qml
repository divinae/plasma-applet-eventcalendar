import QtQuick

import "StripeSvg.js" as StripeSvg

// Diagonal stripes for an event the user answered "maybe" to (or out of office), like Google
// Calendar. Fill the event tile with it, under the text.
// One image per tile: the stripes as an SVG clipped to the rounded tile (StripeSvg.js), drawn once
// per size and color (Qt caches it), nothing at all when hidden. Not a Canvas (it painted with
// QPainter during the layout and hung Plasma in #3), nor a rectangle per stripe (30 items and a
// layer per tile, even unstriped ones, made the Month view slow to open).
Image {
	id: stripeFill
	property color stripeColor: "gray"
	property real radius: 0

	readonly property bool active: visible && width > 0 && height > 0
	readonly property real pixelRatio: Screen.devicePixelRatio || 1
	source: active ? StripeSvg.url(width, height, String(Qt.rgba(stripeColor.r, stripeColor.g, stripeColor.b, 1)).substr(0, 7), 0.35, radius) : ""
	sourceSize: Qt.size(Math.ceil(width * pixelRatio), Math.ceil(height * pixelRatio))
	fillMode: Image.Stretch
	smooth: true
}
