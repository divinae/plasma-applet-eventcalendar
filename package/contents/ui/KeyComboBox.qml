import QtQuick

// A combo box over [{ key, text }] showing `currentKey`. The user's pick comes as picked(key);
// the shown item then follows currentKey again (a plain currentIndex binding is lost once the
// user picks, so later changes of the key would no longer show).
FormComboBox {
	id: combo

	property string currentKey: ""
	signal picked(string key)

	textRole: "text"

	function syncIndex() {
		var list = model || []
		for (var i = 0; i < list.length; i++) {
			if (list[i].key === currentKey) {
				currentIndex = i
				return
			}
		}
		currentIndex = -1
	}
	onCurrentKeyChanged: syncIndex()
	// Again once the combo box took the new model (it can reset the index after this handler).
	onModelChanged: {
		syncIndex()
		Qt.callLater(syncIndex)
	}
	Component.onCompleted: syncIndex()
	onActivated: function(index) {
		picked(model[index].key)
		syncIndex() // When the pick didn't change currentKey
	}
}
