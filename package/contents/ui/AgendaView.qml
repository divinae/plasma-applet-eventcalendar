import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3

import "Shared.js" as Shared

Item {
	id: agendaView

	signal newEventFormOpened(var agendaItem, var calendarSelector)
	signal submitNewEventForm(string calendarId, var date, string text)

	// No separator line next to the scrollbar (both the desktop style and Breeze draw one).
	PlasmaComponents3.ScrollView {
		id: agendaScrollView
		anchors.fill: parent
		QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff
		// Keep Plasma's own (positioned) scrollbar, just without its separator line: a replacement
		// scrollbar isn't laid out by the ScrollView and showed as a dot in the corner.
		Component.onCompleted: {
			var bar = QQC2.ScrollBar.vertical
			for (var i = 0; bar && i < bar.children.length; i++) {
				var child = bar.children[i]
				if (child !== bar.background && child !== bar.contentItem && child.implicitWidth === 1 && child.implicitHeight === 1) {
					child.visible = false // The 1 px separator Breeze draws next to the scrollbar
				}
			}
		}
		readonly property int viewportWidth: contentItem ? contentItem.width : width
		readonly property int viewportHeight: contentItem ? contentItem.height : height
		readonly property int scrollY: contentItem ? contentItem.contentY : 0
		readonly property int contentHeightValue: contentItem ? contentItem.contentHeight : 0

		ColumnLayout {
			id: agendaColumn
			width: agendaScrollView.viewportWidth
			spacing: appletConfig.islands ? appletConfig.cardGap : appletConfig.agendaDaySpacing

			Repeater {
				id: agendaRepeater
				model: root.agendaModel
				delegate: AgendaListItem {
					width: parent.width
					// Islands: the day cards as wide as the column (not as their content).
					Layout.fillWidth: appletConfig.islands
				}
			}
		}

		function getItemOffsetY(index) {
			if (index <= 0) {
				return 0
			} else if (index < agendaRepeater.count) {
				var offsetY = 0
				for (var i = 0; i < Math.min(index, agendaRepeater.count); i++) {
					var agendaListItem = agendaRepeater.itemAt(i)
					offsetY += agendaListItem ? agendaListItem.height : 0
					if (i != agendaRepeater.count-1) {
						offsetY += agendaColumn.spacing
					}
				}
				return offsetY
			} else { // index >= agendaRepeater.count
				return agendaScrollView.contentHeightValue
			}
		}

		function scrollToY(offsetY) {
			if (contentItem) {
				contentItem.contentY = Math.min(offsetY, contentHeightValue - viewportHeight)
			}
		}

		function positionViewAtBeginning() {
			scrollToY(0)
		}

		function positionViewAtIndex(i) {
			var offsetY = getItemOffsetY(i)
			scrollToY(offsetY)
		}

		function positionViewAtEnd() {
			scrollToY(contentHeightValue)
		}
	}

	// TODO: properly detect when all events have completed loading
	Timer {
		id: scrollToIndexTimer
		property int itemIndex: -1
		interval: 400 // Give events time to populate
		onTriggered: updatePosition()
		function scrollTo(i) {
			itemIndex = i
			restart()
		}
		function updatePosition() {
			agendaScrollView.positionViewAtIndex(itemIndex)
		}
	}

	function scrollToDate(date) {
		for (var i = 0; i < root.agendaModel.count; i++) {
			var agendaItem = root.agendaModel.get(i)
			if (Shared.isSameDate(date, agendaItem.date)) {
				agendaScrollView.positionViewAtIndex(i)
				scrollToIndexTimer.scrollTo(i)
				return
			} else if (Shared.isDateEarlier(date, agendaItem.date)) {
				// If the date is smaller than the current agendaItem.date, scroll to the previous agendaItem.
				if (i > 0) {
					agendaScrollView.positionViewAtIndex(i-1)
					scrollToIndexTimer.scrollTo(i-1)
				} else {
					agendaScrollView.positionViewAtBeginning()
				}
				return
			}
		}
		// If the date is greater than any item in the agenda, scroll to the bottom.
		agendaScrollView.positionViewAtEnd()
	}
}
