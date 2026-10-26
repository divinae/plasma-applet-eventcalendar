const assert = require('assert')
const fs = require('fs')
const path = require('path')

const state = require('../package/contents/ui/lib/TickTickAccountState.js')
const UI = path.join(__dirname, '../package/contents/ui')
const read = file => fs.readFileSync(path.join(UI, file), 'utf8')

// Only the whitelisted fields are saved: never the token.
const saved = state.serializeAccount({
	id: 'tt_1',
	label: 'TickTick',
	server: 'dida365',
	token: 'secret-token',
	accessToken: 'x',
	projectList: [{ id: 'p1', name: 'Work', color: '#F18181', closed: false, extra: { a: 1 } }, { name: 'no id' }],
	projectIdList: ['p1', '', null, 2],
	other: 'dropped',
})
assert.deepStrictEqual(saved, {
	id: 'tt_1',
	label: 'TickTick',
	server: 'dida365',
	projectList: [{ id: 'p1', name: 'Work', color: '#F18181' }],
	projectIdList: ['p1', '2'],
})
assert.ok(!JSON.stringify(saved).includes('secret-token'))

// Unknown servers fall back to TickTick: the token only goes to the known API hosts.
assert.strictEqual(state.serializeAccount({ id: 'a', server: 'https://evil.example' }).server, 'ticktick')
assert.strictEqual(state.apiUrl('evil'), 'https://api.ticktick.com/open/v1')
assert.strictEqual(state.apiUrl('dida365'), 'https://api.dida365.com/open/v1')
assert.strictEqual(state.serverName('dida365'), 'Dida365')
assert.strictEqual(state.serverName('ticktick'), 'TickTick')

// normalizeAccount keeps the runtime token of the same account only.
const loaded = [{ id: 'tt_1', token: 'tok-1' }, { id: 'tt_2', token: 'tok-2' }]
assert.strictEqual(state.normalizeAccount({ id: 'tt_1' }, loaded).token, 'tok-1')
assert.strictEqual(state.normalizeAccount({ id: 'tt_3' }, loaded).token, '')
assert.strictEqual(state.normalizeAccount({ token: 'from-config' }, []), null)
assert.strictEqual(state.normalizeAccount({ id: 'tt_4', token: 'from-config' }, []).token, '', 'a token in config is ignored')

// Task projects: open TASK projects only.
assert.deepStrictEqual(state.taskProjects([
	{ id: 'a', name: 'A', color: null, kind: 'TASK' },
	{ id: 'b', name: 'B', closed: true },
	{ id: 'c', name: 'C', kind: 'NOTE' },
	{ id: 'd', name: 'D' },
	null,
]), [{ id: 'a', name: 'A', color: '' }, { id: 'd', name: 'D', color: '' }])
assert.deepStrictEqual(state.taskProjects(null), [])
assert.ok(/^tt_/.test(state.generateId()))

// The token stays out of argv, config and logs.
const store = read('lib/TickTickAccountsStore.qml')
const keyring = read('lib/KeyringSecret.qml')
const session = read('calendars/TickTickApiSession.qml')
const manager = read('calendars/TickTickTasksManager.qml')
assert.ok(store.includes('accounts.map(TickTickAccountState.serializeAccount)'), 'the store saves serializeAccount only')
assert.ok(store.includes('scope: "ticktick-account"'), 'the store keeps tokens in the ticktick-account keyring scope')
assert.ok(/helperArgs\(command, accountId, key, readyFile\)/.test(keyring), 'helper argv: no value')
assert.ok(!/helperArgs\([^)]*value/.test(keyring), 'the secret value is never in the helper argv')
for (const [name, source] of [['store', store], ['keyring', keyring], ['session', session], ['manager', manager]]) {
	const logLines = source.split('\n').filter(line => /logger\.(log|debug|logJSON|debugJSON)\(|console\./.test(line))
	for (const line of logLines) {
		assert.ok(!/token|value\b|title|notes|content|summary|description|body\b|data\b/i.test(line.replace(/'[^']*'|"[^"]*"/g, '').replace(/\w+\.length/g, '')), // Lengths are fine
			name + ' must not log tokens, titles, notes or bodies: ' + line.trim())
	}
}

console.log('PASS ticktick_account_state')
