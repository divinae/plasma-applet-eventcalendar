const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const source = fs.readFileSync(path.join(__dirname, '../package/contents/ui/TaskLists.js'), 'utf8')
	.replace(/^\.pragma library\s*$/m, '')
const names = ['swatches', 'isEditableRole', 'capabilities', 'hasAny', 'cleanTitle', 'hexColor',
	'withAdded', 'withChanged', 'withRemoved', 'taskCount']
const L = {}
vm.runInNewContext(source + '\nObject.assign(out, { ' + names.join(', ') + ' })', { out: L })
const plain = o => JSON.parse(JSON.stringify(o))
const same = (a, b, msg) => assert.deepStrictEqual(plain(a), b, msg)

//--- Capabilities
const none = { rename: false, delete: false, color: false, clearCompleted: false }
same(L.capabilities('GoogleTasks', 'abc', 'owner'), { rename: true, delete: true, color: false, clearCompleted: true })
same(L.capabilities('GoogleTasks', 'abc', undefined), { rename: true, delete: true, color: false, clearCompleted: true })
same(L.capabilities('TickTick', 'p1', 'owner'), { rename: true, delete: true, color: true, clearCompleted: false })
same(L.capabilities('TickTick', 'p1', 'writer'), { rename: true, delete: true, color: true, clearCompleted: false })
same(L.capabilities('TickTick', 'inbox', 'owner'), none, 'the Inbox stays')
same(L.capabilities('TickTick', 'inbox1234', 'owner'), none, 'the Inbox by its real id')
same(L.capabilities('TickTick', 'p1', 'reader'), none, 'read-only')
same(L.capabilities('GoogleTasks', 'abc', 'freeBusyReader'), none)
same(L.capabilities('ICal', 'x', 'owner'), none)
assert.strictEqual(L.hasAny(none), false)
assert.strictEqual(L.hasAny(null), false)
assert.strictEqual(L.hasAny({ clearCompleted: true }), true)
assert.strictEqual(L.isEditableRole('writer'), true)
assert.strictEqual(L.isEditableRole('reader'), false)

//--- Titles and colors
assert.strictEqual(L.cleanTitle('  Groceries \n list '), 'Groceries list')
assert.strictEqual(L.cleanTitle('   '), '')
assert.strictEqual(L.cleanTitle(null), '')
assert.strictEqual(L.hexColor('#FF6161'), '#ff6161')
assert.strictEqual(L.hexColor('4ca1ff'), '#4ca1ff')
assert.strictEqual(L.hexColor('#fff'), '')
assert.strictEqual(L.hexColor('red'), '')
assert.strictEqual(L.hexColor(undefined), '')
L.swatches.forEach(c => assert.strictEqual(L.hexColor(c), c, 'swatch ' + c))

//--- Stored lists after a change
const lists = [{ id: 'a', title: 'A' }, { id: 'b', title: 'B' }]
const ids = ['a']
same(L.withAdded(lists, ids, { id: 'c', title: 'C' }), {
	lists: [{ id: 'a', title: 'A' }, { id: 'b', title: 'B' }, { id: 'c', title: 'C' }],
	ids: ['a', 'c'],
}, 'a new list is shown')
same(L.withAdded(lists, ids, { id: 'b', title: 'B' }), { lists: plain(lists), ids: ['a', 'b'] }, 'no duplicate')
same(L.withAdded(lists, ids, null), { lists: plain(lists), ids: ['a'] })
same(L.withAdded(undefined, undefined, { id: 'x' }), { lists: [{ id: 'x' }], ids: ['x'] })
same(L.withChanged(lists, ids, 'b', { title: 'Bee' }), {
	lists: [{ id: 'a', title: 'A' }, { id: 'b', title: 'Bee' }],
	ids: ['a'],
})
same(L.withChanged([{ id: 'p', name: 'P', color: '' }], ['p'], 'p', { color: '#ff6161' }).lists, [{ id: 'p', name: 'P', color: '#ff6161' }])
same(L.withRemoved(lists, ['a', 'b'], 'a'), { lists: [{ id: 'b', title: 'B' }], ids: ['b'] }, 'a deleted list leaves the selection')
same(L.withRemoved(lists, ids, 'zzz'), { lists: plain(lists), ids: ['a'] })
// Inputs are not changed.
same(lists, [{ id: 'a', title: 'A' }, { id: 'b', title: 'B' }])
same(ids, ['a'])

//--- Tasks a delete takes with it
assert.strictEqual(L.taskCount([
	{ kind: 'tasks#task', id: '1' }, { kind: 'tasks#task', id: '2' }, { kind: 'tasks#task', id: '1' },
	{ kind: 'calendar#event', id: 'e' }, null,
]), 2)
assert.strictEqual(L.taskCount(undefined), 0)

console.log('PASS task_lists')
