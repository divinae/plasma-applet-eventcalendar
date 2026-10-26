import QtQuick

import "../lib"
import "../lib/Requests.js" as Requests
import "../lib/TickTickAccountState.js" as TickTickAccountState

// One TickTick account's Open API access: the server and the API token (from the keyring, see
// TickTickAccountsStore). https://developer.ticktick.com/docs/openapi.md
// Only the HTTP status is logged: never the token, ids, titles, notes or bodies.
Item {
	id: session
	visible: false

	property string server: "ticktick"
	property string apiUrl: TickTickAccountState.apiUrl(server) // Not readonly: tests point it at a mock
	property string token: ""
	property bool debugEnabled: typeof plasmoid !== "undefined" && plasmoid && plasmoid.configuration
		? !!plasmoid.configuration.debugging
		: false

	Logger {
		id: logger
		name: "eventcalendar-ticktick"
		showDebug: session.debugEnabled
	}

	// One request. path: after /open/v1, ids encoded. body: JSON body (not for GET / DELETE).
	// callback(err, data, xhr), always called. Without a token: xhr is null.
	function request(method, path, body, callback) {
		if (!token) {
			callback("No TickTick token", null, null)
			return
		}
		var opt = {
			method: method,
			url: apiUrl + path,
			headers: {
				"Authorization": "Bearer " + token,
			},
		}
		var send = Requests.getJSON
		if (method !== 'GET') {
			// No body: an empty one (Qt sends "undefined" for an undefined body).
			opt.data = (typeof body !== 'undefined' && body !== null) ? body : ""
			send = Requests.postJSON
		}
		send(opt, function(err, data, xhr) {
			logger.debug('TickTick', method, 'response', xhr && xhr.status)
			callback(err, data, xhr)
		})
	}

	// The projects that hold tasks, the Inbox first when the server has one:
	// callback(err, projects [{ id, name, color }], xhr), always called. The Inbox is
	// { id: 'inbox', name: inboxName }; when /project/inbox/data fails it's left out.
	function fetchProjects(inboxName, callback) {
		request('GET', '/project', null, function(err, data, xhr) {
			if (err || !Array.isArray(data)) {
				callback(err || 'Invalid project list', null, xhr)
				return
			}
			var projects = TickTickAccountState.taskProjects(data)
			request('GET', '/project/inbox/data', null, function(inboxErr, inboxData, inboxXhr) {
				if (!inboxErr && inboxData) {
					projects.unshift({ id: 'inbox', name: inboxName, color: '' })
				}
				callback(null, projects, xhr)
			})
		})
	}
}
