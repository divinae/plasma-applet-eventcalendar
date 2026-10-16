import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "lib"
import "Shared.js" as Shared
import "LocaleFuncs.js" as LocaleFuncs

Item {
	id: agendaView

	property color isOverdueColor: Kirigami.Theme.negativeTextColor
	property int isOverdueFontWeight: Font.Bold

	signal newEventFormOpened(var agendaItem, var calendarSelector)
	signal submitNewEventForm(string calendarId, var date, string text)

	// No separator line next to the scrollbar (both the desktop style and Breeze draw one).
	PlasmaComponents3.ScrollView {
		id: agendaScrollView
		anchors.fill: parent
		QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff
		QQC2.ScrollBar.vertical: PlainScrollBar {}
		readonly property int viewportWidth: contentItem ? contentItem.width : width
		readonly property int viewportHeight: contentItem ? contentItem.height : height
		readonly property int scrollY: contentItem ? contentItem.contentY : 0
		readonly property int contentHeightValue: contentItem ? contentItem.contentHeight : 0

		ColumnLayout {
			id: agendaColumn
			width: agendaScrollView.viewportWidth
			spacing: appletConfig.agendaDaySpacing

			Repeater {
				id: agendaRepeater

				property bool populated: false
				model: root.agendaModel
				delegate: AgendaListItem {
					width: parent.width
				}

				function onItemAdded(index, item) {
					if (index === root.agendaModel.count-1) {
						populated = true
					}
				}
				function onItemRemoved(index, item) {
					populated = false
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

		function positionViewAtEvent(agendaItemIndex, eventIndex) {
			var offsetY = getItemOffsetY(agendaItemIndex)
			var agendaListItem = agendaRepeater.itemAt(agendaItemIndex)
			offsetY += agendaListItem.getEventOffset(eventIndex)
			scrollToY(offsetY)
		}

		function positionViewAtTask(agendaItemIndex, taskIndex) {
			var offsetY = getItemOffsetY(agendaItemIndex)
			var agendaListItem = agendaRepeater.itemAt(agendaItemIndex)
			var eventIndex = agendaListItem.agendaItemEvents.count + taskIndex
			offsetY += agendaListItem.getEventOffset(eventIndex)
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

	function scrollToTop() {
		agendaScrollView.positionViewAtBeginning()
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
