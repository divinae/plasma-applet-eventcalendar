// Guest list editing (package/contents/ui/Guests.js).
const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const source = fs.readFileSync(path.join(__dirname, '../package/contents/ui/Guests.js'), 'utf8')
	.replace(/^\.pragma library\s*$/m, '')
	.replace(/^\.import .*$/mg, '')
const G = {}
vm.runInNewContext(source, G)
// Plain copies: objects from the vm context have other prototypes.
const plain = (value) => JSON.parse(JSON.stringify(value))

// Validation
for (const ok of ['anna@example.com', ' anna@example.com ', 'a.b+c@mail.example.co.uk', 'x@y.z']) {
	assert.ok(G.isValidEmail(ok), ok)
}
for (const bad of ['', 'anna', 'anna@', '@example.com', 'anna@example', 'anna@example.', 'an na@example.com', 'a@b@c.d']) {
	assert.ok(!G.isValidEmail(bad), bad)
}

// Add / remove
let list = []
let r = G.addGuest(list, ' Anna@Example.com ')
assert.strictEqual(r.error, '')
list = r.list
assert.deepStrictEqual(plain(list), [{ email: 'Anna@Example.com' }])
r = G.addGuest(list, 'anna@example.COM')
assert.strictEqual(r.error, 'duplicate', 'case-insensitive duplicate')
assert.strictEqual(r.list, list)
assert.strictEqual(G.addGuest(list, 'nope').error, 'invalid')
list = G.addGuest(list, 'sam@example.com').list
assert.strictEqual(list.length, 2)
assert.deepStrictEqual(plain(G.removeGuest(list, 'ANNA@example.com')), [{ email: 'sam@example.com' }])

// people(): rooms and email-less entries (cached self) left out, copies
const room = { email: 'room-1@resource.calendar.google.com', displayName: 'Room 1', resource: true, responseStatus: 'accepted' }
const me = { email: 'me@example.com', self: true, organizer: true, responseStatus: 'accepted' }
const anna = { email: 'anna@example.com', displayName: 'Anna', responseStatus: 'tentative', optional: true }
const bob = { email: 'bob@example.com', responseStatus: 'needsAction' }
const server = [me, anna, room, bob]
const shown = G.people(server)
assert.deepStrictEqual(plain(shown).map((a) => a.email), ['me@example.com', 'anna@example.com', 'bob@example.com'])
assert.notStrictEqual(shown[1], anna, 'copied')
assert.deepStrictEqual(plain(G.people([{ self: true, responseStatus: 'accepted' }])), [], 'cached self entry')
assert.ok(G.hasOtherGuests(server))
assert.ok(!G.hasOtherGuests([me, room]), 'only the user and a room')

// applyChanges: unchanged objects kept, removed dropped, added as { email }, rooms kept
let edited = G.removeGuest(shown, 'Bob@Example.com')
edited = G.addGuest(edited, 'carol@example.com').list
assert.ok(G.emailsDiffer(shown, edited))
assert.ok(!G.emailsDiffer(shown, plain(shown).reverse()), 'order ignored')
let out = plain(G.applyChanges(server, shown, edited))
assert.deepStrictEqual(out, [
	{ email: 'me@example.com', self: true, organizer: true, responseStatus: 'accepted' },
	{ email: 'anna@example.com', displayName: 'Anna', responseStatus: 'tentative', optional: true },
	room,
	{ email: 'carol@example.com' },
])
// A guest the server got meanwhile (added elsewhere) stays; one added in both isn't doubled.
const serverNow = server.concat([{ email: 'dave@example.com' }, { email: 'CAROL@example.com', responseStatus: 'needsAction' }])
out = plain(G.applyChanges(serverNow, shown, edited))
assert.deepStrictEqual(out.map((a) => a.email), ['me@example.com', 'anna@example.com', room.email, 'dave@example.com', 'CAROL@example.com'])
// Server duplicates collapse.
out = plain(G.applyChanges([anna, { email: 'ANNA@example.com' }], [anna], [anna]))
assert.deepStrictEqual(out, [anna])
// No attendees on the server yet.
assert.deepStrictEqual(plain(G.applyChanges(undefined, [], [{ email: 'x@y.z' }])), [{ email: 'x@y.z' }])
assert.deepStrictEqual(plain(G.newAttendees([{ email: 'a@b.cd' }, { email: 'A@B.cd' }])), [{ email: 'a@b.cd' }])

// Known guests: from loaded events, most frequent first, no self / rooms / duplicates
const events = [
	{ attendees: [me, anna, room] },
	{ attendees: [{ email: 'ANNA@example.com' }, bob] },
	{ attendees: null },
	{ summary: 'no guests' },
]
const known = plain(G.knownGuests(events))
assert.deepStrictEqual(known, [
	{ email: 'anna@example.com', name: 'Anna' },
	{ email: 'bob@example.com', name: '' },
])
// ListModel attendees (agenda)
const model = (items) => ({ count: items.length, get: (i) => items[i] })
assert.deepStrictEqual(plain(G.knownGuests([{ attendees: model([bob]) }])), [{ email: 'bob@example.com', name: '' }])

// Suggestions: by email or name, not yet added, limited
assert.deepStrictEqual(plain(G.suggest(known, 'ann', [])), [{ email: 'anna@example.com', name: 'Anna' }])
assert.deepStrictEqual(plain(G.suggest(known, 'EXAMPLE', [])).length, 2)
assert.deepStrictEqual(plain(G.suggest(known, 'example', [{ email: 'Anna@example.com' }])), [{ email: 'bob@example.com', name: '' }])
assert.deepStrictEqual(plain(G.suggest(known, 'example', [], 1)).length, 1)
assert.deepStrictEqual(plain(G.suggest(known, '  ', [])), [])

assert.strictEqual(G.responseIcon('accepted'), 'dialog-ok-apply')
assert.strictEqual(G.responseIcon(undefined), 'clock')

console.log('guests: ok')
