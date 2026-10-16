.pragma library

// Google's API still returns calendar and event colors from its old ("classic") palette, while the
// Google Calendar website shows them as its current named colors. Map one to the other so events
// look like they do in Google Calendar.

// Calendar colors (calendarList backgroundColor, classic) -> current color.
var calendarColors = {
	'#ac725e': '#795548', // Cocoa
	'#d06b64': '#e67c73', // Flamingo
	'#f83a22': '#d50000', // Tomato
	'#fa573c': '#f4511e', // Tangerine
	'#ff7537': '#ef6c00', // Pumpkin
	'#ffad46': '#f09300', // Mango
	'#42d692': '#009688', // Eucalyptus
	'#16a765': '#0b8043', // Basil
	'#7bd148': '#7cb342', // Pistachio
	'#b3dc6c': '#c0ca33', // Avocado
	'#fbe983': '#e4c441', // Citron
	'#fad165': '#f6bf26', // Banana
	'#92e1c0': '#33b679', // Sage
	'#9fe1e7': '#039be5', // Peacock
	'#9fc6e7': '#4285f4', // Cobalt
	'#4986e7': '#3f51b5', // Blueberry
	'#9a9cff': '#7986cb', // Lavender
	'#b99aff': '#b39ddb', // Wisteria
	'#c2c2c2': '#616161', // Graphite
	'#cabdbf': '#a79b8e', // Birch
	'#cca6ac': '#ad1457', // Radicchio
	'#f691b2': '#d81b60', // Cherry blossom
	'#cd74e6': '#9e69af', // Amethyst
	'#a47ae2': '#8e24aa', // Grape
}

// Event colors by colorId (1..11) as Google Calendar shows them.
var eventColors = {
	'1': '#7986cb', // Lavender
	'2': '#33b679', // Sage
	'3': '#8e24aa', // Grape
	'4': '#e67c73', // Flamingo
	'5': '#f6bf26', // Banana
	'6': '#f4511e', // Tangerine
	'7': '#039be5', // Peacock
	'8': '#616161', // Graphite
	'9': '#3f51b5', // Blueberry
	'10': '#0b8043', // Basil
	'11': '#d50000', // Tomato
}

// Calendar colorIds 1..24 (same order as the classic list above).
var calendarColorsById = Object.keys(calendarColors).map(function(k) { return calendarColors[k] })

// calendarColor(calendar) or calendarColor("#hex"): the color Google Calendar shows for a calendar.
// By hex first; colors the API returns outside the classic list (eg: "#dadada") by colorId.
function calendarColor(calendarOrColor) {
	var isObject = calendarOrColor && typeof calendarOrColor === 'object'
	var color = isObject ? calendarOrColor.backgroundColor : calendarOrColor
	var key = String(color || '').toLowerCase()
	if (calendarColors[key]) {
		return calendarColors[key]
	}
	var id = isObject ? parseInt(calendarOrColor.colorId, 10) : NaN
	if (id >= 1 && id <= calendarColorsById.length) {
		return calendarColorsById[id - 1]
	}
	return color
}

function eventColor(colorId) {
	return eventColors[String(colorId)] || null
}
