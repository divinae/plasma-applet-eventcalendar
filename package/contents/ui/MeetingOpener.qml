import QtQuick

import "lib"
import "MeetingLink.js" as MeetingLink
import "Shared.js" as Shared

// Opens meeting links (Join buttons): Google Meet links in the app chosen in the settings (eg: a
// Meet web app), with the chosen Google account; everything else in the default browser.
QtObject {
	id: meetingOpener

	property var executable: ExecUtil {}

	readonly property string meetCommand: String(plasmoid.configuration.meetLinkCommand || '').trim()
	readonly property string meetAuthUser: String(plasmoid.configuration.meetLinkAuthUser || '').trim()

	function open(url) {
		if (!url) {
			return
		}
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
		// Detached (setsid -f): the app keeps running on its own, the widget doesn't wait for it.
		executable.execArgv(['setsid', '-f'].concat(argv), function(cmd, exitCode, exitStatus, stdout, stderr) {
			if (exitCode !== 0) {
				logger.log('meeting app failed to start, opening the browser instead', exitCode)
				Shared.openExternalUrl(url)
			}
		})
	}
}
