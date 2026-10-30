.pragma library

// The stripes of StripeFill as an SVG image (a data URL): bands 3 px wide every 9 px along the width,
// bottom left to top right, clipped to the rounded tile. Polygons only (Qt SVG is SVG Tiny: no
// clipPath or pattern), so each band is clipped here, against the rounded rectangle as a polygon
// (convex: Sutherland-Hodgman). Cached by size, color and radius.
var cache = {}

function roundedRect(w, h, r) {
	r = Math.max(0, Math.min(r, w / 2, h / 2))
	if (r === 0) {
		return [[0, 0], [w, 0], [w, h], [0, h]]
	}
	var points = []
	var corners = [[w - r, r, -Math.PI / 2], [w - r, h - r, 0], [r, h - r, Math.PI / 2], [r, r, Math.PI]]
	var steps = 4
	corners.forEach(function(c) {
		for (var i = 0; i <= steps; i++) {
			var a = c[2] + (Math.PI / 2) * i / steps
			points.push([c[0] + r * Math.cos(a), c[1] + r * Math.sin(a)])
		}
	})
	return points
}

// subject clipped by the convex polygon clip (both clockwise in screen coordinates).
function clipPolygon(subject, clip) {
	var output = subject
	for (var i = 0; i < clip.length && output.length; i++) {
		var a = clip[i], b = clip[(i + 1) % clip.length]
		var inside = function(p) { return (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0]) >= 0 }
		var cross = function(p, q) {
			var x1 = p[0], y1 = p[1], x2 = q[0], y2 = q[1]
			var den = (x1 - x2) * (a[1] - b[1]) - (y1 - y2) * (a[0] - b[0])
			var t = ((x1 - a[0]) * (a[1] - b[1]) - (y1 - a[1]) * (a[0] - b[0])) / den
			return [x1 + t * (x2 - x1), y1 + t * (y2 - y1)]
		}
		var input = output
		output = []
		for (var j = 0; j < input.length; j++) {
			var p = input[j], q = input[(j + 1) % input.length]
			if (inside(q)) {
				if (!inside(p)) {
					output.push(cross(p, q))
				}
				output.push(q)
			} else if (inside(p)) {
				output.push(cross(p, q))
			}
		}
	}
	return output
}

function svgPath(w, h, radius) {
	var clip = roundedRect(w, h, radius)
	var half = 1.5 * Math.SQRT2 // A band 3 px wide across: 3 * sqrt(2) along the width
	var d = ''
	for (var x = 0; x <= w + h + 9; x += 9) {
		// The band's center line goes from (x - h, h) to (x, 0).
		var band = [[x - half, 0], [x + half, 0], [x - h + half, h], [x - h - half, h]]
		var poly = clipPolygon(band, clip)
		if (poly.length >= 3) {
			d += 'M' + poly.map(function(p) { return p[0].toFixed(2) + ' ' + p[1].toFixed(2) }).join('L') + 'Z'
		}
	}
	return d
}

// color: "#rrggbb"; opacity of the stripes.
function url(w, h, color, opacity, radius) {
	w = Math.max(1, Math.round(w))
	h = Math.max(1, Math.round(h))
	var key = w + '|' + h + '|' + color + '|' + opacity + '|' + radius
	if (!cache[key]) {
		cache[key] = 'data:image/svg+xml;utf8,' + encodeURIComponent(
			'<svg xmlns="http://www.w3.org/2000/svg" width="' + w + '" height="' + h + '" viewBox="0 0 ' + w + ' ' + h + '">'
			+ '<path fill="' + color + '" fill-opacity="' + opacity + '" d="' + svgPath(w, h, radius) + '"/></svg>')
	}
	return cache[key]
}
