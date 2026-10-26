// ./uninstall removes the event cache (~/.cache/plasma-eventcalendar), and only that directory.
const assert = require('assert')
const childProcess = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')

const source = fs.readFileSync(path.join(__dirname, '../uninstall'), 'utf8')
const start = source.indexOf('# Event cache:')
const end = source.indexOf('\nfi\n', start)
assert.ok(start >= 0 && end > start, 'uninstall has the event cache block')
const block = source.slice(start, end + 4)
assert.ok(block.includes('"${XDG_CACHE_HOME:-$HOME/.cache}/plasma-eventcalendar"'), 'the cache path')
assert.ok(block.includes('rm -rf -- "$EVENT_CACHE_DIR"'), 'rm -rf of exactly that path')
assert.ok(block.includes('[ -n "${XDG_CACHE_HOME:-}" ] || [ -n "${HOME:-}" ]'), 'guarded against empty variables')

// Run the block: log is the script's.
function run(env) {
	childProcess.execFileSync('bash', ['-euo', 'pipefail', '-c', 'log() { :; }\n' + block], { env: env })
}
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'eventcalendar-uninstall-'))
try {
	const cacheHome = path.join(tmp, 'cache')
	const other = path.join(cacheHome, 'other-app')
	const ours = path.join(cacheHome, 'plasma-eventcalendar')
	fs.mkdirSync(other, { recursive: true })
	fs.mkdirSync(ours, { recursive: true })
	fs.writeFileSync(path.join(ours, 'events.ini'), 'x')
	run({ PATH: process.env.PATH, XDG_CACHE_HOME: cacheHome, HOME: path.join(tmp, 'home') })
	assert.ok(!fs.existsSync(ours), 'XDG_CACHE_HOME: removed')
	assert.ok(fs.existsSync(other), 'other caches kept')

	const homeCache = path.join(tmp, 'home', '.cache', 'plasma-eventcalendar')
	fs.mkdirSync(homeCache, { recursive: true })
	run({ PATH: process.env.PATH, HOME: path.join(tmp, 'home') })
	assert.ok(!fs.existsSync(homeCache), 'HOME/.cache: removed')

	// No HOME and no XDG_CACHE_HOME: nothing happens (and no error).
	run({ PATH: process.env.PATH })
	run({ PATH: process.env.PATH, HOME: '', XDG_CACHE_HOME: '' })
} finally {
	fs.rmSync(tmp, { recursive: true, force: true })
}

console.log('PASS uninstall_cache')
