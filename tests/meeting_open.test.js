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

console.log('meeting_open: ok')
