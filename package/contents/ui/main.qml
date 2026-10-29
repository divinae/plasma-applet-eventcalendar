import QtCore
import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.config as KConfig
import org.kde.kcmutils as KCMUtils

import "./lib"
import "DayWeather.js" as DayWeather
import "Shared.js" as Shared
import "MeetingLink.js" as MeetingLink

PlasmoidItem {
	id: root

	Logger {
		id: logger
		name: 'eventcalendar'
		showDebug: plasmoid.configuration.debugging
	}

	ConfigMigration { id: configMigration }
	AppletConfig { id: appletConfig }
	NotificationManager { id: notificationManager }
	MeetingOpener { id: meetingOpener }
	FocusMode { id: focusMode }
	NetworkMonitor { id: networkMonitor }

	property alias eventModel: eventModel
	property alias agendaModel: agendaModel
	
	TimeModel { id: timeModel }
	TimerModel { id: timerModel }
	EventCache { id: eventCache }
	EventModel { id: eventModel }
	UpcomingEvents {
		id: upcomingEvents
		onMeetingAlertRequested: function(eventItem) { root.showMeetingAlert(eventItem) }
	}

	// The popup opened in a view (a notification's Show All / Show Tasks): after it opens in the
	// Default view, this one.
	function openPopupIn(view) {
		root.expanded = true
		Qt.callLater(function() {
			var popupItem = root.fullRepresentationItem
			if (popupItem && typeof popupItem.viewOffered === 'function' && popupItem.viewOffered(view)) {
				popupItem.currentView = view
				if (view === 'today') {
					Qt.callLater(function() { popupItem.goToDay(new Date()) }) // Today, not the day last shown
				}
			}
		})
	}

	//--- Full-screen meeting alert (UpcomingEvents.meetingAlertRequested), as the Fokus plasmoid's
	// break overlay: one window per screen, made only while the alert is up (windows made at startup
	// are a risk to plasmashell's start). Above panels and on every desktop through layer-shell when
	// it's installed: probed when needed, its files reached by URL only (MeetingAlertSetLayer.qml).
	property var alertEvent: null
	property var alertMeetingLink: null
	// The windows: blurred behind (Kicker's DashboardWindow, as Fokus) and through layer-shell when
	// those modules are there, each probed once when first needed; '' : the plain windows below.
	property string alertSetUrl: ""
	property var moduleProbes: ({})
	function moduleAvailable(probeFile) {
		if (!(probeFile in moduleProbes)) {
			var probe = Qt.createComponent(Qt.resolvedUrl(probeFile), Component.PreferSynchronous)
			moduleProbes[probeFile] = probe.status === Component.Ready
			probe.destroy()
		}
		return moduleProbes[probeFile]
	}
	function showMeetingAlert(eventItem) {
		alertSnoozeTimer.stop()
		var layer = moduleAvailable("LayerShellProbe.qml")
		var blur = moduleAvailable("KickerProbe.qml")
		alertSetUrl = blur && layer ? "MeetingAlertSetBlurLayer.qml"
			: blur ? "MeetingAlertSetBlur.qml"
			: layer ? "MeetingAlertSetLayer.qml" : ""
		alertMeetingLink = MeetingLink.find(eventItem)
		alertEvent = eventItem
	}
	function closeMeetingAlert() {
		alertEvent = null
	}
	function joinMeetingAlert() {
		if (alertMeetingLink) {
			meetingOpener.open(alertMeetingLink.url)
		}
		closeMeetingAlert()
	}
	function snoozeMeetingAlert() {
		alertSnoozeTimer.eventItem = alertEvent
		closeMeetingAlert()
		alertSnoozeTimer.restart()
	}
	Timer {
		id: alertSnoozeTimer
		property var eventItem: null
		interval: 60 * 1000
		onTriggered: {
			if (eventItem && eventItem.endDateTime > new Date() && !upcomingEvents.isMuted(eventItem)) {
				root.showMeetingAlert(eventItem)
			}
		}
	}
	Instantiator {
		active: !!root.alertEvent && !root.alertSetUrl
		model: Qt.application.screens
		delegate: MeetingAlertWindow {
			screen: modelData
			screenGeometry: Qt.rect(modelData.virtualX, modelData.virtualY, modelData.width, modelData.height)
			eventItem: root.alertEvent
			meetingLink: root.alertMeetingLink
			onJoinRequested: root.joinMeetingAlert()
			onSnoozeRequested: root.snoozeMeetingAlert()
			onCloseRequested: root.closeMeetingAlert()
		}
	}
	Loader {
		source: root.alertEvent && root.alertSetUrl ? Qt.resolvedUrl(root.alertSetUrl) : ""
		onLoaded: {
			item.eventItem = Qt.binding(function() { return root.alertEvent })
			item.meetingLink = Qt.binding(function() { return root.alertMeetingLink })
			item.joinRequested.connect(root.joinMeetingAlert)
			item.snoozeRequested.connect(root.snoozeMeetingAlert)
			item.closeRequested.connect(root.closeMeetingAlert)
		}
	}
	AgendaModel {
		id: agendaModel
		timeModel: timeModel
		Component.onCompleted: logger.debug('AgendaModel.onCompleted')
	}
	Logic { id: logic }
	// The daily forecast by day (Shared.dayKey): the views, the agenda and the tooltip.
	readonly property var weatherByDay: DayWeather.byDay(logic.dailyWeatherData)

	FontLoader {
		source: "../fonts/weathericons-regular-webfont.ttf"
	}

	function formatClipboardText() {
		return Shared.formatDateTime(timeModel.currentTime, Qt.locale().dateTimeFormat(Locale.LongFormat))
	}

	function copyCurrentDateTime() {
		clipboardHelper.copyText(formatClipboardText())
	}

	TextEdit {
		id: clipboardHelper
		visible: false
		function copyText(text) {
			clipboardHelper.text = text
			clipboardHelper.selectAll()
			clipboardHelper.copy()
		}
	}

	toolTipItem: Loader {
		id: tooltipLoader

		Layout.minimumWidth: item ? item.implicitWidth : 0
		Layout.maximumWidth: item ? item.implicitWidth : 0
		Layout.minimumHeight: item ? item.implicitHeight : 0
		Layout.maximumHeight: item ? item.implicitHeight : 0

		source: "TooltipView.qml"
		onStatusChanged: {
			if (status === Loader.Ready && item) {
				item.appletItem = root
			}
		}
	}

	Plasma5Support.DataSource {
		id: executable
		engine: "executable"
		connectedSources: []
		function onNewData(sourceName, data) {
			disconnectSource(sourceName) // cmd finished
		}
		function getUniqueId(cmd) {
			// Note: we assume that 'cmd' is executed quickly so that a previous call
			// with the same 'cmd' has already finished (otherwise no new cmd will be
			// added because it is already in the list)
			// Workaround: We append spaces onto the user's command to workaround this.
			var cmd2 = cmd
			for (var i = 0; i < 10; i++) {
				if (executable.connectedSources.includes(cmd2)) {
					cmd2 += ' '
				}
			}
			return cmd2
		}
		function exec(cmd) {
			connectSource(getUniqueId(cmd))
		}
	}

	property Component clockComponent: ClockView {
		id: clock

		currentTime: timeModel.currentTime

		MouseArea {
			id: mouseArea
			anchors.fill: parent

			property int wheelDelta: 0
			acceptedButtons: Qt.LeftButton | Qt.MiddleButton

			onClicked: function(mouse) {
				if (mouse.button === Qt.LeftButton) {
					root.expanded = !root.expanded
				} else if (mouse.button === Qt.MiddleButton) {
					upcomingEvents.joinNextEvent()
				}
			}

			onWheel: function(wheel) {
				var delta = wheel.angleDelta.y || wheel.angleDelta.x
				wheelDelta += delta

				// Magic number 120 for common "one click"
				// See: https://doc.qt.io/qt-5/qml-qtquick-wheelevent.html#angleDelta-prop
				while (wheelDelta >= 120) {
					wheelDelta -= 120
					onScrollUp()
				}
				while (wheelDelta <= -120) {
					wheelDelta += 120
					onScrollDown()
				}
			}

			function onScrollUp() {
				if (plasmoid.configuration.clockMouseWheel === 'RunCommands') {
					executable.exec(plasmoid.configuration.clockMouseWheelUp)
				}
			}
			function onScrollDown() {
				if (plasmoid.configuration.clockMouseWheel === 'RunCommands') {
					executable.exec(plasmoid.configuration.clockMouseWheelDown)
				}
			}
		}
	}

	property Component popupComponent: PopupView {
		id: popup

		eventModel: root.eventModel
		agendaModel: root.agendaModel
		onImportFileRequested: root.chooseImportFile()

		// If pin is enabled, we need to add some padding around the popup unless
		// * we're a desktop widget (no need)
		// * the timer widget is enabled since there's room in the top right
		property bool isPinVisible: {
			// plasmoid.location == PlasmaCore.Types.Floating when using plasmawindowed and when used as a desktop widget.
			return plasmoid.location !== PlasmaCore.Types.Floating
		}
		// The pin button lives in the popup's top bar.
		showPinButton: isPinVisible

		property bool isExpanded: root.expanded
		onIsExpandedChanged: {
			logger.debug('isExpanded', isExpanded)
			if (!isExpanded && !plasmoid.configuration.pin) {
				closeOverlays() // Don't come back to a stale search or event card.
			}
			if (isExpanded) {
				showDefaultView() // Each time it opens: Settings > Views > Default view
				updateToday()
				logic.updateWeather()
				Qt.callLater(focusForKeys) // Keyboard shortcuts (PopupView Keys)
			}
		}

		function updateToday() {
			setToday(timeModel.currentTime)
		}

		function setToday(d) {
			logger.debug('setToday', d)
			today = d
			logger.debug('currentTime', timeModel.currentTime)
			monthViewDate = today
			selectedDate = today
			scrollToSelection()
		}

		Connections {
			target: timeModel
			function onDateChanged() {
				popup.updateToday()
				logger.debug('root.onDateChanged', timeModel.currentTime, popup.today)
			}
		}
	}

	Plasmoid.backgroundHints: plasmoid.configuration.showBackground ? PlasmaCore.Types.DefaultBackground : PlasmaCore.Types.NoBackground
	hideOnWindowDeactivate: !plasmoid.configuration.pin

	property bool isDesktopContainment: plasmoid.location === PlasmaCore.Types.Floating
	preferredRepresentation: isDesktopContainment ? fullRepresentation : compactRepresentation
	compactRepresentation: clockComponent
	fullRepresentation: popupComponent

	// Right-click menu: the next meeting and event actions first, then the widget's data, then
	// the system settings for date and time (Plasma adds Configure / Remove after these).
	function openPopupAndNewEvent() {
		root.expanded = true
		Qt.callLater(function() {
			if (root.fullRepresentationItem && typeof root.fullRepresentationItem.newEvent === 'function') {
				root.fullRepresentationItem.newEvent(timeModel.currentTime)
			}
		})
	}
	readonly property bool hasGoogleAccounts: logic.parseGoogleAccounts().length > 0

	// Import a .ics file: pick it, then the popup shows its events in the import card.
	// The dialog is here, not in the popup: the popup may close while the dialog is open.
	function chooseImportFile() {
		importFileDialog.open()
	}
	FileDialog {
		id: importFileDialog
		title: i18n("Import Events")
		nameFilters: [ i18n("iCalendar (*.ics)") ]
		currentFolder: StandardPaths.standardLocations(StandardPaths.DownloadLocation)[0]
		onAccepted: {
			var fileUrl = String(selectedFile)
			root.expanded = true
			Qt.callLater(function() {
				if (root.fullRepresentationItem && typeof root.fullRepresentationItem.openImport === 'function') {
					root.fullRepresentationItem.openImport(fileUrl)
				}
			})
		}
	}

	Plasmoid.contextualActions: [
		PlasmaCore.Action {
			text: upcomingEvents.nextEventMeetingLink && upcomingEvents.nextEvent
				? i18nc("%1 = Google Meet, Zoom, ..., %2 = event title, %3 = when", "Join %1: %2 (%3)",
					upcomingEvents.nextEventMeetingLink.label, upcomingEvents.nextEvent.summary,
					upcomingEvents.formatTooltipStart(upcomingEvents.nextEvent, timeModel.currentTime))
				: ""
			icon.name: "call-start"
			visible: !!upcomingEvents.nextEventMeetingLink
			onTriggered: upcomingEvents.joinNextEvent()
		},
		PlasmaCore.Action {
			text: upcomingEvents.nextEventInProgress && upcomingEvents.nextEvent
				? i18nc("%1 = event title", "Mark “%1” as Ended", upcomingEvents.nextEvent.summary)
				: ""
			icon.name: "dialog-ok"
			visible: upcomingEvents.nextEventInProgress
			onTriggered: upcomingEvents.markEnded(upcomingEvents.nextEvent)
		},
		PlasmaCore.Action {
			text: i18n("New Event…")
			icon.name: "list-add"
			onTriggered: root.openPopupAndNewEvent()
		},
		PlasmaCore.Action {
			text: i18n("Import Events…")
			icon.name: "document-import"
			visible: root.hasGoogleAccounts
			onTriggered: root.chooseImportFile()
		},
		PlasmaCore.Action {
			text: i18n("Open Google Calendar")
			icon.name: "globe"
			visible: root.hasGoogleAccounts
			onTriggered: Qt.openUrlExternally("https://calendar.google.com/")
		},
		PlasmaCore.Action {
			isSeparator: true
		},
		PlasmaCore.Action {
			text: i18n("Refresh")
			icon.name: "view-refresh"
			onTriggered: logic.update()
		},
		PlasmaCore.Action {
			id: clipboardAction
			text: i18n("Copy Date and Time")
			icon.name: "edit-copy"
			onTriggered: copyCurrentDateTime()
		},
		PlasmaCore.Action {
			isSeparator: true
		},
		PlasmaCore.Action {
			text: i18nd("plasma_applet_org.kde.plasma.digitalclock", "Adjust Date and Time…")
			icon.name: "preferences-system-time"
			visible: KConfig.KAuthorized.authorize("kcm_clock")
			onTriggered: KCMUtils.KCMLauncher.openSystemSettings("kcm_clock")
		},
		PlasmaCore.Action {
			text: i18n("Date and Time Formats…")
			icon.name: "preferences-desktop-locale"
			visible: KConfig.KAuthorized.authorizeControlModule("kcm_regionandlang")
			onTriggered: KCMUtils.KCMLauncher.openSystemSettings("kcm_regionandlang")
		}
	]
}
