import QtQuick

// Compiles every QML file of the package (resolving all imports) and exits non-zero on errors.
// Run through tests/qml_compile.sh, which passes the ui folder URL and the file list:
//   qml6 tests/qml_compile.qml -- file:///…/package/contents/ui/ AgendaView.qml …
Item {
	Component.onCompleted: {
		var args = Qt.application.arguments
		var separator = args.indexOf("--")
		var rest = separator >= 0 ? args.slice(separator + 1) : []
		var base = rest[0]
		var files = rest.slice(1)
		var bad = 0
		for (var i = 0; i < files.length; i++) {
			var component = Qt.createComponent(base + files[i], Component.PreferSynchronous)
			if (component.status === Component.Error) {
				bad++
				console.log("ERROR", files[i], component.errorString().split("\n").slice(0, 3).join(" | "))
			}
		}
		console.log("compiled", files.length, "files,", bad, "with errors")
		Qt.exit(files.length > 0 && bad === 0 ? 0 : 1)
	}
}
