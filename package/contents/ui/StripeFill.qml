import QtQuick

// Diagonal stripes for an event the user answered "maybe" to, like Google Calendar.
// Fill the event tile with it, under the text.
Canvas {
	id: stripeFill
	property color stripeColor: "gray"
	property real radius: 0

	onStripeColorChanged: requestPaint()
	onRadiusChanged: requestPaint()
	onWidthChanged: requestPaint()
	onHeightChanged: requestPaint()

	onPaint: {
		var ctx = getContext("2d")
		ctx.reset()
		if (width <= 0 || height <= 0) {
			return
		}
		ctx.beginPath()
		ctx.roundedRect(0, 0, width, height, radius, radius)
		ctx.clip()
		ctx.strokeStyle = Qt.rgba(stripeColor.r, stripeColor.g, stripeColor.b, 0.35)
		ctx.lineWidth = 3
		ctx.beginPath()
		for (var x = -height; x < width; x += 9) {
			ctx.moveTo(x, height)
			ctx.lineTo(x + height, 0)
		}
		ctx.stroke()
	}
}
