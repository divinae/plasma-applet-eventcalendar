import QtQuick

// A menu (or other popup) made from component the first time it's needed (get()), then kept: a
// Menu and its items for every row or view, made up front, took much of the time views needed to
// open. object: the menu once made (null before), eg: for its opened state.
QtObject {
	id: lazyMenu

	property Component component: null
	property Item parentItem: null
	property var object: null

	function get() {
		if (!object && component) {
			object = component.createObject(parentItem)
		}
		return object
	}
}
