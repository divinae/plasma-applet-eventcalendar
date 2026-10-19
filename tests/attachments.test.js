// Event attachments (package/contents/ui/Attachments.js).
const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const source = fs.readFileSync(path.join(__dirname, '../package/contents/ui/Attachments.js'), 'utf8')
	.replace(/^\.pragma library\s*$/m, '')
const A = {}
vm.runInNewContext(source, A)
const plain = (value) => JSON.parse(JSON.stringify(value))

// MIME type -> theme icon
const icons = {
	'application/pdf': 'application-pdf',
	'APPLICATION/PDF': 'application-pdf',
	'application/vnd.google-apps.document': 'x-office-document',
	'application/vnd.google-apps.spreadsheet': 'x-office-spreadsheet',
	'application/vnd.google-apps.presentation': 'x-office-presentation',
	'application/vnd.google-apps.folder': 'folder',
	'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'x-office-document',
	'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'x-office-spreadsheet',
	'application/vnd.openxmlformats-officedocument.presentationml.presentation': 'x-office-presentation',
	'application/vnd.oasis.opendocument.text': 'x-office-document',
	'image/png': 'image-x-generic',
	'video/mp4': 'video-x-generic',
	'audio/ogg': 'audio-x-generic',
	'application/zip': 'application-x-archive',
	'application/octet-stream': 'text-x-generic',
	'': 'text-x-generic',
}
for (const mime in icons) {
	assert.strictEqual(A.iconForMimeType(mime), icons[mime], mime)
}
assert.strictEqual(A.iconForMimeType(undefined), 'text-x-generic')
assert.strictEqual(A.iconForMimeType(null), 'text-x-generic')

// List: web links only, title falls back to the link
assert.deepStrictEqual(plain(A.list(null)), [])
assert.deepStrictEqual(plain(A.list({})), [])
assert.deepStrictEqual(plain(A.list({ attachments: 'x' })), [])
assert.deepStrictEqual(plain(A.list({ attachments: [
	{ title: 'Agenda', fileUrl: 'https://docs.google.com/document/d/1', mimeType: 'application/vnd.google-apps.document', fileId: '1' },
	{ title: '', fileUrl: ' https://drive.google.com/file/d/2 ', mimeType: 'application/pdf' },
	{ title: 'Evil', fileUrl: 'javascript:alert(1)' },
	{ title: 'Local', fileUrl: 'file:///etc/passwd' },
	{ title: 'No link' },
	null,
] })), [
	{ title: 'Agenda', url: 'https://docs.google.com/document/d/1', icon: 'x-office-document' },
	{ title: 'https://drive.google.com/file/d/2', url: 'https://drive.google.com/file/d/2', icon: 'application-pdf' },
])

console.log('attachments tests passed')
