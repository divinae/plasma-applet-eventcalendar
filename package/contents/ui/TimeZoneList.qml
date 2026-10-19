import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

import "TimeZone.js" as TimeZone

// A list of IANA time zones matching `query` (eg: typed in a search field next to it), with
// their offset at `referenceTime`. Up / Down / Enter in the search field: moveUp(), moveDown(),
// pickCurrent().
ListView {
	id: zoneList

	property string query: ""
	property string currentZone: ""
	property double referenceTime: Date.now()
	property int maxResults: 500
	signal picked(string zone)

	clip: true
	boundsBehavior: Flickable.StopAtBounds
	implicitHeight: Kirigami.Units.gridUnit * 8
	currentIndex: 0
	keyNavigationEnabled: false
	readonly property var zones: TimeZone.search(query, maxResults, currentZone)
	model: zones
	onZonesChanged: currentIndex = Math.max(0, zones.indexOf(currentZone))
	highlightMoveDuration: 0
	onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

	QQC2.ScrollBar.vertical: QQC2.ScrollBar {}

	function moveUp() {
		currentIndex = Math.max(0, currentIndex - 1)
	}
	function moveDown() {
		currentIndex = Math.min(count - 1, currentIndex + 1)
	}
	function pickCurrent() {
		if (currentIndex >= 0 && currentIndex < count) {
			picked(zones[currentIndex])
		}
	}

	delegate: MouseArea {
		id: zoneDelegate
		readonly property string zone: modelData
		readonly property bool isCurrent: ListView.isCurrentItem
		width: ListView.view.width - (zoneList.QQC2.ScrollBar.vertical.visible ? zoneList.QQC2.ScrollBar.vertical.width : 0)
		height: Math.round(Kirigami.Units.gridUnit * 1.6)
		hoverEnabled: true
		cursorShape: Qt.PointingHandCursor
		onClicked: zoneList.picked(zone)

		Rectangle {
			anchors.fill: parent
			radius: Kirigami.Units.cornerRadius
			color: Kirigami.Theme.highlightColor
			opacity: zoneDelegate.isCurrent ? 0.3 : (zoneDelegate.containsMouse ? 0.15 : 0)
		}
		QQC2.Label {
			anchors.left: parent.left
			anchors.right: offsetLabel.left
			anchors.leftMargin: Kirigami.Units.smallSpacing
			anchors.verticalCenter: parent.verticalCenter
			elide: Text.ElideRight
			color: Kirigami.Theme.textColor
			font.bold: zoneDelegate.zone === zoneList.currentZone
			text: zoneDelegate.zone.replace(/_/g, ' ')
		}
		QQC2.Label {
			id: offsetLabel
			anchors.right: parent.right
			anchors.rightMargin: Kirigami.Units.smallSpacing
			anchors.verticalCenter: parent.verticalCenter
			color: Kirigami.Theme.textColor
			opacity: 0.7
			text: {
				var offset = TimeZone.offsetAt(zoneDelegate.zone, zoneList.referenceTime)
				var abbr = TimeZone.abbreviation(zoneDelegate.zone, zoneList.referenceTime)
				var gmt = offset === null ? '' : 'GMT' + TimeZone.offsetText(offset)
				return abbr && abbr.indexOf('GMT') !== 0 ? abbr + ' · ' + gmt : gmt
			}
		}
	}
}
