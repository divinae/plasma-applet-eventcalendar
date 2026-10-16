.pragma library
// Version 8

function request(opt, callback) {
	if (typeof opt === 'string') {
		opt = { url: opt }
	}
	var req = new XMLHttpRequest()
	// Qt can fire both onerror and DONE for a failed request. Only call back once.
	var completed = false
	function responseText() {
		try {
			return req.responseText || null
		} catch (e) {
			return null
		}
	}
	function finish(err, data) {
		if (completed) {
			return
		}
		completed = true
		callback(err, data, req)
	}
	function finishFromResponse() {
		if (200 <= req.status && req.status < 400) {
			finish(null, responseText())
			return
		}
		finish("HTTP Error " + req.status, responseText())
	}
	req.onerror = function() {
		// Network Error / No Connection
		if (req.readyState !== XMLHttpRequest.DONE && req.status !== 0) {
			// Some Qt versions emit error before exposing the HTTP response body.
			// Let the final ready-state event complete the request in that case.
			return
		}
		finishFromResponse()
	}
	// Hung connections (eg: half-dead wifi) fail after 30 s instead of never. Status stays 0.
	req.timeout = opt.timeout || 30000
	req.ontimeout = function() {
		finish("Timeout", null)
	}
	req.onreadystatechange = function() {
		if (req.readyState === XMLHttpRequest.DONE) { // https://xhr.spec.whatwg.org/#dom-xmlhttprequest-done
			finishFromResponse()
		}
	}
	req.open(opt.method || "GET", opt.url, true)
	if (opt.headers) {
		for (var key in opt.headers) {
			req.setRequestHeader(key, opt.headers[key])
		}
	}
	req.send(opt.data)
}

// The request never got an HTTP response: no connection, DNS failure, timeout.
function isNetworkError(xhr) {
	return !xhr || xhr.status === 0
}

function encodeParams(params) {
	var s = ''
	var i = 0
	for (var key in params) {
		if (i > 0) {
			s += '&'
		}
		var value = params[key]
		if (typeof value === "object") {
			// TODO: Flatten obj={list: [1, 2]} as
			// obj[list][0]=1
			// obj[list][1]=2
		}
		s += encodeURIComponent(key) + '=' + encodeURIComponent(value)
		i += 1
	}
	return s
}

function encodeFormData(opt) {
	opt.headers = opt.headers || {}
	opt.headers['Content-Type'] = 'application/x-www-form-urlencoded'
	if (opt.data) {
		opt.data = encodeParams(opt.data)
	}
	return opt
}

function post(opt, callback) {
	if (typeof opt === 'string') {
		opt = { url: opt }
	}
	opt.method = 'POST'
	encodeFormData(opt)
	request(opt, callback)
}

function getJSON(opt, callback) {
	if (typeof opt === 'string') {
		opt = { url: opt }
	}
	opt.headers = opt.headers || {}
	opt.headers['Accept'] = 'application/json'
	request(opt, function(err, data, req) {
		if (!err && data) {
			try {
				data = JSON.parse(data)
			} catch (e) {
				// eg: Captive portal returning HTML with a 200.
				return callback("Invalid JSON response: " + e, data, req)
			}
		}
		callback(err, data, req)
	})
}

function postJSON(opt, callback) {
	if (typeof opt === 'string') {
		opt = { url: opt }
	}
	opt.method = opt.method || 'POST'
	opt.headers = opt.headers || {}
	opt.headers['Content-Type'] = 'application/json'
	if (opt.data) {
		opt.data = JSON.stringify(opt.data)
	}
	getJSON(opt, callback)
}

function getFile(url, callback) {
	var req = new XMLHttpRequest()
	req.onerror = function() {
		// Network Error / No Connection
		console.log('XMLHttpRequest.onerror', req.status)
		var msg = "HTTP Error " + req.status
		callback(msg, null, req)
	}
	req.onreadystatechange = function() {
		if (req.readyState === 4) {
			// Since the file is local, it will have HTTP 0 Unsent.
			callback(null, req.responseText, req)
		}
	}
	req.open("GET", url, true)
	req.send()
}

