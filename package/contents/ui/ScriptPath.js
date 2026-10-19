.pragma library

// Paths of the package's helper scripts (package/contents/scripts), for running them with
// python3. Tested in tests/script_path.test.js.

// A local path from a file:// URL (percent-decoded: an install path with spaces or non-ASCII
// characters is encoded in the URL), or `url` as it is when it isn't one.
function localPath(url) {
	var text = String(url)
	return text.indexOf('file://') === 0 ? decodeURIComponent(text.slice(7)) : text
}

// The path of the script `name`, eg: scriptPath('icsjson.py').
function scriptPath(name) {
	return localPath(Qt.resolvedUrl('../scripts/' + name))
}
