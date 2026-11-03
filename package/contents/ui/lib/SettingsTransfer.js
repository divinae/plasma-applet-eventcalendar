.pragma library
// Settings > Views > Settings backup: the widget's settings as a JSON file and back (issue #21).
// No secrets go into the file (tokens and passwords are in the keyring anyway; the older settings
// that held them are left out) and no internal state; an imported file can't set them either.

var APP = "org.kde.plasma.eventcalendar"
var SECRET = /token|secret|password|appid/i
var INTERNAL = [
	"debugging",
	"importRequest", // A pending import of an .ics file
	"invitationsNotified",
	"mutedEventKeys",
	"latestClientId",
	"sessionClientId",
	"useDesktopClient",
]

function exportable(key) {
	key = String(key || "")
	if (!key || /Default$/.test(key) || /^v\d+Migration$/.test(key)) {
		return false
	}
	return !SECRET.test(key) && INTERNAL.indexOf(key) < 0
}

// The file's object: { app, version, exported, settings: { key: value } } for the exportable
// keys; read(key) gives a setting's value (undefined: left out).
function build(keys, read, version, now) {
	var settings = {}
	;(keys || []).filter(exportable).sort().forEach(function(key) {
		var value = read(key)
		if (value !== undefined && value !== null) {
			settings[key] = value
		}
	})
	return {
		app: APP,
		version: String(version || ""),
		exported: (now || new Date()).toISOString(),
		settings: settings,
	}
}

function sameKind(current, value) {
	if (Array.isArray(current) || Array.isArray(value)) {
		return Array.isArray(current) && Array.isArray(value) && value.every(function(item) { return typeof item === "string" })
	}
	return typeof current === typeof value
}

// The file's text → { settings: { key: value }, skipped: [key] } or { error }. Only the keys
// this widget has (current(key) isn't undefined), exportable, with a value of the same kind.
function parse(text, current) {
	var data
	try {
		data = JSON.parse(String(text || ""))
	} catch (e) {
		return { error: "json" }
	}
	if (!data || typeof data !== "object" || data.app !== APP || !data.settings || typeof data.settings !== "object" || Array.isArray(data.settings)) {
		return { error: "app" }
	}
	var settings = {}
	var skipped = []
	Object.keys(data.settings).sort().forEach(function(key) {
		var value = data.settings[key]
		var now = exportable(key) ? current(key) : undefined
		if (now === undefined || now === null || value === null || !sameKind(now, value)) {
			skipped.push(key)
			return
		}
		settings[key] = value
	})
	return { settings: settings, skipped: skipped }
}

// "eventcalendar-settings-2026-11-03.json"
function fileName(date) {
	function pad(n) { return (n < 10 ? "0" : "") + n }
	return "eventcalendar-settings-" + date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate()) + ".json"
}

// A string cut into parts of at most `size` characters (the file is written part by part: a
// command line has a length limit).
function chunks(text, size) {
	var out = []
	for (var i = 0; i < text.length; i += size) {
		out.push(text.slice(i, i + size))
	}
	return out.length ? out : [""]
}
