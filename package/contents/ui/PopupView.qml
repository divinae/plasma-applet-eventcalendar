import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "lib"
import "Shared.js" as Shared
import "Tasks.js" as Tasks
import "Undo.js" as Undo
import "KeyNav.js" as KeyNav
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

	// DigitalClock LeftColumn minWidth: Kirigami.Units.gridUnit * 22
	// DigitalClock RightColumn minWidth: Kirigami.Units.gridUnit * 14
	// 14/(22+14) * 400 = 156
	// rightColumnWidth=156 looks nice but is very thin for listing events + date + weather.
	property int leftColumnWidth: Math.round(plasmoid.configuration.monthModeWidth * widthScale) // Meteogram + MonthView
	property int rightColumnWidth: Math.round(plasmoid.configuration.rightColumnWidth * widthScale) // TimerView + AgendaView

	// Every view has the configured width. Height: the view, plus (agenda view) the meteogram and
	// timer rows above it.
	property int contentHeight: {
		var rows = [bottomRowHeight]
		if (showMeteogram) {
			rows.push(topRowHeight)
		}
		if (showTimer) {
			rows.push(topRowHeight)
		}
		var h = viewTabsHeight
		for (var i = 0; i < rows.length; i++) {
			h += rows[i]
		}
		return h + spacing * (rows.length - 1)
	}

	Layout.minimumWidth: Kirigami.Units.gridUnit * 14
	Layout.preferredWidth: leftColumnWidth + padding * 2
	Layout.minimumHeight: Kirigami.Units.gridUnit * 14
	Layout.preferredHeight: contentHeight + padding * 2

	property var eventModel
	property var agendaModel

	// Month mode: only a full month view with event titles, like mobile calendar apps.
	// Week mode: only the week view. Both use the month/week popup size.
	// Tasks mode: the task lists (Tasks tab), when some are selected in settings; else the month.
	property bool taskListsSelected: false
	function refreshTaskLists() {
		taskListsSelected = !!eventModel && eventModel.getSelectedTaskLists().length > 0
	}
	readonly property string viewMode: plasmoid.configuration.popupMode === 'tasks' && !taskListsSelected
		? 'month' : plasmoid.configuration.popupMode
	readonly property bool monthMode: viewMode === 'month'
	readonly property bool weekMode: viewMode === 'week'
	readonly property bool dayMode: viewMode === 'today'
	readonly property bool tasksMode: viewMode === 'tasks'
	readonly property bool hourGridMode: weekMode || dayMode // Both use WeekView
	readonly property bool fullViewMode: monthMode || hourGridMode || tasksMode
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
		agendaView.scrollToDate(selectedDate)
	}

	Component.onCompleted: {
		refreshTaskLists()
		deferredUpdateUI()
	}

	onMonthViewDateChanged: {
		logger.debug('onMonthViewDateChanged', monthViewDate)
		var startOfMonth = new Date(monthViewDate)
		startOfMonth.setDate(1)
		var prevMonth = agendaModel.currentMonth
		var monthChanged = !prevMonth
			|| prevMonth.getFullYear() !== startOfMonth.getFullYear()
			|| prevMonth.getMonth() !== startOfMonth.getMonth()
		agendaModel.currentMonth = new Date(startOfMonth)
		// Opening the popup or picking a day / "today" in the same month keeps the month:
		// nothing to fetch or rebuild. (A newly created popup fills itself in Component.onCompleted.)
		if (monthChanged) {
			logic.updateEvents()
		}
	}

	property bool refreshing: false // Events are being fetched (the header's refresh button spins)

	//--- Event details panel
	property var detailsEvent: null
	// Click on an event in any view: details in the widget, or the browser (Settings > Events).
	// Right-click menu for events in every view.
	EventContextMenu {
		id: eventContextMenu
		onShowDetails: function(eventItem) { popup.activateEvent(eventItem) }
		onEditEvent: function(eventItem) { popup.editEvent(eventItem) }
		onDuplicateEvent: function(eventItem) { popup.duplicateEvent(eventItem) }
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
		var deletedText = Tasks.isTask(eventItem) ? i18n("Task deleted") : i18n("Event deleted")
		eventModel.deleteEvent(calendarId, eventId, function(err) {
			if (!err && undoable) {
				offerUndo(deletedText, function() {
					eventModel.restoreEvent(calendarId, eventId, copy, restored)
				})
			}
		})
	}

	// Month and agenda delegates hand over ListModel copies (nested arrays become models): the
	// original event object when it's loaded.
	function originalEvent(eventItem) {
		var original = null
		if (eventItem && eventItem.calendarId && eventItem.id && eventModel.eventsByCalendar[eventItem.calendarId]) {
			original = eventModel.getEvent(eventItem.calendarId, eventItem.id)
		}
		return original || eventItem
	}

	function showEventMenu(eventItem, item, x, y) {
		eventContextMenu.openFor(originalEvent(eventItem), item, x, y)
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
		detailsEvent = originalEvent(eventItem)
	}
	function closeEventDetails() {
		detailsEvent = null
		searchOverlay.focusCard() // Esc closes the search next
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

	//--- Import a .ics file (the widget menu's "Import Events…"). The file dialog lives in main.qml,
	// outside the popup, which may close while the dialog is open.
	signal importFileRequested()
	property bool importOpen: false
	property string importFileUrl: ""
	function openImport(fileUrl) {
		importFileUrl = String(fileUrl || "")
		importOpen = true
	}
	function closeImport() {
		importOpen = false
		importFileUrl = ""
	}

	//--- Month view: clicking a day opens it in the Today view.
	property var pendingDayViewDate: null // Picked up when the day view is created
	function showDayView(date) {
		var day = Shared.startOfDay(date)
		if (dayMode && weekViewLoader.item) {
			weekViewLoader.item.weekStart = day
			return
		}
		pendingDayViewDate = day
		plasmoid.configuration.popupMode = 'today'
	}

	//--- New / edit event form, on top of everything.
	property bool editorOpen: false
	property var editorEvent: null // null: new event
	property date editorDate: new Date()
	property var editorStart: null
	property string editorTitle: ""
	property var editorTemplate: null // Duplicate: the new event starts as a copy of this one
	property bool editorTask: false // New task (due on editorDate) instead of an event
	property string editorCalendarId: "" // New event / task: on this calendar / task list
	property bool editorTaskNoDue: false // New task without a due date
	function newEvent(date, startTime, title, calendarId) {
		editorEvent = null
		editorTemplate = null
		editorTask = false
		editorCalendarId = calendarId || ""
		editorTaskNoDue = false
		editorDate = date || selectedDate || new Date()
		editorStart = startTime || null
		editorTitle = title || ""
		editorOpen = true
	}
	// A new task due on date (the editor in task mode), on calendarId when that's a task list.
	// No date (null): without a due date.
	function newTask(date, title, calendarId) {
		newEvent(date, null, title, calendarId)
		editorTask = true
		editorTaskNoDue = !date
	}
	// Any task list to add tasks to.
	function hasTaskLists() {
		return eventModel.getCalendarList().some(function(c) { return c.isTasklist })
	}
	function editEvent(eventItem) {
		editorEvent = originalEvent(eventItem)
		editorTemplate = null
		editorTask = false
		editorCalendarId = ""
		editorOpen = true
	}
	function duplicateEvent(eventItem) {
		editorEvent = null
		editorTask = false
		editorCalendarId = ""
		editorTemplate = eventItem
		editorDate = eventItem.startDateTime || new Date()
		editorStart = null
		editorTitle = ""
		editorOpen = true
	}
	function closeEditor() {
		editorOpen = false
		editorEvent = null
		editorTemplate = null
		eventDetailsOverlay.focusCard()
	}

	function closeOverlays() {
		editorOpen = false
		editorEvent = null
		editorTemplate = null
		detailsEvent = null
		searchOpen = false
		quickAddOpen = false
		closeImport()
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
			monthView.keyboardActive = false // The focus ring follows the keys only
			if (popup.monthMode && plasmoid.configuration.monthClickOpensDay) {
				popup.showDayView(clickedDate)
			}
		}
	}
	Connections {
		target: popup.eventModel
		function onFetchingData() { popup.refreshing = true }
		function onAllDataFetched() {
			popup.refreshing = false
			popup.refreshTaskLists()
		}
		function onCalendarFetched(calendarId, data) { popup.refreshTaskLists() }
		function onDataCleared() { popup.refreshTaskLists() }
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
		currentMode: popup.viewMode
		showTasksTab: popup.taskListsSelected
		tasksMode: popup.tasksMode
		showViewTabs: popup.showViewTabs
		showPinButton: popup.showPinButton
		refreshing: popup.refreshing
		onViewSelected: function(mode) {
			popup.closeOverlays()
			plasmoid.configuration.popupMode = mode
		}
		onNewEventClicked: popup.tasksMode ? popup.newTask(null) : popup.openQuickAdd()
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

	// Overlay cards: search < event details < quick add, import, event form.
	// Later cards stack above earlier ones; the undo banner stays above them all.
	Item {
		id: overlays
		z: 4
		anchors.top: header.bottom
		anchors.left: parent.left
		anchors.right: parent.right
		anchors.bottom: parent.bottom

		OverlayCard {
			id: searchOverlay
			visible: popup.searchOpen
			anchors.fill: parent
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
			id: eventDetailsOverlay
			visible: !!popup.detailsEvent
			anchors.fill: parent
			framed: false // The card draws its own frame
			onOutsideClicked: popup.closeEventDetails()
			cardComponent: visible ? eventDetailsCard : null
			Component {
				id: eventDetailsCard
				EventDetailsView {
					eventItem: popup.detailsEvent
					onCloseRequested: popup.closeEventDetails()
					onEditRequested: popup.editEvent(popup.detailsEvent)
					onDuplicateRequested: popup.duplicateEvent(popup.detailsEvent)
				}
			}
		}

		OverlayCard {
			id: quickAddOverlay
			visible: popup.quickAddOpen
			anchors.fill: parent
			onOutsideClicked: popup.closeQuickAdd()
			cardComponent: visible ? quickAddCard : null
			Component {
				id: quickAddCard
				QuickAddView {
					date: popup.selectedDate
					onCloseRequested: popup.closeQuickAdd()
					onMoreOptionsRequested: function(title, calendarId, isTasklist) {
						popup.closeQuickAdd()
						if (isTasklist) {
							popup.newTask(popup.selectedDate, title, calendarId)
						} else {
							popup.newEvent(popup.selectedDate, null, title, calendarId)
						}
					}
					onNewTaskRequested: function(title) {
						popup.closeQuickAdd()
						popup.newTask(popup.selectedDate, title)
					}
				}
			}
		}

		OverlayCard {
			id: importOverlay
			visible: popup.importOpen
			anchors.fill: parent
			onOutsideClicked: {} // Don't lose the checked events on a stray click.
			cardComponent: visible ? importCard : null
			Component {
				id: importCard
				ImportView {
					fileUrl: popup.importFileUrl
					onCloseRequested: popup.closeImport()
					onChooseFileRequested: popup.importFileRequested()
				}
			}
		}

		OverlayCard {
			id: eventEditorOverlay
			visible: popup.editorOpen
			anchors.fill: parent
			framed: false // The card draws its own frame
			onOutsideClicked: {} // Don't lose typed input on a stray click.
			cardComponent: visible ? eventEditorCard : null
			Component {
				id: eventEditorCard
				EventEditView {
					eventItem: popup.editorEvent
					initialDate: popup.editorDate
					initialStart: popup.editorStart
					initialTitle: popup.editorTitle
					templateEvent: popup.editorTemplate
					newTask: popup.editorTask
					initialNoDue: popup.editorTask && popup.editorTaskNoDue
					initialCalendarId: popup.editorCalendarId
					onCloseRequested: popup.closeEditor()
				}
			}
		}
	}

	Loader {
		id: weekViewLoader
		active: popup.hourGridMode
		visible: active
		anchors.fill: widgetGrid
		onLoaded: {
			if (popup.pendingDayViewDate) {
				item.weekStart = popup.pendingDayViewDate
				popup.pendingDayViewDate = null
			}
		}
		sourceComponent: WeekView {
			eventModel: popup.eventModel
			dayCount: popup.dayMode ? 1 : 7
			workWeek: plasmoid.configuration.weekViewWorkWeek // Week view only
			weatherByDay: popup.weatherInViews ? root.weatherByDay : ({})
			weatherHourly: logic.hourlyWeatherData && logic.hourlyWeatherData.list ? logic.hourlyWeatherData.list : []
			weatherCurrent: logic.currentWeatherData
			weatherIsSetup: WeatherApi.weatherIsSetup(plasmoid.configuration)
			weatherLoading: logic.weatherLoading
			weatherError: logic.lastForecastErr ? String(logic.lastForecastErr) : ""
			onWeatherRetryRequested: logic.updateWeather(true)
			// Make sure the visible week's (or day's) month is fetched.
			onWeekStartChanged: {
				var middle = new Date(weekStart.getFullYear(), weekStart.getMonth(), weekStart.getDate() + Math.floor(dayCount / 2))
				popup.monthViewDate = middle
			}
		}
	}

	// The task lists: a list like the agenda, capped in width and centered.
	Loader {
		id: tasksViewLoader
		active: popup.tasksMode
		visible: active
		anchors.top: widgetGrid.top
		anchors.bottom: widgetGrid.bottom
		anchors.horizontalCenter: widgetGrid.horizontalCenter
		width: Math.min(widgetGrid.width, popup.agendaMaxWidth)
		sourceComponent: TasksView {
			eventModel: popup.eventModel
		}
	}

	GridLayout {
		id: widgetGrid
		visible: !popup.hourGridMode && !popup.tasksMode
		anchors.fill: parent
		anchors.margins: popup.padding
		anchors.topMargin: popup.viewTabsHeight
		columns: 1
		columnSpacing: popup.spacing
		rowSpacing: popup.spacing

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
			Layout.maximumHeight: popup.topRowHeight * 1.5
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
			Layout.maximumHeight: popup.topRowHeight

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
			Layout.alignment: Qt.AlignCenter

			eventTitles: popup.monthMode
			// Multi-day events as bars across the days (with event titles, ie: the month popup mode).
			spanBarsEnabled: true
			// Events can be dragged to other days (with event titles).
			eventDragEnabled: true
			eventDragModel: popup.eventModel

			onDaysRebuilt: parseGCalEvents(popup.eventModel.eventsData)
			// The bar lanes depend on how many event rows fit in a day cell. Refilled right away
			// (in the same frame as the layout change): a deferred refill showed the cells first
			// filled the other way, then reordered.
			onEventRowCapacityChanged: if (spanBarsActive) reparseGCalEvents()
			onSpanBarsActiveChanged: reparseGCalEvents()
			function reparseGCalEvents() {
				parseGCalEvents(popup.eventModel.eventsData)
			}

			function parseGCalEvents(data) {
				if (!(data && data.items)) {
					return
				}
				monthView.setEvents(data.items) // Leaves the tasks out (they're in the Agenda and the Tasks tab)
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

	function updateUI() {
		updateUITimer.stop()

		agendaModel.parseGCalEvents(eventModel.eventsData)
		agendaModel.parseWeatherForecast(root.weatherByDay)
		monthView.parseGCalEvents(eventModel.eventsData)
		if (weekViewLoader.item) {
			weekViewLoader.item.rebuild()
		}
		scrollToSelection()
	}

	//--- Keyboard (KeyNav.js): arrows, Enter, N, / or Ctrl+F, T, 1-5. Cards and text fields keep
	// their keys; Esc is left to the cards and to Plasma (closes the popup).
	readonly property bool anyOverlayOpen: editorOpen || !!detailsEvent || searchOpen || quickAddOpen || importOpen
	readonly property string currentViewMode: monthMode ? 'month' : weekMode ? 'week' : dayMode ? 'today' : tasksMode ? 'tasks' : 'classic'
	// Take the keys when the popup opens and when the last card closes (its focus is gone).
	function focusForKeys() {
		if (!anyOverlayOpen) {
			forceActiveFocus()
		}
	}
	onAnyOverlayOpenChanged: if (!anyOverlayOpen) Qt.callLater(focusForKeys)

	Keys.onPressed: function(event) {
		if (anyOverlayOpen || KeyNav.isTextInput(Window.activeFocusItem)) {
			return
		}
		var action = KeyNav.actionFor(event.key, event.modifiers, currentViewMode)
		if (action && runKeyAction(action)) {
			event.accepted = true
		}
	}

	// The day shown by the Day view, otherwise the selected day.
	function keyDate() {
		if (dayMode && weekViewLoader.item) {
			return weekViewLoader.item.weekStart
		}
		return selectedDate
	}

	function runKeyAction(action) {
		var nav = weekViewLoader.item
		switch (action.type) {
			case 'previous':
				if (nav) nav.goPrevious(); else monthView.goPrevious()
				return true
			case 'next':
				if (nav) nav.goNext(); else monthView.goNext()
				return true
			case 'today':
				if (nav) nav.goToday(); else monthView.resetToToday()
				return true
			case 'move':
				var date = Shared.startOfDay(Shared.addDays(selectedDate, action.days))
				if (date.getFullYear() !== monthViewDate.getFullYear() || date.getMonth() !== monthViewDate.getMonth()) {
					monthViewDate = date
				}
				monthView.keyboardActive = true
				monthView.setSelectedDate(date)
				return true
			case 'open':
				showDayView(selectedDate)
				return true
			case 'new':
				if (tasksMode) {
					newTask(null)
					return true
				}
				var day = keyDate()
				if (!Shared.isSameDate(day, selectedDate)) {
					selectedDate = day
				}
				openQuickAdd()
				return true
			case 'search':
				openSearch()
				return true
			case 'view':
				if (action.mode === 'tasks' && !taskListsSelected) {
					return false
				}
				if (action.mode !== plasmoid.configuration.popupMode) {
					closeOverlays()
					plasmoid.configuration.popupMode = action.mode
				}
				return true
		}
		return false
	}
}
