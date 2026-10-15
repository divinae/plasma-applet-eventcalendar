.pragma library

// Finds a video meeting link for an event.
// Returns { url, label } or null.

var knownHosts = [
	{ pattern: /^(.+\.)?meet\.google\.com$/, label: "Google Meet" },
	{ pattern: /^(.+\.)?zoom\.us$/, label: "Zoom" },
	{ pattern: /^teams\.(microsoft|live)\.com$/, label: "Microsoft Teams" },
	{ pattern: /^(.+\.)?webex\.com$/, label: "Webex" },
	{ pattern: /^(.+\.)?whereby\.com$/, label: "Whereby" },
	{ pattern: /^meet\.jit\.si$/, label: "Jitsi Meet" },
]

function hostLabel(url) {
	var match = /^https?:\/\/([^\/:?#]+)/i.exec(url)
	if (!match) {
		return ""
	}
	var host = match[1].toLowerCase()
	for (var i = 0; i < knownHosts.length; i++) {
		if (knownHosts[i].pattern.test(host)) {
			return knownHosts[i].label
		}
	}
	return ""
}

function findInText(text) {
	if (!text) {
		return null
	}
	var urlRegex = /https?:\/\/[^\s<>"']+/gi
	var match
	while ((match = urlRegex.exec(String(text))) !== null) {
		var url = match[0].replace(/[).,;]+$/, '') // Trailing punctuation from prose.
		var label = hostLabel(url)
		if (label) {
			return { url: url, label: label }
		}
	}
	return null
}

function find(event) {
	if (!event) {
		return null
	}
	var conference = event.conferenceData
	var solutionName = conference && conference.conferenceSolution && conference.conferenceSolution.name || ""

	if (event.hangoutLink) {
		return { url: event.hangoutLink, label: solutionName || hostLabel(event.hangoutLink) || "Google Meet" }
	}

	var entryPoints = conference && conference.entryPoints
	if (entryPoints) {
		// A JS array, or a ListModel when read from an agenda delegate's model.
		var isListModel = typeof entryPoints.count === 'number' && typeof entryPoints.get === 'function'
		var count = isListModel ? entryPoints.count : entryPoints.length
		for (var i = 0; i < count; i++) {
			var entryPoint = isListModel ? entryPoints.get(i) : entryPoints[i]
			if (entryPoint.entryPointType === 'video' && entryPoint.uri) {
				var uri = entryPoint.uri
				return { url: uri, label: solutionName || hostLabel(uri) || "Video call" }
			}
		}
	}

	return findInText(event.location) || findInText(event.description)
}
