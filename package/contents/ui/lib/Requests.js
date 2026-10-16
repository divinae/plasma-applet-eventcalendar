.pragma library
// Version 8

function request(opt, callback) {
	if (typeof opt === 'string') {
		opt = { url: opt }
	}
	var req = new XMLHttpRequest()
	// Qt can fire both onerror and DONE for a failed request. Only call back once.
	var finished = false
	function done(err, data) {
		if (finished) {
			return
		}
		finished = true
		callback(err, data, req)
	}
	req.onerror = function() {
		// Network Error / No Connection
		done("HTTP Error " + req.status, null)
	}
	req.onreadystatechange = function() {
		if (req.readyState === XMLHttpRequest.DONE) { // https://xhr.spec.whatwg.org/#dom-xmlhttprequest-done
			if (200 <= req.status && req.status < 400) {
				done(null, req.responseText)
			} else {
				done("HTTP Error " + req.status, req.responseText)
			}
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

