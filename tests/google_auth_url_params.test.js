// Regression: Google rejects a repeated parameter ("OAuth 2 parameters can only have a single value: state").
// Every OAuth parameter must appear once in the authorization URL.
const fs = require('fs')
const src = fs.readFileSync(require("path").join(__dirname, "../package/contents/ui/config/GoogleLoginManager.qml"), "utf8")
const body = src.slice(src.indexOf('function buildAuthorizationUrl(ctx) {'))
const fn = body.slice(0, body.indexOf('\n\t}\n') + 3).replace('function buildAuthorizationUrl(ctx)', 'function f(ctx)')
const f = new Function(fn + '; return f')()
const url = f({ redirectUri: 'http://127.0.0.1:53682/', clientId: 'id', state: 'abc', pkceChallenge: 'ch' })
const keys = url.split('?')[1].split('&').map(p => p.split('=')[0])
const dup = keys.filter((k, i) => keys.indexOf(k) !== i)
console.log(dup.length ? 'DUPLICATE: ' + dup : 'ok, params: ' + keys.join(','))
process.exit(dup.length ? 1 : 0)
