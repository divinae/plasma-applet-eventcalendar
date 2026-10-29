// Opening Google Meet links in a chosen app (package/contents/ui/MeetingLink.js).
const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const source = fs.readFileSync(path.join(__dirname, '../package/contents/ui/MeetingLink.js'), 'utf8')
	.replace(/^\.pragma library\s*$/m, '')
	.replace(/^\.import .*$/mg, '')
const M = {}
vm.runInNewContext(source, M)
const list = value => value && Array.from(value)

assert.strictEqual(M.isGoogleMeet('https://meet.google.com/abc-defg-hij'), true)
assert.strictEqual(M.isGoogleMeet('https://zoom.us/j/1'), false)
assert.strictEqual(M.isGoogleMeet('https://meet.google.com.evil.example/x'), false)

assert.strictEqual(M.withAuthUser('https://meet.google.com/abc', '1'), 'https://meet.google.com/abc?authuser=1')
assert.strictEqual(M.withAuthUser('https://meet.google.com/abc?hs=1', 'me@example.com'), 'https://meet.google.com/abc?hs=1&authuser=me%40example.com')
assert.strictEqual(M.withAuthUser('https://meet.google.com/abc?authuser=0', '1'), 'https://meet.google.com/abc?authuser=0', 'kept')
assert.strictEqual(M.withAuthUser('https://meet.google.com/abc', ''), 'https://meet.google.com/abc')

assert.deepStrictEqual(list(M.splitCommand('vivaldi-stable --app=%u --class=X')), ['vivaldi-stable', '--app=%u', '--class=X'])
assert.deepStrictEqual(list(M.splitCommand('"/opt/My Browser/b" --x=\'a b\' c\\ d')), ['/opt/My Browser/b', '--x=a b', 'c d'])
assert.strictEqual(M.splitCommand('broken "quote'), null)

const url = 'https://meet.google.com/abc-defg-hij?authuser=1'
assert.deepStrictEqual(list(M.launchArgv('vivaldi-stable --app=%u --class=WebApp-Meets3811', url)),
	['vivaldi-stable', '--app=' + url, '--class=WebApp-Meets3811'])
assert.deepStrictEqual(list(M.launchArgv('brave --app-id=x', url)), ['brave', '--app-id=x', url], 'URL appended')
// The URL is one argument even with shell characters in it; nothing is run through a shell.
const nasty = 'https://meet.google.com/abc?x=$(rm -rf ~);y="z"'
assert.deepStrictEqual(list(M.launchArgv('app --app=%u', nasty)), ['app', '--app=' + nasty])
assert.strictEqual(M.launchArgv('', url), null)
assert.strictEqual(M.launchArgv('   ', url), null)

// Same hosts as the Join button's label.
assert.strictEqual(M.isGoogleMeet('http://meet.google.com/abc'), true)
assert.strictEqual(M.isGoogleMeet('https://x.meet.google.com/abc'), true)
assert.strictEqual(M.isGoogleMeet('https://meet.google.com'), true)
assert.strictEqual(M.isGoogleMeet('https://notmeet.google.com/abc'), false)
// An authuser only in the fragment doesn't count.
assert.strictEqual(M.withAuthUser('https://meet.google.com/abc#x?authuser=0', '1'), 'https://meet.google.com/abc?authuser=1#x?authuser=0')
// Desktop entry field codes.
assert.deepStrictEqual(list(M.launchArgv('chromium --app-id=xyz %U', url)), ['chromium', '--app-id=xyz', url])
assert.deepStrictEqual(list(M.launchArgv('app %f --x=100%% %u', url)), ['app', '--x=100%', url])
assert.strictEqual(M.launchArgv('%F', url), null)

console.log('meeting_open: ok')
// Services found in a location or the notes (hostLabel): by host, a few by path too.
const label = url => M.hostLabel(url)
assert.strictEqual(label('https://us02web.zoom.us/j/123'), 'Zoom')
assert.strictEqual(label('https://agency.zoomgov.com/j/123'), 'Zoom')
assert.strictEqual(label('https://teams.microsoft.com/l/meetup-join/x'), 'Microsoft Teams')
assert.strictEqual(label('https://meet.goto.com/123456789'), 'GoTo Meeting')
assert.strictEqual(label('https://app.slack.com/huddle/T1/C1'), 'Slack Huddle')
assert.strictEqual(label('https://app.slack.com/client/T1/C1'), '', 'a Slack page that is no huddle')
assert.strictEqual(label('https://discord.gg/abc'), 'Discord')
assert.strictEqual(label('https://discord.com/channels/1/2'), 'Discord')
assert.strictEqual(label('https://discord.com/app'), '', 'a Discord page that is no call')
assert.strictEqual(label('https://chime.aws/1234567890'), 'Amazon Chime')
assert.strictEqual(label('https://8x8.vc/company/room'), 'Jitsi Meet')
assert.strictEqual(label('https://zoom.us.evil.example/j/1'), '', 'a look-alike host')
assert.strictEqual(M.find({ location: 'Room 1, https://whereby.com/team' }).label, 'Whereby')

