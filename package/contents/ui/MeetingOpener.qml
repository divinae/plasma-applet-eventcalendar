import QtQuick

import "lib"
import "MeetingLink.js" as MeetingLink
import "ScriptPath.js" as ScriptPath
import "Shared.js" as Shared

// Opens meeting links (Join buttons): Google Meet links in the app chosen in the settings (eg: a
// Meet web app), with the chosen Google account; everything else in the default browser.
QtObject {
	id: meetingOpener

	property var executable: ExecUtil {}

	readonly property string meetCommand: String(plasmoid.configuration.meetLinkCommand || '').trim()
	readonly property string meetAuthUser: String(plasmoid.configuration.meetLinkAuthUser || '').trim()
	readonly property string launcherPath: ScriptPath.scriptPath("launch_detached.py")
	readonly property string pauseMediaPath: ScriptPath.scriptPath("pause_media.py")

	// Pauses the media players that are playing (scripts/pause_media.py, MPRIS), if set.
	function pauseMedia() {
		if (!plasmoid.configuration.meetingPauseMedia) {
			return
		}
		executable.execArgv(['python3', '-I', pauseMediaPath], function(cmd, exitCode, exitStatus, stdout, stderr) {
			if (exitCode !== 0) {
				logger.log('pausing media failed', exitCode)
			} else if (Number(stdout) > 0) {
				logger.log('paused media players:', Number(stdout))
			}
		})
	}

	function open(url) {
		if (!url) {
			return
		}
		pauseMedia()
		if (!MeetingLink.isGoogleMeet(url)) {
			Shared.openExternalUrl(url)
			return
		}
		url = MeetingLink.withAuthUser(url, meetAuthUser)
		var argv = meetCommand ? MeetingLink.launchArgv(meetCommand, url) : null
		if (!argv) {
			Shared.openExternalUrl(url)
			return
		}
		// Detached (scripts/launch_detached.py): own session, no pipes to us, so nothing waits for
		// the app; it reports when the app can't start, and then the browser is used.
		executable.execArgv(['python3', '-I', launcherPath, '--'].concat(argv), function(cmd, exitCode, exitStatus, stdout, stderr) {
			if (exitCode !== 0) {
				logger.log('meeting app failed to start, opening the browser instead', exitCode)
				Shared.openExternalUrl(url)
			}
		})
	}
}
