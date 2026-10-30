// Links in a title shown by their ticket's name (package/contents/ui/Shared.js linkShortName, linkifiedText).
const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const source = fs.readFileSync(path.join(__dirname, '../package/contents/ui/Shared.js'), 'utf8')
	.replace(/^\.pragma library\s*$/m, '')
	.replace(/^\.import .*$/mg, '')
const S = {}
vm.runInNewContext(source, S)

const short = S.linkShortName
assert.strictEqual(short('https://example.atlassian.net/browse/CSS-2175'), 'CSS-2175')
assert.strictEqual(short('https://example.atlassian.net/browse/CSS-2175?focusedCommentId=1'), 'CSS-2175')
assert.strictEqual(short('https://example.atlassian.net/jira/software/projects/CSS/boards/1?selectedIssue=CSS-9'), 'CSS-9')
assert.strictEqual(short('https://linear.app/acme/issue/ENG-12/fix-login'), 'ENG-12')
assert.strictEqual(short('https://github.com/divinae/plasma-applet-eventcalendar/issues/3'), 'plasma-applet-eventcalendar#3')
assert.strictEqual(short('https://github.com/divinae/plasma-applet-eventcalendar/pull/5'), 'plasma-applet-eventcalendar#5')
assert.strictEqual(short('https://gitlab.com/group/app/-/merge_requests/7'), 'app!7')
assert.strictEqual(short('https://gitlab.com/group/app/-/issues/8'), 'app#8')
assert.strictEqual(short('https://example.com/page'), '')
assert.strictEqual(short(null), '')

const linked = S.linkifiedText
assert.strictEqual(linked('https://example.atlassian.net/browse/CSS-2175'),
	'<a href="https://example.atlassian.net/browse/CSS-2175">CSS-2175</a>')
assert.strictEqual(linked('Review <b> https://example.atlassian.net/browse/CSS-1, then ship'),
	'Review &lt;b&gt; <a href="https://example.atlassian.net/browse/CSS-1">CSS-1</a>, then ship', 'escaped, punctuation left out')
assert.strictEqual(linked('See https://example.com/a?x=1&y=2'), 'See <a href="https://example.com/a?x=1&y=2">https://example.com/a?x=1&amp;y=2</a>')
assert.strictEqual(linked('No link here'), '')
assert.strictEqual(linked('javascript:alert(1)'), '')

console.log('PASS title_links')
