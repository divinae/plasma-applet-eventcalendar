.pragma library

// File attachments of Google events (event.attachments: [{ title, fileUrl, mimeType, iconLink,
// fileId }], Drive files). Pure functions, tested in tests/attachments.test.js.
// Not kept in the disk cache (EventCacheUtil.pickEvent): shown from the fetched events only.

// Theme icon for a MIME type; text-x-generic when unknown.
function iconForMimeType(mimeType) {
	var mime = String(mimeType || '').toLowerCase()
	var exact = {
		'application/pdf': 'application-pdf',
		'application/vnd.google-apps.folder': 'folder',
		'application/vnd.google-apps.document': 'x-office-document',
		'application/vnd.google-apps.spreadsheet': 'x-office-spreadsheet',
		'application/vnd.google-apps.presentation': 'x-office-presentation',
		'application/vnd.google-apps.drawing': 'image-x-generic',
		'application/vnd.google-apps.form': 'x-office-document',
		'application/msword': 'x-office-document',
		'application/rtf': 'x-office-document',
		'application/vnd.ms-excel': 'x-office-spreadsheet',
		'text/csv': 'x-office-spreadsheet',
		'application/vnd.ms-powerpoint': 'x-office-presentation',
		'application/zip': 'application-x-archive',
		'application/x-zip-compressed': 'application-x-archive',
		'application/x-7z-compressed': 'application-x-archive',
		'application/x-tar': 'application-x-archive',
		'application/gzip': 'application-x-archive',
	}
	if (exact[mime]) {
		return exact[mime]
	}
	// Office Open XML and OpenDocument
	if (/wordprocessingml|opendocument\.text/.test(mime)) {
		return 'x-office-document'
	}
	if (/spreadsheetml|opendocument\.spreadsheet/.test(mime)) {
		return 'x-office-spreadsheet'
	}
	if (/presentationml|opendocument\.presentation/.test(mime)) {
		return 'x-office-presentation'
	}
	if (/^image\//.test(mime)) {
		return 'image-x-generic'
	}
	if (/^video\//.test(mime)) {
		return 'video-x-generic'
	}
	if (/^audio\//.test(mime)) {
		return 'audio-x-generic'
	}
	return 'text-x-generic'
}

// Attachments to list: [{ title, url, icon }]. Only web links (they open in the browser); the
// title falls back to the link.
function list(event) {
	var attachments = event && event.attachments
	if (!attachments || typeof attachments.length !== 'number') {
		return []
	}
	var result = []
	for (var i = 0; i < attachments.length; i++) {
		var attachment = attachments[i]
		var url = attachment ? String(attachment.fileUrl || '').trim() : ''
		if (!/^https?:\/\/\S+$/i.test(url)) {
			continue
		}
		result.push({
			title: String(attachment.title || '').trim() || url,
			url: url,
			icon: iconForMimeType(attachment.mimeType),
		})
	}
	return result
}
