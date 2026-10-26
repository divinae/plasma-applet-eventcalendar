import QtQuick

import "Requests.js" as Requests
import "../ScriptPath.js" as ScriptPath

// Secrets of one scope in the system keyring (Secret Service or KWallet), through
// scripts/secret_store.py: a secret is written or read once through a one-request localhost
// server (store-once / read-once) that writes its port and a one-time token to a ready file, so
// the value is never on a command line. Nothing here logs a value (lengths only, with debugging).
// Like GoogleAccountsStore.storeAccountSecret / loadAccountSecret, for other account kinds.
Item {
	id: keyring
	visible: false

	property string scope: "" // One of secret_store.py's ALLOWED_SCOPES
	property bool debugEnabled: false
	property string secretStorePath: ScriptPath.scriptPath("secret_store.py")

	Logger {
		id: logger
		name: "eventcalendar-keyring"
		showDebug: keyring.debugEnabled
	}

	ExecUtil {
		id: secretExec
	}

	function generateTempFilePath(prefix) {
		var timePart = Date.now().toString(36)
		var randPart = Math.floor(Math.random() * 1000000).toString(36)
		return "/tmp/" + prefix + "-" + timePart + "-" + randPart + ".json"
	}

	function waitForReadyFile(readyFile, callback) {
		secretExec.execArgv([
			"python3",
			secretStorePath,
			"wait-ready",
			"--ready-file",
			readyFile,
			"--timeout",
			"5",
		], function(cmd, exitCode, exitStatus, stdout, stderr) {
			var payload = null
			var trimmed = (stdout || "").trim()
			if (trimmed) {
				try {
					payload = JSON.parse(trimmed)
				} catch (e) {
					payload = null
				}
			}
			if (exitCode === 0 && payload && payload.port && payload.token) {
				callback(null, payload)
				return
			}
			callback((stderr || "").trim() || "Timed out waiting for secret storage helper.")
		})
	}

	function helperArgs(command, accountId, key, readyFile) {
		var args = ["python3", secretStorePath, command, "--scope", scope, "--key", key, "--account-id", accountId]
		if (readyFile) {
			args.push("--ready-file", readyFile)
		}
		return args
	}

	function errorOf(data) {
		var payload = data
		if (typeof payload === "string" && payload) {
			try {
				payload = JSON.parse(payload)
			} catch (e) {
				payload = null
			}
		}
		return payload && payload.error ? String(payload.error) : ""
	}

	// Store value (an empty one clears it). callback(err): optional, always called once.
	function store(accountId, key, value, callback) {
		var finished = false
		function finish(err) {
			if (finished) {
				return
			}
			finished = true
			if (typeof callback === "function") {
				callback(err || null)
			}
		}
		if (!accountId || !scope) {
			finish("Missing account id or scope.")
			return
		}
		if (!value) {
			clear(accountId, key, callback)
			return
		}
		var readyFile = generateTempFilePath("eventcalendar-secret-store")
		logger.debug("store", key, "length", value.length)
		secretExec.execArgv(helperArgs("store-once", accountId, key, readyFile), function(cmd, exitCode, exitStatus, stdout, stderr) {
			logger.debug("store", key, "helper exit", exitCode)
			if (exitCode !== 0) {
				finish((stderr || "").trim() || "Failed to store the secret.")
			}
		})
		waitForReadyFile(readyFile, function(err, payload) {
			if (err) {
				finish(err)
				return
			}
			Requests.postJSON({
				url: "http://127.0.0.1:" + payload.port + "/store",
				headers: {
					"Authorization": "Bearer " + payload.token,
				},
				data: {
					value: value,
				},
			}, function(postErr, data, xhr) {
				logger.debug("store", key, "status", xhr ? xhr.status : 0)
				if (postErr || !data || data.ok !== true) {
					finish(errorOf(data) || postErr || "Failed to store the secret.")
				} else {
					finish(null)
				}
			})
		})
	}

	// callback(err, value), always called once: value "" and err null when the keyring answered
	// that there's no such secret (a definite not-found); err when it couldn't be read (the helper
	// timed out, the keyring is locked or not up yet, ...): try again later.
	function load(accountId, key, callback) {
		if (!accountId || !scope) {
			callback(null, "")
			return
		}
		var readyFile = generateTempFilePath("eventcalendar-secret-read")
		secretExec.execArgv(helperArgs("read-once", accountId, key, readyFile), function(cmd, exitCode, exitStatus, stdout, stderr) {
			logger.debug("load", key, "helper exit", exitCode)
		})
		waitForReadyFile(readyFile, function(err, payload) {
			if (err) {
				logger.debug("load", key, "helper not ready")
				callback("The secret storage helper did not start.", "")
				return
			}
			Requests.getJSON({
				url: "http://127.0.0.1:" + payload.port + "/read",
				headers: {
					"Authorization": "Bearer " + payload.token,
				},
			}, function(readErr, data, xhr) {
				var value = (!readErr && data && data.found && data.value) ? String(data.value) : ""
				logger.debug("load", key, "status", xhr ? xhr.status : 0, "length", value.length)
				if (value) {
					callback(null, value)
				} else if (readErr || !data || typeof data !== "object") {
					callback("Could not read the secret.", "")
				} else if (errorOf(data)) {
					callback(errorOf(data), "")
				} else {
					callback(null, "") // Not found
				}
			})
		})
	}

	// callback(err): optional.
	function clear(accountId, key, callback) {
		if (!accountId || !scope) {
			if (typeof callback === "function") {
				callback("Missing account id or scope.")
			}
			return
		}
		secretExec.execArgv(helperArgs("clear", accountId, key, ""), function(cmd, exitCode, exitStatus, stdout, stderr) {
			if (typeof callback === "function") {
				callback(exitCode === 0 ? null : ((stderr || "").trim() || "Failed to clear the secret."))
			}
		})
	}
}
