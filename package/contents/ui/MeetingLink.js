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

//--- Opening Google Meet links in a chosen app (MeetingOpener.qml)

// Same hosts as hostLabel: meet.google.com and its subdomains, http or https.
function isGoogleMeet(url) {
	return /^https?:\/\/([a-z0-9-]+\.)*meet\.google\.com(?=[\/?#:]|$)/i.test(String(url || ''))
}

// The Google account to join with: an index ("1") or an email, as Google's authuser parameter.
function withAuthUser(url, authuser) {
	if (!authuser) {
		return url
	}
	var hash = ''
	var hashIndex = url.indexOf('#')
	if (hashIndex >= 0) {
		hash = url.substring(hashIndex)
		url = url.substring(0, hashIndex)
	}
	if (/[?&]authuser=/.test(url)) {
		return url + hash // The link names its account already
	}
	return url + (url.indexOf('?') >= 0 ? '&' : '?') + 'authuser=' + encodeURIComponent(authuser) + hash
}

// A command line split into arguments like a shell would, without running one: quotes and
// backslashes group, nothing is expanded. Returns null when quotes don't match.
function splitCommand(command) {
	var args = []
	var current = ''
	var hasCurrent = false
	var quote = ''
	var text = String(command || '')
	for (var i = 0; i < text.length; i++) {
		var c = text[i]
		if (quote) {
			if (c === quote) {
				quote = ''
			} else if (c === '\\' && quote === '"' && i + 1 < text.length) {
				current += text[++i]
			} else {
				current += c
			}
		} else if (c === '"' || c === "'") {
			quote = c
			hasCurrent = true
		} else if (c === '\\' && i + 1 < text.length) {
			current += text[++i]
			hasCurrent = true
		} else if (/\s/.test(c)) {
			if (hasCurrent) {
				args.push(current)
				current = ''
				hasCurrent = false
			}
		} else {
			current += c
			hasCurrent = true
		}
	}
	if (quote) {
		return null
	}
	if (hasCurrent) {
		args.push(current)
	}
	return args
}

// The arguments to run: %u (or %U) replaced by the URL as part of one argument (never re-split),
// or the URL added at the end when the command has neither. Other desktop entry field codes
// (%f %F %i %c %k) are dropped and %% becomes %, so an Exec line can be pasted as it is.
// null for an empty or broken command.
function launchArgv(command, url) {
	var args = splitCommand(command)
	if (!args || !args.length) {
		return null
	}
	var used = false
	var result = []
	args.forEach(function(arg) {
		if (/^%[fFick]$/.test(arg)) {
			return
		}
		var out = ''
		for (var i = 0; i < arg.length; i++) {
			if (arg[i] === '%' && i + 1 < arg.length) {
				var code = arg[i + 1]
				if (code === 'u' || code === 'U') {
					out += url
					used = true
					i++
					continue
				}
				if (code === '%') {
					out += '%'
					i++
					continue
				}
			}
			out += arg[i]
		}
		result.push(out)
	})
	args = result
	if (!args.length) {
		return null
	}
	if (!used) {
		args.push(url)
	}
	return args
}
