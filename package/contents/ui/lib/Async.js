.pragma library
// Version 1

function _taskCallback(asyncObj, key, err, taskResult) {
	asyncObj.numCompleted += 1
	if (asyncObj.err) {
		// Already reported the first error.
		return
	}
	if (err) {
		asyncObj.err = err
		asyncObj.finalCallback(err)
	} else {
		asyncObj.results[key] = taskResult
		if (asyncObj.numCompleted >= asyncObj.numTasks) {
			asyncObj.finalCallback(null, asyncObj.results)
		}
	}
}

// http://caolan.github.io/async/docs.html#parallel
function parallel(tasks, finalCallback) {
	if (tasks.length == 0) {
		finalCallback(null, [])
	} else {
		var asyncObj = {}
		asyncObj.numTasks = tasks.length // Serialize in case the array changes size
		asyncObj.numCompleted = 0
		asyncObj.err = null
		asyncObj.results = []
		asyncObj.finalCallback = finalCallback

		for (var i = 0; i < tasks.length; i++) {
			var task = tasks[i]
			var taskCallback = _taskCallback.bind(null, asyncObj, i)
			task(taskCallback)
		}
	}
}

// Runs every task(callback(err, data)) at once and waits for all of them, failed ones too.
// done(results): results[i] = { err, data } of tasks[i] (err null when it worked). A task that
// calls back twice counts once.
function settleAll(tasks, done) {
	var results = new Array(tasks.length)
	var pending = tasks.length
	if (pending === 0) {
		done([])
		return
	}
	tasks.forEach(function(task, i) {
		var settled = false
		task(function(err, data) {
			if (settled) {
				return
			}
			settled = true
			results[i] = { err: err || null, data: data }
			pending -= 1
			if (pending === 0) {
				done(results)
			}
		})
	})
}

/*
** Example
*/
// parallel([
// 	function(callback) {
// 		setTimeout(function() {
// 			callback(null, 'one');
// 		}, 200);
// 	},
// 	function(callback) {
// 		setTimeout(function() {
// 			callback(null, 'two');
// 		}, 100);
// 	},
// ], function(err, results) {
// 	console.log('done', results)
// })
