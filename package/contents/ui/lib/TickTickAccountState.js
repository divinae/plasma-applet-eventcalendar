// TickTick accounts (config key tickTickAccounts): what's saved, and the servers.
// The API token is never saved here: it lives in the system keyring (scope ticktick-account,
// key token), and only in memory (account.token) once read.

// The Open API servers, by config value. Only these: the token is never sent anywhere else.
var servers = {
	ticktick: { apiUrl: "https://api.ticktick.com/open/v1", webUrl: "https://ticktick.com/webapp/" },
	dida365: { apiUrl: "https://api.dida365.com/open/v1", webUrl: "https://dida365.com/webapp/" },
}

function serverKey(server) {
	return Object.prototype.hasOwnProperty.call(servers, server) ? server : "ticktick"
}
function apiUrl(server) {
	return servers[serverKey(server)].apiUrl
}
function webUrl(server) {
	return servers[serverKey(server)].webUrl
}
function serverName(server) {
	return serverKey(server) === "dida365" ? "Dida365" : "TickTick"
}

function str(value) {
	var type = typeof value
	return type === "string" || type === "number" || type === "boolean" ? String(value) : ""
}

function stringList(value) {
	if (!Array.isArray(value)) {
		return []
	}
	return value.map(str).filter(function(item) { return !!item })
}

// A project as saved: { id, name, color } (color '' when it has none).
function serializableProject(project) {
	return {
		id: str(project && project.id),
		name: str(project && project.name),
		color: str(project && project.color),
	}
}

// The saved fields of an account, nothing else (no token).
function serializeAccount(account) {
	var projects = Array.isArray(account && account.projectList) ? account.projectList : []
	return {
		id: str(account && account.id),
		label: str(account && account.label),
		server: serverKey(account && account.server),
		projectList: projects.map(serializableProject).filter(function(p) { return !!p.id }),
		projectIdList: stringList(account && account.projectIdList),
	}
}

// An account read from config, with its runtime token (from previous, a list of accounts already
// loaded, or ""). Null when it has no id.
function normalizeAccount(account, previous) {
	var safe = serializeAccount(account)
	if (!safe.id) {
		return null
	}
	safe.token = ""
	for (var i = 0; i < (previous || []).length; i++) {
		if (previous[i] && previous[i].id === safe.id && previous[i].token) {
			safe.token = previous[i].token
		}
	}
	return safe
}

// The projects of GET /project that hold tasks: open (not closed / archived) task projects, as
// { id, name, color }.
function taskProjects(projects) {
	if (!Array.isArray(projects)) {
		return []
	}
	return projects.filter(function(p) {
		return p && p.id && !p.closed && (!p.kind || p.kind === "TASK")
	}).map(serializableProject)
}

function generateId() {
	var timePart = Date.now().toString(36)
	var randPart = Math.floor(Math.random() * 1000000).toString(36)
	return "tt_" + timePart + "_" + randPart
}

if (typeof module !== "undefined") {
	module.exports = {
		servers: servers,
		serverKey: serverKey,
		apiUrl: apiUrl,
		webUrl: webUrl,
		serverName: serverName,
		serializeAccount: serializeAccount,
		normalizeAccount: normalizeAccount,
		taskProjects: taskProjects,
		generateId: generateId,
	}
}
