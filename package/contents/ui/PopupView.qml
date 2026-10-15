import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras

import "lib"
import "Shared.js" as Shared
import "./weather/WeatherApi.js" as WeatherApi

MouseArea {
	id: popup

	onClicked: focus = true

	property int padding: 0
	property bool showPinButton: false // Assigned in main.qml
	property int spacing: 10

	property real screenWidth: Screen.width > 0 ? Screen.width : plasmoid.screenGeometry.width
	property real screenHeight: Screen.height > 0 ? Screen.height : plasmoid.screenGeometry.height
	property real widthScale: Math.max(1, screenWidth / 1920)
	property real heightScale: Math.max(1, screenHeight / 1080)

	property int topRowHeight: Math.round(plasmoid.configuration.topRowHeight * heightScale)
	property int bottomRowHeight: Math.round((fullViewMode ? plasmoid.configuration.monthModeHeight : plasmoid.configuration.bottomRowHeight) * heightScale)
	property int singleColumnMonthViewHeight: Math.round(plasmoid.configuration.monthHeightSingleColumn * heightScale)

	// DigitalClock LeftColumn minWidth: Kirigami.Units.gridUnit * 22
	// DigitalClock RightColumn minWidth: Kirigami.Units.gridUnit * 14
	// 14/(22+14) * 400 = 156
	// rightColumnWidth=156 looks nice but is very thin for listing events + date + weather.
	property int leftColumnWidth: Math.round((fullViewMode ? plasmoid.configuration.monthModeWidth : plasmoid.configuration.leftColumnWidth) * widthScale) // Meteogram + MonthView
	property int rightColumnWidth: Math.round(plasmoid.configuration.rightColumnWidth * widthScale) // TimerView + AgendaView

	property int singleColumnWidth: {
		if (weekMode) {
			return leftColumnWidth
		}
		if (showAgenda && showCalendar) {
			return Math.max(leftColumnWidth, rightColumnWidth)
		} else if (showCalendar) {
			return leftColumnWidth
		} else if (showAgenda) {
			return rightColumnWidth
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
		if (weekMode) {
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
	readonly property bool fullViewMode: monthMode || weekMode
	property bool showMeteogram: plasmoid.configuration.widgetShowMeteogram && !fullViewMode
	property bool showTimer: plasmoid.configuration.widgetShowTimer && !fullViewMode
	property bool showAgenda: plasmoid.configuration.widgetShowAgenda && !fullViewMode
	property bool showCalendar: (plasmoid.configuration.widgetShowCalendar && !weekMode) || monthMode
	readonly property bool showViewTabs: plasmoid.configuration.showViewTabs
	// Month and week views put the top bar inside their header row, the agenda layout above.
	readonly property int viewTabsHeight: header.implicitHeight + spacing
	property bool agendaScrollOnSelect: true
	property bool agendaScrollOnMonthChange: false

	property alias today: monthView.today
	property alias selectedDate: monthView.currentDate
	property alias monthViewDate: monthView.displayedDate

	Connections {
		target: monthView
		function onDateSelected(date) {
			// logger.debug('onDateSelected', selectedDate)
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
		// logger.debug(popup.state, widgetGrid.columns, widgetGrid.rows)
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
				// Layout.minimumHeight: popup.bottomRowHeight
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
	function activateEvent(eventItem) {
		if (!eventItem) {
			return
		}
		if (plasmoid.configuration.eventClickAction === 'browser') {
			if (eventItem.htmlLink) {
				Qt.openUrlExternally(eventItem.htmlLink)
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
		dayEventsOverlay.focusCard() // Esc closes the day list next
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
	function newEvent(date) {
		editorEvent = null
		editorDate = date || selectedDate || new Date()
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

	// Native Plasma header for all views: navigation, title (month or week), view switcher,
	// refresh and pin. The month and week views hide their own header rows.
	PlasmaExtras.PlasmoidHeading {
		id: header
		anchors.top: parent.top
		anchors.left: parent.left
		anchors.right: parent.right

		readonly property var weekView: weekViewLoader.item

		// Left: view switcher. Center: navigation and title. Right: refresh, new event, pin.
		contentItem: Item {
		id: topBar
		implicitHeight: Math.max(leftGroup.implicitHeight, centerGroup.implicitHeight, rightGroup.implicitHeight)
		readonly property real sideWidth: Math.max(leftGroup.implicitWidth, rightGroup.implicitWidth)

		RowLayout {
			id: leftGroup
			anchors.left: parent.left
			anchors.verticalCenter: parent.verticalCenter
			spacing: 0
			// View switcher: flat buttons with icon and text, the current view on a soft rounded tint.
			RowLayout {
				visible: popup.showViewTabs
				Layout.alignment: Qt.AlignVCenter
				spacing: 2

				Repeater {
					model: [
						{ mode: 'month', icon: "view-calendar-month", text: i18n("Month") },
						{ mode: 'week', icon: "view-calendar-week", text: i18n("Week") },
						{ mode: 'classic', icon: "view-calendar-agenda", text: i18n("Agenda") },
					]
					Item {
						readonly property bool current: plasmoid.configuration.popupMode === modelData.mode
						implicitWidth: viewButton.implicitWidth
						implicitHeight: viewButton.implicitHeight

						Rectangle {
							anchors.fill: parent
							// Same corners as the Plasma button hover background drawn on top.
							radius: Kirigami.Units.cornerRadius
							color: Kirigami.Theme.highlightColor
							opacity: parent.current ? 0.18 : 0
						}

						PlasmaComponents3.ToolButton {
							id: viewButton
							anchors.fill: parent
							icon.name: modelData.icon
							text: modelData.text
							display: QQC2.AbstractButton.TextBesideIcon
							// Not checkable: the style's checked look changes the size and elides the text.
							onClicked: {
								popup.closeOverlays()
								plasmoid.configuration.popupMode = modelData.mode
							}
							Accessible.name: modelData.text
						}
					}
				}
			}
		}

		RowLayout {
			id: centerGroup
			anchors.centerIn: parent
			// Stay clear of the side groups; the title elides if needed.
			width: Math.min(implicitWidth, parent.width - topBar.sideWidth * 2 - Kirigami.Units.largeSpacing * 2)
			spacing: 0
			PlasmaComponents3.ToolButton {
				icon.name: "go-previous"
				onClicked: header.weekView ? header.weekView.goPrevious() : monthView.goPrevious()
				PlasmaComponents3.ToolTip.text: header.weekView ? i18n("Previous Week") : i18n("Previous Month")
				PlasmaComponents3.ToolTip.visible: hovered
			}
			PlasmaComponents3.ToolButton {
				icon.name: "go-jump-today"
				onClicked: header.weekView ? header.weekView.goToday() : monthView.resetToToday()
				PlasmaComponents3.ToolTip.text: i18n("Today")
				PlasmaComponents3.ToolTip.visible: hovered
			}
			PlasmaComponents3.ToolButton {
				icon.name: "go-next"
				onClicked: header.weekView ? header.weekView.goNext() : monthView.goNext()
				PlasmaComponents3.ToolTip.text: header.weekView ? i18n("Next Week") : i18n("Next Month")
				PlasmaComponents3.ToolTip.visible: hovered
			}
			Kirigami.Heading {
				Layout.fillWidth: true
				Layout.maximumWidth: implicitWidth
				Layout.leftMargin: Kirigami.Units.smallSpacing
				level: 2
				elide: Text.ElideRight
				wrapMode: Text.NoWrap
				font.capitalization: Font.Capitalize
				text: header.weekView ? header.weekView.title : monthView.currentTitle
				MouseArea {
					anchors.fill: parent
					enabled: !header.weekView
					onClicked: monthView.titleClicked() // Year / decade view
				}
			}
		}

		RowLayout {
			id: rightGroup
			anchors.right: parent.right
			anchors.verticalCenter: parent.verticalCenter
			spacing: 0
			PlasmaComponents3.ToolButton {
				icon.name: "list-add"
				onClicked: popup.newEvent(popup.selectedDate)
				PlasmaComponents3.ToolTip.text: i18n("New Event")
				PlasmaComponents3.ToolTip.visible: hovered
			}
			Item {
				Layout.preferredWidth: refreshButton.implicitWidth
				Layout.preferredHeight: refreshButton.implicitHeight
				Layout.alignment: Qt.AlignVCenter

				PlasmaComponents3.ToolButton {
					id: refreshButton
					anchors.fill: parent
					icon.name: "view-refresh"
					enabled: !popup.refreshing
					opacity: popup.refreshing ? 0 : 1
					onClicked: logic.update()
					PlasmaComponents3.ToolTip.text: i18n("Refresh")
					PlasmaComponents3.ToolTip.visible: hovered
				}
				PlasmaComponents3.BusyIndicator {
					anchors.centerIn: parent
					width: refreshButton.icon.width || Kirigami.Units.iconSizes.small
					height: width
					running: popup.refreshing
					visible: running
				}
			}
			Kirigami.Separator {
				visible: popup.showPinButton
				Layout.fillHeight: true
				Layout.topMargin: Kirigami.Units.smallSpacing
				Layout.bottomMargin: Kirigami.Units.smallSpacing
				Layout.leftMargin: Kirigami.Units.smallSpacing
				Layout.rightMargin: Kirigami.Units.smallSpacing
			}
			// Keeps the popup open for reference.
			PlasmaComponents3.ToolButton {
				visible: popup.showPinButton
				checkable: true
				icon.name: "window-pin"
				checked: plasmoid.configuration.pin
				onToggled: plasmoid.configuration.pin = checked
				PlasmaComponents3.ToolTip.text: i18n("Keep Open")
				PlasmaComponents3.ToolTip.visible: hovered
			}
		}
		}
	}


	// Overlay cards: day list < event details < event form.
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
				onCloseRequested: popup.closeEditor()
			}
		}
	}

	Loader {
		id: weekViewLoader
		active: popup.weekMode
		visible: active
		anchors.fill: widgetGrid
		sourceComponent: WeekView {
			eventModel: popup.eventModel
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
		visible: !popup.weekMode
		anchors.fill: parent
		anchors.margins: popup.padding
		anchors.topMargin: popup.viewTabsHeight
		columnSpacing: popup.spacing
		rowSpacing: popup.spacing
		onColumnsChanged: {
			// logger.debug(popup.state, widgetGrid.columns, widgetGrid.rows)
		}
		onRowsChanged: {
			// logger.debug(popup.state, widgetGrid.columns, widgetGrid.rows)
		}


		// Created only when shown.
		Loader {
			id: meteogramView
			visible: showMeteogram
			active: showMeteogram
			Layout.fillWidth: true
			Layout.minimumHeight: popup.topRowHeight
			Layout.preferredWidth: popup.leftColumnWidth
			Layout.preferredHeight: popup.topRowHeight
			onLoaded: popup.updateMeteogram()

			sourceComponent: MeteogramView {
				visibleDuration: plasmoid.configuration.meteogramHours
				showIconOutline: plasmoid.configuration.showOutlines
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
			Layout.minimumHeight: Math.max(popup.topRowHeight, implicitHeight)
			Layout.preferredWidth: popup.rightColumnWidth
			Layout.preferredHeight: popup.topRowHeight

			sourceComponent: TimerView {}
		}

		MonthView {
			id: monthView
			visible: showCalendar
			showHeader: false
			borderOpacity: appletConfig.showGridLines ? appletConfig.gridLineOpacity : appletConfig.faintGridLineOpacity
			showWeekNumbers: plasmoid.configuration.monthShowWeekNumbers
			highlightCurrentDayWeek: plasmoid.configuration.monthHighlightCurrentDayWeek

			Layout.preferredWidth: popup.leftColumnWidth
			Layout.preferredHeight: popup.bottomRowHeight
			Layout.fillWidth: true
			Layout.fillHeight: true
			// Next to the agenda, keep the calendar at its configured size; extra room goes to the agenda.
			Layout.maximumWidth: popup.twoColumns ? popup.leftColumnWidth : Number.POSITIVE_INFINITY
			Layout.maximumHeight: popup.twoColumns ? popup.bottomRowHeight : Number.POSITIVE_INFINITY
			Layout.alignment: Qt.AlignCenter

			// Component.onCompleted: {
			// 	today = new Date()
			// }

			function parseGCalEvents(data) {
				if (!(data && data.items)) {
					return
				}

				// https://github.com/KDE/plasma-framework/blob/master/src/declarativeimports/calendar/daysmodel.h
				// Bucket events per visible day in plain JS first, then write each day to the model once.
				var daysModel = monthView.daysModel
				var dayCount = daysModel.count
				var dayTimes = []
				var dayEvents = []
				for (var dayIndex = 0; dayIndex < dayCount; dayIndex++) {
					var dayData = daysModel.get(dayIndex)
					dayTimes.push(new Date(dayData.yearNumber, dayData.monthNumber - 1, dayData.dayNumber).getTime())
					dayEvents.push([])
				}

				var items = data.items
				for (var itemIndex = 0; itemIndex < items.length; itemIndex++) {
					var eventItem = items[itemIndex]
					var startTime = new Date(eventItem.startDateTime.getFullYear(), eventItem.startDateTime.getMonth(), eventItem.startDateTime.getDate()).getTime()
					var eventItemEndDate = new Date(eventItem.endDateTime.getFullYear(), eventItem.endDateTime.getMonth(), eventItem.endDateTime.getDate())
					if (eventItem.end.date) {
						// All day events end at midnight which is technically the next day.
						eventItemEndDate.setDate(eventItemEndDate.getDate() - 1)
					}
					var endTime = eventItemEndDate.getTime()
					for (var dayIndex = 0; dayIndex < dayCount; dayIndex++) {
						if (endTime < dayTimes[dayIndex]) {
							break
						}
						if (startTime <= dayTimes[dayIndex]) {
							dayEvents[dayIndex].push(eventItem)
						}
					}
				}

				// All-day events first, then by start time. Visible with the event titles badge.
				function compareEvents(a, b) {
					var aAllDay = !!(a.start && a.start.date)
					var bAllDay = !!(b.start && b.start.date)
					if (aAllDay !== bAllDay) {
						return aAllDay ? -1 : 1
					}
					return a.startDateTime - b.startDateTime
				}

				for (var dayIndex = 0; dayIndex < dayCount; dayIndex++) {
					dayEvents[dayIndex].sort(compareEvents)
					var events = daysModel.get(dayIndex).events
					events.clear()
					if (dayEvents[dayIndex].length) {
						events.append(dayEvents[dayIndex])
					}
					daysModel.setProperty(dayIndex, 'showEventBadge', dayEvents[dayIndex].length > 0)
				}
			}

			onDayDoubleClicked: function(dayData) {
				var date = new Date(dayData.yearNumber, dayData.monthNumber-1, dayData.dayNumber)
				// logger.debug('Popup.monthView.onDoubleClicked', date)
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

			onNewEventFormOpened: function(agendaItem, calendarSelector) {
				// logger.debug('onNewEventFormOpened')
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

			MessageWidget {
				id: errorMessageWidget
				anchors.left: parent.left
				anchors.bottom: parent.bottom
				anchors.right: parent.right
				anchors.margins: Kirigami.Units.smallSpacing
				text: logic.currentErrorMessage
			}

		} // AgendaView
	} // GridLayout

	function updateMeteogram() {
		if (meteogramView.item) {
			meteogramView.item.parseWeatherForecast(logic.currentWeatherData, logic.hourlyWeatherData)
		}
	}

	function showError(msg) {
		errorMessageWidget.warn(msg)
	}

	function clearError() {
		errorMessageWidget.close()
	}

	Timer {
		id: updateUITimer
		interval: 100
		onTriggered: popup.updateUI()
	}
	function deferredUpdateUI() {
		updateUITimer.restart()
	}

	function updateUI() {
		// logger.debug('updateUI')
		var now = new Date()

		if (updateUITimer.running) {
			updateUITimer.running = false
		}

		agendaModel.parseGCalEvents(eventModel.eventsData)
		agendaModel.parseWeatherForecast(logic.dailyWeatherData)
		monthView.parseGCalEvents(eventModel.eventsData)
		if (weekViewLoader.item) {
			weekViewLoader.item.rebuild()
		}
		scrollToSelection()
	}
}
