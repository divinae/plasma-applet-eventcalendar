import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras

import "lib"
import "EventBuckets.js" as EventBuckets
import "Shared.js" as Shared
import "Undo.js" as Undo
import "./weather/WeatherApi.js" as WeatherApi

MouseArea {
	id: popup

	// Right clicks too: otherwise Plasma shows the widget's context menu over the open popup.
	// Items with their own right-click menu (agenda events) sit on top and still get theirs.
	acceptedButtons: Qt.LeftButton | Qt.RightButton
	onClicked: function(mouse) {
		if (mouse.button === Qt.LeftButton) {
			focus = true
		}
	}

	property int padding: 0
	property bool showPinButton: false // Assigned in main.qml
	property int spacing: 10

	property real screenWidth: Screen.width > 0 ? Screen.width : plasmoid.screenGeometry.width
	property real screenHeight: Screen.height > 0 ? Screen.height : plasmoid.screenGeometry.height
	property real widthScale: Math.max(1, screenWidth / 1920)
	property real heightScale: Math.max(1, screenHeight / 1080)

	property int topRowHeight: Math.round(plasmoid.configuration.topRowHeight * heightScale)
	// All views share one size (Settings > Views).
	property int bottomRowHeight: Math.round(plasmoid.configuration.monthModeHeight * heightScale)
	property int singleColumnMonthViewHeight: Math.round(plasmoid.configuration.monthHeightSingleColumn * heightScale)

	// DigitalClock LeftColumn minWidth: Kirigami.Units.gridUnit * 22
	// DigitalClock RightColumn minWidth: Kirigami.Units.gridUnit * 14
	// 14/(22+14) * 400 = 156
	// rightColumnWidth=156 looks nice but is very thin for listing events + date + weather.
	property int leftColumnWidth: Math.round(plasmoid.configuration.monthModeWidth * widthScale) // Meteogram + MonthView
	property int rightColumnWidth: Math.round(plasmoid.configuration.rightColumnWidth * widthScale) // TimerView + AgendaView

	property int singleColumnWidth: {
		if (hourGridMode) {
			return leftColumnWidth
		}
		if (showAgenda && showCalendar) {
			return Math.max(leftColumnWidth, rightColumnWidth)
		} else if (showCalendar) {
			return leftColumnWidth
		} else if (showAgenda) {
			return leftColumnWidth
		}

		var width = 0
		if (showMeteogram) {
			width = Math.max(width, leftColumnWidth)
		}
		if (showTimer) {
			width = Math.max(width, rightColumnWidth)
		}
		return width
	}

	property int singleColumnHeight: {
		if (hourGridMode) {
			return bottomRowHeight + viewTabsHeight
		}
		var rows = []
		if (showMeteogram) {
			rows.push(topRowHeight)
		}
		if (showTimer) {
			rows.push(topRowHeight)
		}
		if (showCalendar || showAgenda) {
			rows.push(bottomRowHeight)
		}
		var h = viewTabsHeight
		for (var i = 0; i < rows.length; i++) {
			h += rows[i]
		}
		if (rows.length > 1) {
			h += spacing * (rows.length - 1)
		}
		return h
	}

	property bool singleColumn: !showAgenda || !showCalendar
	property bool singleColumnFullHeight: !plasmoid.configuration.twoColumns && showAgenda && showCalendar
	property bool twoColumns: plasmoid.configuration.twoColumns && showAgenda && showCalendar

	Layout.minimumWidth: {
		if (twoColumns) {
			return Kirigami.Units.gridUnit * 28
		} else {
			return Kirigami.Units.gridUnit * 14
		}
	}
	Layout.preferredWidth: {
		if (twoColumns) {
			return (leftColumnWidth + spacing + rightColumnWidth) + padding * 2
		} else {
			return singleColumnWidth + padding * 2
		}
	}

	Layout.minimumHeight: Kirigami.Units.gridUnit * 14
	Layout.preferredHeight: {
		if (singleColumnFullHeight) {
			return plasmoid.screenGeometry.height
		} else if (singleColumn) {
			return singleColumnHeight + padding * 2
		} else { // twoColumns
			var h = bottomRowHeight + viewTabsHeight // showAgenda || showCalendar
			if (showMeteogram || showTimer) {
				h += spacing + topRowHeight
			}
			return h + padding * 2
		}
	}

	property var eventModel
	property var agendaModel

	// Month mode: only a full month view with event titles, like mobile calendar apps.
	// Week mode: only the week view. Both use the month/week popup size.
	readonly property bool monthMode: plasmoid.configuration.popupMode === 'month'
	readonly property bool weekMode: plasmoid.configuration.popupMode === 'week'
	readonly property bool dayMode: plasmoid.configuration.popupMode === 'today'
	readonly property bool hourGridMode: weekMode || dayMode // Both use WeekView
	readonly property bool fullViewMode: monthMode || hourGridMode
	property bool showMeteogram: plasmoid.configuration.widgetShowMeteogram && !fullViewMode
	property bool showTimer: plasmoid.configuration.widgetShowTimer && !fullViewMode
	// The agenda view is the agenda list only (plus optional meteogram / timer); the month view
	// is the calendar.
	property bool showAgenda: !fullViewMode
	property bool showCalendar: monthMode
	readonly property bool showViewTabs: plasmoid.configuration.showViewTabs
	// The agenda view (and its meteogram / timer) is a list: cap its width and center it.
	readonly property real agendaMaxWidth: Kirigami.Units.gridUnit * 32
	// Month and week views put the top bar inside their header row, the agenda layout above.
	readonly property int viewTabsHeight: header.implicitHeight + spacing
		+ (errorBanner.visible ? errorBanner.implicitHeight + Kirigami.Units.smallSpacing : 0)
	property bool agendaScrollOnSelect: true
	property bool agendaScrollOnMonthChange: false

	property alias today: monthView.today
	property alias selectedDate: monthView.currentDate
	property alias monthViewDate: monthView.displayedDate

	Connections {
		target: monthView
		function onDateSelected(date) {
			scrollToSelection()
		}
	}
	function scrollToSelection() {
		if (!agendaScrollOnSelect) {
			return
		}

		if (true) {
			agendaView.scrollToDate(selectedDate)
		} else {
			agendaView.scrollToTop()
		}
	}

	Component.onCompleted: deferredUpdateUI()

	onMonthViewDateChanged: {
		logger.debug('onMonthViewDateChanged', monthViewDate)
		var startOfMonth = new Date(monthViewDate)
		startOfMonth.setDate(1)
		var prevMonth = agendaModel.currentMonth
		var monthChanged = !prevMonth
			|| prevMonth.getFullYear() !== startOfMonth.getFullYear()
			|| prevMonth.getMonth() !== startOfMonth.getMonth()
		agendaModel.currentMonth = new Date(startOfMonth)
		if (agendaScrollOnMonthChange) {
			selectedDate = startOfMonth
		}
		// Opening the popup or picking a day / "today" in the same month keeps the month:
		// nothing to fetch or rebuild. (A newly created popup fills itself in Component.onCompleted.)
		if (monthChanged) {
			logic.updateEvents()
		}
	}

	onStateChanged: {
	}
	states: [
		State {
			name: "calendar"
			when: !popup.showAgenda && popup.showCalendar && !popup.showMeteogram && !popup.showTimer

			PropertyChanges { target: popup
				// Use the same size as the digitalclock popup
				// since we don't need more space to fit more agenda items.
				Layout.preferredWidth: 378 * popup.widthScale
				Layout.preferredHeight: 378 * popup.heightScale
			}
			PropertyChanges { target: monthView
				Layout.preferredWidth: -1
				Layout.preferredHeight: -1
			}
		},
		State {
			name: "twoColumns+agenda+month"
			when: popup.twoColumns && popup.showAgenda && popup.showCalendar && !popup.showMeteogram && !popup.showTimer

			PropertyChanges { target: widgetGrid
				columns: 2
				rows: 1
			}
		},
		State {
			name: "twoColumns+meteogram+agenda+month"
			when: popup.twoColumns && popup.showAgenda && popup.showCalendar && popup.showMeteogram && !popup.showTimer

			PropertyChanges { target: widgetGrid
				columns: 2
				rows: 2
			}
			PropertyChanges { target: meteogramView
				Layout.columnSpan: 2
			}
		},
		State {
			name: "twoColumns+timer+agenda+month"
			when: popup.twoColumns && popup.showAgenda && popup.showCalendar && !popup.showMeteogram && popup.showTimer

			PropertyChanges { target: widgetGrid
				columns: 2
				rows: 2
			}
			AnchorChanges { target: timerView
				anchors.top: widgetGrid.top
				anchors.left: widgetGrid.left
			}
			AnchorChanges { target: monthView
				anchors.top: timerView.bottom
				anchors.left: widgetGrid.left
				anchors.bottom: widgetGrid.bottom
			}
			PropertyChanges { target: monthView
				anchors.topMargin: widgetGrid.rowSpacing
			}
			AnchorChanges { target: agendaView
				anchors.top: widgetGrid.top
				anchors.right: widgetGrid.right
				anchors.bottom: widgetGrid.bottom
			}
		},
		State {
			name: "twoColumns+meteogram+timer+agenda+month"
			when: popup.twoColumns && popup.showAgenda && popup.showCalendar && popup.showMeteogram && popup.showTimer

			PropertyChanges { target: widgetGrid
				columns: 2
				rows: 2
			}
		},
		State {
			name: "singleColumnFullHeight"
			when: !popup.twoColumns && popup.showAgenda && popup.showCalendar

			PropertyChanges { target: widgetGrid
				columns: 1
				anchors.margins: 0
				anchors.topMargin: popup.padding
			}
			PropertyChanges { target: meteogramView
				Layout.maximumHeight: popup.topRowHeight
			}
			PropertyChanges { target: timerView
				Layout.maximumHeight: popup.topRowHeight
			}
			PropertyChanges { target: monthView
				Layout.minimumHeight: popup.singleColumnMonthViewHeight
				Layout.preferredHeight: popup.singleColumnMonthViewHeight
				Layout.maximumHeight: popup.singleColumnMonthViewHeight
			}
			PropertyChanges { target: agendaView
				Layout.preferredHeight: popup.bottomRowHeight
			}
		},
		State {
			name: "singleColumn"
			when: !popup.showAgenda || !popup.showCalendar

			PropertyChanges { target: widgetGrid
				columns: 1
			}
			PropertyChanges { target: meteogramView
				Layout.maximumHeight: popup.topRowHeight * 1.5 // 150%
			}
			PropertyChanges { target: timerView
				Layout.maximumHeight: popup.topRowHeight
			}
		}
	]

	//--- View tabs: Month | Week | Agenda (classic layout)
	property bool refreshing: false // Events are being fetched

	//--- Event details panel
	property var detailsEvent: null
	// Click on an event in any view: details in the widget, or the browser (Settings > Events).
	// Right-click menu for events in every view.
	EventContextMenu {
		id: eventContextMenu
		onShowDetails: function(eventItem) { popup.activateEvent(eventItem) }
		onEditEvent: function(eventItem) { popup.editEvent(eventItem) }
	}
	//--- Undo (delete, move)
	// Show "text" with an Undo button for a while; a newer offer replaces it.
	function offerUndo(text, undoFn) {
		undoBanner.undoFn = undoFn
		undoBanner.text = text
		undoBanner.visible = true
		undoTimer.restart()
	}
	// Delete an event (or, with wholeSeries, its repeating series), with an undo offer once
	// it's gone (Google calendars).
	function deleteWithUndo(eventItem, wholeSeries) {
		var calendarId = eventItem.calendarId
		var undoable = eventModel.canRestore(calendarId)
		var restored = function() { logic.update() }
		if (wholeSeries) {
			var seriesId = eventItem.recurringEventId
			eventModel.deleteSeries(calendarId, seriesId, function(err) {
				if (!err && undoable) {
					offerUndo(i18n("Repeating event deleted"), function() {
						eventModel.restoreEvent(calendarId, seriesId, null, restored)
					})
				}
			})
			return
		}
		var eventId = eventItem.id
		// A copy to create again if it can't be restored (not for occurrences of a series).
		var copy = null
		if (undoable && !eventItem.recurringEventId) {
			copy = Undo.restoreCopy(eventModel.getEvent(calendarId, eventId) || eventItem)
		}
		eventModel.deleteEvent(calendarId, eventId, function(err) {
			if (!err && undoable) {
				offerUndo(i18n("Event deleted"), function() {
					eventModel.restoreEvent(calendarId, eventId, copy, restored)
				})
			}
		})
	}

	function showEventMenu(eventItem, item, x, y) {
		eventContextMenu.openFor(eventItem, item, x, y)
	}

	function activateEvent(eventItem) {
		if (!eventItem) {
			return
		}
		if (plasmoid.configuration.eventClickAction === 'browser') {
			if (eventItem.htmlLink) {
				Shared.openExternalUrl(eventItem.htmlLink)
			}
			return
		}
		// Month and agenda delegates hand over ListModel copies (nested arrays become models);
		// show the original event object.
		var original = null
		if (eventItem.calendarId && eventItem.id && eventModel.eventsByCalendar[eventItem.calendarId]) {
			original = eventModel.getEvent(eventItem.calendarId, eventItem.id)
		}
		detailsEvent = original || eventItem
	}
	function closeEventDetails() {
		detailsEvent = null
		dayEventsOverlay.focusCard() // Esc closes the day list (or search) next
		searchOverlay.focusCard()
	}

	//--- Search, and quick add (the header's "+")
	property bool searchOpen: false
	function openSearch() {
		closeOverlays()
		searchOpen = true
	}
	function closeSearch() {
		searchOpen = false
	}
	property bool quickAddOpen: false
	function openQuickAdd() {
		quickAddOpen = true
	}
	function closeQuickAdd() {
		quickAddOpen = false
	}

	//--- Day events list (month view: click a day). Event details open on top of it.
	property var dayListDate: null
	function showDayEvents(date) {
		dayListDate = date
	}
	function closeDayEvents() {
		dayListDate = null
	}

	//--- New / edit event form, on top of everything.
	property bool editorOpen: false
	property var editorEvent: null // null: new event
	property date editorDate: new Date()
	property var editorStart: null
	property string editorTitle: ""
	function newEvent(date, startTime, title) {
		editorEvent = null
		editorDate = date || selectedDate || new Date()
		editorStart = startTime || null
		editorTitle = title || ""
		editorOpen = true
	}
	function editEvent(eventItem) {
		editorEvent = eventItem
		editorOpen = true
	}
	function closeEditor() {
		editorOpen = false
		editorEvent = null
		eventDetailsOverlay.focusCard()
	}

	function closeOverlays() {
		editorOpen = false
		editorEvent = null
		detailsEvent = null
		dayListDate = null
		searchOpen = false
		quickAddOpen = false
	}
	// Overlays belong to the view they were opened from.
	Connections {
		target: plasmoid.configuration
		function onPopupModeChanged() { popup.closeOverlays() }
	}
	// The open event may have been edited (or deleted) meanwhile: show the current version.
	Connections {
		target: popup.eventModel
		function onEventUpdated(calendarId, eventId, data) {
			if (popup.detailsEvent && popup.detailsEvent.id == eventId) {
				popup.detailsEvent = popup.eventModel.getEvent(calendarId, eventId) || data
			}
		}
		function onEventRemoved(calendarId, eventId, data) {
			if (popup.detailsEvent && popup.detailsEvent.id == eventId) {
				popup.closeEventDetails()
			}
		}
	}
	Connections {
		target: monthView
		function onDateClicked(clickedDate) {
			if (popup.monthMode && plasmoid.configuration.monthClickOpensDay) {
				popup.showDayEvents(clickedDate)
			}
		}
	}
	Connections {
		target: popup.eventModel
		function onFetchingData() { popup.refreshing = true }
		function onAllDataFetched() { popup.refreshing = false }
	}
	Timer {
		// Never leave the spinner stuck if a fetch doesn't report back.
		running: popup.refreshing
		interval: 30000
		onTriggered: popup.refreshing = false
	}

	PopupHeader {
		id: header
		anchors.top: parent.top
		anchors.left: parent.left
		anchors.right: parent.right
		monthViewItem: monthView
		weekViewItem: weekViewLoader.item
		showViewTabs: popup.showViewTabs
		showPinButton: popup.showPinButton
		refreshing: popup.refreshing
		onViewSelected: function(mode) {
			popup.closeOverlays()
			plasmoid.configuration.popupMode = mode
		}
		onNewEventClicked: popup.openQuickAdd()
		onSearchClicked: popup.openSearch()
		onRefreshClicked: logic.update()
	}

	// Problems fetching data, above every view. Offline: the last loaded events stay visible and
	// the fetch is retried with a growing delay (Logic.networkFailed).
	Kirigami.InlineMessage {
		id: errorBanner
		anchors.top: header.bottom
		anchors.left: parent.left
		anchors.right: parent.right
		anchors.topMargin: Kirigami.Units.smallSpacing
		anchors.leftMargin: Kirigami.Units.smallSpacing
		anchors.rightMargin: Kirigami.Units.smallSpacing

		property string errorText: logic.currentErrorMessage // Other errors (sign-in, API)
		readonly property bool network: logic.offline
		property int secondsLeft: 0
		function updateCountdown() {
			secondsLeft = logic.nextRetryAt > 0 ? Math.max(0, Math.ceil((logic.nextRetryAt - Date.now()) / 1000)) : 0
		}

		visible: network || errorText !== ""
		type: network ? Kirigami.MessageType.Warning : Kirigami.MessageType.Error
		text: {
			if (!network) {
				return errorText
			}
			var retry = secondsLeft <= 0 ? i18n("Retrying…")
				: secondsLeft < 60 ? i18np("Retrying in %1 second.", "Retrying in %1 seconds.", secondsLeft)
				: i18np("Retrying in %1 minute.", "Retrying in %1 minutes.", Math.ceil(secondsLeft / 60))
			return i18n("Can't connect. Showing the last loaded events.") + " " + retry
		}
		actions: [
			Kirigami.Action {
				visible: errorBanner.network
				icon.name: "view-refresh"
				text: i18n("Retry Now")
				onTriggered: logic.retryNow()
			},
			Kirigami.Action {
				visible: !errorBanner.network
				icon.name: "dialog-close"
				text: i18n("Dismiss")
				onTriggered: errorBanner.errorText = ""
			}
		]
		Timer {
			interval: 1000
			repeat: true
			running: errorBanner.visible && errorBanner.network
			triggeredOnStart: true
			onTriggered: errorBanner.updateCountdown()
		}
	}

	// Undo the last delete / move: at the bottom, over the views (like Google Calendar), so the
	// header, the error banner and the day names stay visible.
	Kirigami.InlineMessage {
		id: undoBanner
		z: 20
		anchors.bottom: parent.bottom
		anchors.left: parent.left
		anchors.right: parent.right
		anchors.bottomMargin: Kirigami.Units.smallSpacing
		anchors.leftMargin: Kirigami.Units.smallSpacing
		anchors.rightMargin: Kirigami.Units.smallSpacing

		property var undoFn: null
		visible: false
		type: Kirigami.MessageType.Information
		showCloseButton: true
		actions: [
			Kirigami.Action {
				icon.name: "edit-undo"
				text: i18n("Undo")
				onTriggered: {
					var fn = undoBanner.undoFn
					undoBanner.visible = false
					if (fn) {
						fn()
					}
				}
			}
		]
		HoverHandler {
			id: undoHover
		}
		Timer {
			id: undoTimer
			interval: 8000
			// Paused while the pointer is on it.
			running: undoBanner.visible && !undoHover.hovered
			onTriggered: undoBanner.visible = false
		}
		onVisibleChanged: {
			if (!visible) {
				undoFn = null
			}
		}
	}

	// Overlay cards: day list, search < event details < quick add, event form.
	OverlayCard {
		id: searchOverlay
		visible: popup.searchOpen
		z: 4
		anchors.top: header.bottom
		anchors.left: parent.left
		anchors.right: parent.right
		anchors.bottom: parent.bottom
		onOutsideClicked: popup.closeSearch()
		cardComponent: visible ? searchCard : null
		Component {
			id: searchCard
			SearchView {
				onCloseRequested: popup.closeSearch()
				onEventClicked: function(eventItem) { popup.activateEvent(eventItem) }
			}
		}
	}

	OverlayCard {
		id: dayEventsOverlay
		visible: !!popup.dayListDate
		z: 4
		anchors.top: header.bottom
		anchors.left: parent.left
		anchors.right: parent.right
		anchors.bottom: parent.bottom
		onOutsideClicked: popup.closeDayEvents()
		cardComponent: visible ? dayEventsCard : null
		Component {
			id: dayEventsCard
			DayEventsView {
				date: popup.dayListDate
				onCloseRequested: popup.closeDayEvents()
				onEventClicked: function(eventItem) { popup.activateEvent(eventItem) }
				onAddRequested: popup.newEvent(popup.dayListDate)
			}
		}
	}

	OverlayCard {
		id: eventDetailsOverlay
		visible: !!popup.detailsEvent
		z: 5
		anchors.top: header.bottom
		anchors.left: parent.left
		anchors.right: parent.right
		anchors.bottom: parent.bottom
		onOutsideClicked: popup.closeEventDetails()
		cardComponent: visible ? eventDetailsCard : null
		Component {
			id: eventDetailsCard
			EventDetailsView {
				eventItem: popup.detailsEvent
				onCloseRequested: popup.closeEventDetails()
				onEditRequested: popup.editEvent(popup.detailsEvent)
			}
		}
	}

	OverlayCard {
		id: quickAddOverlay
		visible: popup.quickAddOpen
		z: 6
		anchors.top: header.bottom
		anchors.left: parent.left
		anchors.right: parent.right
		anchors.bottom: parent.bottom
		onOutsideClicked: popup.closeQuickAdd()
		cardComponent: visible ? quickAddCard : null
		Component {
			id: quickAddCard
			QuickAddView {
				date: popup.selectedDate
				onCloseRequested: popup.closeQuickAdd()
				onMoreOptionsRequested: function(title) {
					popup.closeQuickAdd()
					popup.newEvent(popup.selectedDate, null, title)
				}
			}
		}
	}

	OverlayCard {
		id: eventEditorOverlay
		visible: popup.editorOpen
		z: 6
		anchors.top: header.bottom
		anchors.left: parent.left
		anchors.right: parent.right
		anchors.bottom: parent.bottom
		onOutsideClicked: {} // Don't lose typed input on a stray click.
		cardComponent: visible ? eventEditorCard : null
		Component {
			id: eventEditorCard
			EventEditView {
				eventItem: popup.editorEvent
				initialDate: popup.editorDate
				initialStart: popup.editorStart
				initialTitle: popup.editorTitle
				onCloseRequested: popup.closeEditor()
			}
		}
	}

	Loader {
		id: weekViewLoader
		active: popup.hourGridMode
		visible: active
		anchors.fill: widgetGrid
		sourceComponent: WeekView {
			eventModel: popup.eventModel
			dayCount: popup.dayMode ? 1 : 7
			weatherByDay: popup.weatherInViews ? popup.weatherByDay : ({})
			weatherHourly: logic.hourlyWeatherData && logic.hourlyWeatherData.list ? logic.hourlyWeatherData.list : []
			weatherCurrent: logic.currentWeatherData
			weatherIsSetup: WeatherApi.weatherIsSetup(plasmoid.configuration)
			weatherLoading: logic.weatherLoading
			showHeader: false
			// Make sure the visible week's month is fetched.
			onWeekStartChanged: {
				var middle = new Date(weekStart.getFullYear(), weekStart.getMonth(), weekStart.getDate() + 3)
				popup.monthViewDate = middle
			}
		}
	}

	GridLayout {
		id: widgetGrid
		visible: !popup.hourGridMode
		anchors.fill: parent
		anchors.margins: popup.padding
		anchors.topMargin: popup.viewTabsHeight
		columnSpacing: popup.spacing
		rowSpacing: popup.spacing
		onColumnsChanged: {
		}
		onRowsChanged: {
		}

		// Created only when shown.
		Loader {
			id: meteogramView
			visible: showMeteogram
			active: showMeteogram
			Layout.fillWidth: true
			Layout.maximumWidth: popup.agendaMaxWidth
			Layout.alignment: Qt.AlignHCenter
			Layout.minimumHeight: popup.topRowHeight
			Layout.preferredWidth: popup.leftColumnWidth
			Layout.preferredHeight: popup.topRowHeight
			onLoaded: popup.updateMeteogram()

			sourceComponent: MeteogramView {
				visibleDuration: plasmoid.configuration.meteogramHours
				xAxisScale: 1 / hoursPerDataPoint
				xAxisLabelEvery: Math.ceil(3 / hoursPerDataPoint)
				property int hoursPerDataPoint: WeatherApi.getDataPointDuration(plasmoid.configuration)
				rainUnits: WeatherApi.getRainUnits(plasmoid.configuration)

					Rectangle {
						id: meteogramMessageBox
						anchors.fill: parent
						anchors.margins: Kirigami.Units.smallSpacing
						color: "transparent"
						border.color: Kirigami.Theme.buttonBackgroundColor ? Kirigami.Theme.buttonBackgroundColor : Kirigami.Theme.backgroundColor
						border.width: 1

					readonly property string message: {
						if (!WeatherApi.weatherIsSetup(plasmoid.configuration)) {
							return i18n("Weather not configured.\nGo to Weather in the config and set your city,\nand/or disable the meteogram to hide this area.")
						} else if (logic.lastForecastErr) {
							return i18n("Error fetching weather.") + '\n' + logic.lastForecastErr
						} else {
							return ''
						}
					}

					visible: !!message

					PlasmaComponents3.Label {
						text: meteogramMessageBox.message
						anchors.fill: parent
						fontSizeMode: Text.Fit
						wrapMode: Text.Wrap
						horizontalAlignment: Text.AlignHCenter
						verticalAlignment: Text.AlignVCenter
					}
				}
			}
		}

		Loader {
			id: timerView
			visible: showTimer
			active: showTimer
			Layout.fillWidth: true
			Layout.maximumWidth: popup.agendaMaxWidth
			Layout.alignment: Qt.AlignHCenter
			Layout.minimumHeight: Math.max(popup.topRowHeight, implicitHeight)
			Layout.preferredWidth: popup.rightColumnWidth
			Layout.preferredHeight: popup.topRowHeight

			sourceComponent: TimerView {}
		}

		MonthView {
			id: monthView
			visible: showCalendar
			showHeader: false
			borderOpacity: appletConfig.faintGridLineOpacity
			showWeekNumbers: plasmoid.configuration.monthShowWeekNumbers
			highlightCurrentDayWeek: true

			Layout.preferredWidth: popup.leftColumnWidth
			Layout.preferredHeight: popup.bottomRowHeight
			Layout.fillWidth: true
			Layout.fillHeight: true
			// Next to the agenda, keep the calendar at its configured size; extra room goes to the agenda.
			Layout.maximumWidth: popup.twoColumns ? popup.leftColumnWidth : Number.POSITIVE_INFINITY
			Layout.maximumHeight: popup.twoColumns ? popup.bottomRowHeight : Number.POSITIVE_INFINITY
			Layout.alignment: Qt.AlignCenter

			onDaysRebuilt: parseGCalEvents(popup.eventModel.eventsData)

			function parseGCalEvents(data) {
				if (!(data && data.items)) {
					return
				}

				// https://github.com/KDE/plasma-framework/blob/master/src/declarativeimports/calendar/daysmodel.h
				// Bucket events per visible day in plain JS first, then write each day to the model once.
				var daysModel = monthView.daysModel
				var dayTimes = []
				for (var i = 0; i < daysModel.count; i++) {
					var dayData = daysModel.get(i)
					dayTimes.push(new Date(dayData.yearNumber, dayData.monthNumber - 1, dayData.dayNumber).getTime())
				}
				var dayEvents = EventBuckets.bucketByDay(data.items, dayTimes)
				for (var j = 0; j < dayEvents.length; j++) {
					var events = daysModel.get(j).events
					events.clear()
					if (dayEvents[j].length) {
						events.append(dayEvents[j])
					}
					daysModel.setProperty(j, 'showEventBadge', dayEvents[j].length > 0)
				}
			}

			onDayDoubleClicked: function(dayData) {
				var date = new Date(dayData.yearNumber, dayData.monthNumber-1, dayData.dayNumber)
				var doubleClickOption = plasmoid.configuration.monthDayDoubleClick

				switch (doubleClickOption) {
					case 'GoogleCalWeb':
						Shared.openGoogleCalendarNewEventUrl(date)
						return
					default:
						return
				}
			}
		} // MonthView

		AgendaView {
			id: agendaView
			visible: showAgenda

			Layout.preferredWidth: popup.rightColumnWidth
			Layout.preferredHeight: popup.bottomRowHeight
			Layout.fillWidth: true
			Layout.fillHeight: true
			Layout.maximumWidth: popup.agendaMaxWidth
			Layout.alignment: Qt.AlignHCenter

			onNewEventFormOpened: function(agendaItem, calendarSelector) {
				var selectedCalendarId = ""
				if (plasmoid.configuration.agendaNewEventRememberCalendar) {
					selectedCalendarId = plasmoid.configuration.agendaNewEventLastCalendarId
				}
				var calendarList = eventModel.getCalendarList()
				calendarSelector.populate(calendarList, selectedCalendarId)
			}
			onSubmitNewEventForm: function(calendarId, date, text) {
				logger.debug('onSubmitNewEventForm', calendarId)
				eventModel.createEvent(calendarId, date, text)
			}

		} // AgendaView
	} // GridLayout

	function updateMeteogram() {
		if (meteogramView.item) {
			meteogramView.item.parseWeatherForecast(logic.currentWeatherData, logic.hourlyWeatherData)
		}
	}

	function showError(msg) {
		errorBanner.errorText = msg
	}
	function showNetworkError() {
		errorBanner.updateCountdown()
	}
	function clearError() {
		errorBanner.errorText = ""
	}

	Timer {
		id: updateUITimer
		interval: 100
		onTriggered: popup.updateUI()
	}
	function deferredUpdateUI() {
		updateUITimer.restart()
	}

	//--- Weather for the views
	readonly property bool weatherInViews: plasmoid.configuration.weatherShowInViews
	property var weatherByDay: ({}) // Shared.dayKey -> daily forecast item
	function updateWeatherByDay() {
		var map = {}
		var list = logic.dailyWeatherData && logic.dailyWeatherData.list ? logic.dailyWeatherData.list : []
		for (var i = 0; i < list.length; i++) {
			map[Shared.dayKey(new Date(list[i].dt * 1000))] = list[i]
		}
		weatherByDay = map
	}

	function updateUI() {
		var now = new Date()

		if (updateUITimer.running) {
			updateUITimer.running = false
		}

		agendaModel.parseGCalEvents(eventModel.eventsData)
		agendaModel.parseWeatherForecast(logic.dailyWeatherData)
		updateWeatherByDay()
		monthView.parseGCalEvents(eventModel.eventsData)
		if (weekViewLoader.item) {
			weekViewLoader.item.rebuild()
		}
		scrollToSelection()
	}
}
