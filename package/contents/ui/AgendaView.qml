import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

import "Shared.js" as Shared

Item {
	id: agendaView

	signal newEventFormOpened(var agendaItem, var calendarSelector)
	signal submitNewEventForm(string calendarId, var date, string text)
	// Scrolled to the end: the next month below (Logic.loadMoreAgenda).
	signal endReached()
	// The first day in sight at the top of the list (the small month beside it follows it).
	property date topDate: new Date(NaN)
	function updateTopDate() {
		var index = agendaList.indexAt(0, agendaList.contentY + 1)
		if (index < 0) {
			index = agendaList.indexAt(0, agendaList.contentY + agendaList.spacing + 1)
		}
		var agendaItem = index >= 0 && index < root.agendaModel.count ? root.agendaModel.get(index) : null
		if (agendaItem && agendaItem.date && agendaItem.date.getTime() !== topDate.getTime()) {
			topDate = agendaItem.date
		}
	}

	// The days in a ListView: only the days in sight (and a screen's worth around them) are
	// built, not the whole month at once (a busy calendar has hundreds of event tiles; building
	// them all froze Plasma, issue #3). The thin scroll bar over the days' right edge.
	ListView {
		id: agendaList
		anchors.fill: parent
		clip: true
		model: root.agendaModel
		spacing: appletConfig.islands ? appletConfig.cardGap : appletConfig.agendaDaySpacing
		cacheBuffer: Math.max(0, height)
		boundsBehavior: Flickable.StopAtBounds
		// At the end after scrolling (not a short list that fits): the next month.
		onContentYChanged: agendaView.updateTopDate()
		onCountChanged: Qt.callLater(agendaView.updateTopDate)
		onAtYEndChanged: {
			if (atYEnd && contentHeight > height && count > 0) {
				agendaView.endReached()
			}
		}
		// Not flicked with the mouse (as Plasma's ScrollView); wheel and touchpad as there.
		interactive: Kirigami.Settings.hasTransientTouchInput
		QQC2.ScrollBar.vertical: OverlayScrollBar {}
		Kirigami.WheelHandler {
			target: agendaList
			filterMouseEvents: true
			keyNavigationEnabled: false
		}

		delegate: AgendaListItem {
			// As wide as the list. Not width: parent.width, the parent is null while a delegate
			// is removed.
			width: ListView.view ? ListView.view.width : 0
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
			agendaList.positionViewAtIndex(itemIndex, ListView.Beginning)
		}
	}

	function scrollToDate(date) {
		for (var i = 0; i < root.agendaModel.count; i++) {
			var agendaItem = root.agendaModel.get(i)
			if (Shared.isSameDate(date, agendaItem.date)) {
				agendaList.positionViewAtIndex(i, ListView.Beginning)
				scrollToIndexTimer.scrollTo(i)
				return
			} else if (Shared.isDateEarlier(date, agendaItem.date)) {
				// If the date is smaller than the current agendaItem.date, scroll to the previous agendaItem.
				if (i > 0) {
					agendaList.positionViewAtIndex(i-1, ListView.Beginning)
					scrollToIndexTimer.scrollTo(i-1)
				} else {
					agendaList.positionViewAtBeginning()
				}
				return
			}
		}
		// If the date is greater than any item in the agenda, scroll to the bottom.
		agendaList.positionViewAtEnd()
	}
}
