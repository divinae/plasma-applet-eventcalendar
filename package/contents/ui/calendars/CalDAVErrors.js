.pragma library

// scripts/caldav.py's error line ("AUTH: Access denied …", the last line of its stderr): its kind
// (AUTH, NOTFOUND, CONFLICT, NETWORK, PROTOCOL, INPUT, or "" for anything else) and its text, any
// URL in it left out (as ICalManager.safeProcessError).
function parse(stderr) {
	var line = String(stderr || "").trim().split("\n").pop()
	var kind = (/^([A-Z]+):/.exec(line) || [])[1] || ""
	var text = line.replace(/^[A-Z]+:\s*/, "").replace(/https?:\/\/\S+/gi, "[URL]")
	return { kind: kind, text: text }
}
