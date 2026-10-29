.pragma library

.import "../lib/Requests.js" as Requests

// Weather service requests, shared by all the widgets in plasmashell (a library is loaded once
// per QML engine):
// - A response is reused for MAX_AGE: by the other widgets, and by the updates that don't wait for
//   the hourly one (the popup's view switches, its first open, ...). Requests for one URL running
//   at once are sent once.
// - A daily budget per service, a safety net for runaway updates and many widgets: past it, a URL
//   is requested at most once per LIMITED_MAX_AGE, the older response is shown meanwhile.
var MAX_AGE = 10 * 60 * 1000
var LIMITED_MAX_AGE = 60 * 60 * 1000

var cache = {} // url -> { at, data }
var pending = {} // url -> [callbacks]
var budget = { day: '', counts: {}, warned: {} }

function now() {
	return Date.now()
}

function dayOf(ms) {
	var d = new Date(ms)
	return d.getFullYear() + '-' + (d.getMonth() + 1) + '-' + d.getDate()
}

// Network requests sent today (not the cached answers).
function requestsToday(service) {
	if (budget.day !== dayOf(now())) {
		return 0
	}
	return budget.counts[service] || 0
}

function countRequest(service) {
	var day = dayOf(now())
	if (budget.day !== day) {
		budget = { day: day, counts: {}, warned: {} }
	}
	budget.counts[service] = (budget.counts[service] || 0) + 1
}

function pruneCache(at) {
	for (var url in cache) {
		if (at - cache[url].at >= LIMITED_MAX_AGE) {
			delete cache[url]
		}
	}
}

// opt: { service, url, dailyLimit, errorOf: function(data) -> error message or '' (optional) }
// callback(err, data, xhr); xhr is null for a cached answer.
function getJSON(opt, callback) {
	var url = opt.url
	var at = now()
	var cached = cache[url]
	var overBudget = requestsToday(opt.service) >= opt.dailyLimit
	var maxAge = overBudget ? LIMITED_MAX_AGE : MAX_AGE
	if (overBudget && !budget.warned[opt.service]) {
		budget.warned[opt.service] = true
		console.warn('[eventcalendar]', opt.service, 'made', requestsToday(opt.service), 'requests today: at most one an hour from now on')
	}
	if (cached && at - cached.at < maxAge) {
		return callback(null, cached.data, null)
	}
	if (pending[url]) {
		pending[url].push(callback)
		return
	}
	pending[url] = [callback]
	countRequest(opt.service)
	Requests.getJSON({ url: url }, function(err, data, xhr) {
		if (!err && opt.errorOf) {
			err = opt.errorOf(data) || null
		}
		if (!err) {
			pruneCache(at)
			cache[url] = { at: now(), data: data }
		}
		var callbacks = pending[url]
		delete pending[url]
		for (var i = 0; i < callbacks.length; i++) {
			callbacks[i](err, data, xhr)
		}
	})
}
