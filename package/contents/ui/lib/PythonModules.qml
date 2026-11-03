import QtQuick

import "../ScriptPath.js" as ScriptPath

// The Python modules .ics files and CalDAV are read with (icalendar, recurring-ical-events and what
// they need): a helper's error says whether they're missing (isMissing), and install() puts them
// into the widget's own folder without root (scripts/install_python_deps.py: pip, uv, or the
// wheels from PyPI), as ./install does for an install from source. The import card
// (ImportView.qml) and Settings > Calendars > CalDAV offer it.
QtObject {
	id: modules

	// A helper's output naming a missing module: caldav.py's "DEPS: ...", or Python's own.
	readonly property var missingPattern: /^DEPS:|No module named '?(icalendar|recurring_ical_events|x_wr_timezone|dateutil|tzdata|six|click|typing_extensions)\b/m
	function isMissing(output) {
		return missingPattern.test(String(output || ""))
	}

	property bool installing: false
	// done(errorText): "" once installed, else what went wrong (for the user).
	function install(done) {
		installing = true
		executable.execArgv(['python3', ScriptPath.scriptPath("install_python_deps.py")], function(cmd, exitCode, exitStatus, stdout, stderr) {
			modules.installing = false
			var result = {}
			try {
				var lines = String(stdout || "").trim().split('\n')
				result = JSON.parse(lines[lines.length - 1])
			} catch (e) {
			}
			done(result.ok ? ""
				: result.noInstaller
				? i18n("Couldn't install the modules. Install python3-icalendar (python-icalendar on Arch) with your package manager.")
				: i18n("Couldn't install the modules: %1", String(result.error || stderr || "").slice(0, 200)))
		})
	}

	property ExecUtil executable: ExecUtil {}
}
