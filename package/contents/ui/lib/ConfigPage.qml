// Version 4

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
	id: page
	Layout.fillWidth: true
	implicitHeight: content.implicitHeight

	// BEGIN AUTO CFG PROPS
	property var cfg_debugging
	property var cfg_debuggingDefault
	property var cfg_pin
	property var cfg_pinDefault
	property var cfg_widgetShowMeteogram
	property var cfg_widgetShowMeteogramDefault
	property var cfg_widgetShowTimer
	property var cfg_widgetShowTimerDefault
	property var cfg_timerSfxEnabled
	property var cfg_timerSfxEnabledDefault
	property var cfg_timerSfxFilepath
	property var cfg_timerSfxFilepathDefault
	property var cfg_timerRepeats
	property var cfg_timerRepeatsDefault
	property var cfg_clockFontFamily
	property var cfg_clockFontFamilyDefault
	property var cfg_clockTimeFormat1
	property var cfg_clockTimeFormat1Default
	property var cfg_clockTimeFormat2
	property var cfg_clockTimeFormat2Default
	property var cfg_clockShowLine2
	property var cfg_clockShowLine2Default
	property var cfg_clockLine2HeightRatio
	property var cfg_clockLine2HeightRatioDefault
	property var cfg_clockLineBold1
	property var cfg_clockLineBold1Default
	property var cfg_clockLineBold2
	property var cfg_clockLineBold2Default
	property var cfg_clockMaxHeight
	property var cfg_clockMaxHeightDefault
	property var cfg_clockMouseWheel
	property var cfg_clockMouseWheelDefault
	property var cfg_clockMouseWheelUp
	property var cfg_clockMouseWheelUpDefault
	property var cfg_clockMouseWheelDown
	property var cfg_clockMouseWheelDownDefault
	property var cfg_showBackground
	property var cfg_showBackgroundDefault
	property var cfg_topRowHeight
	property var cfg_topRowHeightDefault
	property var cfg_rightColumnWidth
	property var cfg_rightColumnWidthDefault
	property var cfg_v73Migration
	property var cfg_v73MigrationDefault
	property var cfg_v72Migration
	property var cfg_v72MigrationDefault
	property var cfg_selectedTimeZones
	property var cfg_selectedTimeZonesDefault
	property var cfg_displayTimezoneAsCode
	property var cfg_displayTimezoneAsCodeDefault
	property var cfg_monthShowWeekNumbers
	property var cfg_monthShowWeekNumbersDefault
	property var cfg_monthDayDoubleClick
	property var cfg_monthDayDoubleClickDefault
	property var cfg_monthEventBadgeType
	property var cfg_monthEventBadgeTypeDefault
	property var cfg_firstDayOfWeek
	property var cfg_firstDayOfWeekDefault
	property var cfg_agendaBreakupMultiDayEvents
	property var cfg_agendaBreakupMultiDayEventsDefault
	property var cfg_agendaNewEventRememberCalendar
	property var cfg_agendaNewEventRememberCalendarDefault
	property var cfg_agendaNewEventLastCalendarId
	property var cfg_agendaNewEventLastCalendarIdDefault
	property var cfg_agendaMaxDescriptionLines
	property var cfg_agendaMaxDescriptionLinesDefault
	property var cfg_agendaShowEventDescription
	property var cfg_agendaShowEventDescriptionDefault
	property var cfg_agendaShowEventHangoutLink
	property var cfg_agendaShowEventHangoutLinkDefault
	property var cfg_agendaCondensedAllDayEvent
	property var cfg_agendaCondensedAllDayEventDefault
	property var cfg_agendaPlaceOverdueTasksOnToday
	property var cfg_agendaPlaceOverdueTasksOnTodayDefault
	property var cfg_dayTasksListId
	property var cfg_dayTasksListIdDefault
	property var cfg_tasksSmartHiddenLists
	property var cfg_tasksSmartHiddenListsDefault
	property var cfg_tasksSidebarCollapsed
	property var cfg_tasksSidebarCollapsedDefault
	property var cfg_tasksShowCompleted
	property var cfg_tasksShowCompletedDefault
	property var cfg_tasksGroupBy
	property var cfg_tasksGroupByDefault
	property var cfg_tasksFilter
	property var cfg_tasksFilterDefault
	property var cfg_tasksSortBy
	property var cfg_tasksSortByDefault
	property var cfg_tasksShowDetails
	property var cfg_tasksShowDetailsDefault
	property var cfg_tasksLastListId
	property var cfg_tasksLastListIdDefault
	property var cfg_tasksSmartQuickAdd
	property var cfg_tasksSmartQuickAddDefault
	property var cfg_eventsPollInterval
	property var cfg_eventsPollIntervalDefault
	property var cfg_icalCalendarList
	property var cfg_icalCalendarListDefault
	property var cfg_eventReminderNotificationEnabled
	property var cfg_eventReminderNotificationEnabledDefault
	property var cfg_eventReminderSfxEnabled
	property var cfg_eventReminderSfxEnabledDefault
	property var cfg_eventReminderSfxPath
	property var cfg_eventReminderSfxPathDefault
	property var cfg_eventReminderMinutesBefore
	property var cfg_eventReminderMinutesBeforeDefault
	property var cfg_eventStartingNotificationEnabled
	property var cfg_eventStartingNotificationEnabledDefault
	property var cfg_eventStartingSfxEnabled
	property var cfg_eventStartingSfxEnabledDefault
	property var cfg_eventStartingSfxPath
	property var cfg_eventStartingSfxPathDefault
	property var cfg_openMeteoLatitude
	property var cfg_openMeteoLatitudeDefault
	property var cfg_openMeteoLongitude
	property var cfg_openMeteoLongitudeDefault
	property var cfg_openMeteoLocationName
	property var cfg_openMeteoLocationNameDefault
	property var cfg_weatherShowInViews
	property var cfg_weatherShowInViewsDefault
	property var cfg_monthClickOpensDay
	property var cfg_monthClickOpensDayDefault
	property var cfg_showDeclinedEvents
	property var cfg_showDeclinedEventsDefault
	property var cfg_hiddenCalendarIds
	property var cfg_hiddenCalendarIdsDefault
	property var cfg_eventClickAction
	property var cfg_eventClickActionDefault
	property var cfg_eventFontScale
	property var cfg_eventFontScaleDefault
	property var cfg_weekViewWorkWeek
	property var cfg_weekViewWorkWeekDefault
	property var cfg_weekViewStartHour
	property var cfg_weekViewStartHourDefault
	property var cfg_weekViewEndHour
	property var cfg_weekViewEndHourDefault
	property var cfg_weekViewSecondTimeZone
	property var cfg_weekViewSecondTimeZoneDefault
	property var cfg_hiddenViewTabs
	property var cfg_hiddenViewTabsDefault
	property var cfg_showViewTabs
	property var cfg_showViewTabsDefault
	property var cfg_viewSwitcher
	property var cfg_viewSwitcherDefault
	property var cfg_v182Migration
	property var cfg_v182MigrationDefault
	property var cfg_popupMode
	property var cfg_popupModeDefault
	property var cfg_popupOpenLastView
	property var cfg_popupOpenLastViewDefault
	property var cfg_monthModeWidth
	property var cfg_monthModeWidthDefault
	property var cfg_monthModeHeight
	property var cfg_monthModeHeightDefault
	property var cfg_eventReminderUseGoogle
	property var cfg_eventReminderUseGoogleDefault
	property var cfg_meetLinkCommand
	property var cfg_meetLinkCommandDefault
	property var cfg_meetLinkAuthUser
	property var cfg_meetLinkAuthUserDefault
	property var cfg_invitationNotificationEnabled
	property var cfg_invitationNotificationEnabledDefault
	property var cfg_invitationsNotified
	property var cfg_invitationsNotifiedDefault
	property var cfg_meetingPauseMedia
	property var cfg_meetingPauseMediaDefault
	property var cfg_meetingAutoJoin
	property var cfg_meetingAutoJoinDefault
	property var cfg_meetingDoNotDisturb
	property var cfg_meetingDoNotDisturbDefault
	property var cfg_meetingDoNotDisturbAcceptedOnly
	property var cfg_meetingDoNotDisturbAcceptedOnlyDefault
	property var cfg_dailyAgendaEnabled
	property var cfg_dailyAgendaEnabledDefault
	property var cfg_dailyAgendaTime
	property var cfg_dailyAgendaTimeDefault
	property var cfg_dailyAgendaDay
	property var cfg_dailyAgendaDayDefault
	property var cfg_dailyAgendaTasks
	property var cfg_dailyAgendaTasksDefault
	property var cfg_taskRemindersEnabled
	property var cfg_taskRemindersEnabledDefault
	property var cfg_taskSummaryDay
	property var cfg_taskSummaryDayDefault
	property var cfg_clockShowNextEvent
	property var cfg_clockShowNextEventDefault
	property var cfg_clockNextEventMinutes
	property var cfg_clockNextEventMinutesDefault
	property var cfg_clockNextEventSkipAllDay
	property var cfg_clockNextEventSkipAllDayDefault
	property var cfg_hideDuplicateEvents
	property var cfg_hideDuplicateEventsDefault
	property var cfg_meetingStartCommand
	property var cfg_meetingStartCommandDefault
	property var cfg_meetingEndCommand
	property var cfg_meetingEndCommandDefault
	property var cfg_meetingFullScreenAlert
	property var cfg_meetingFullScreenAlertDefault
	property var cfg_meetingFullScreenAlertLinkOnly
	property var cfg_meetingFullScreenAlertLinkOnlyDefault
	property var cfg_clockNextEventLinkOnly
	property var cfg_clockNextEventLinkOnlyDefault
	property var cfg_clockNextEventAcceptedOnly
	property var cfg_clockNextEventAcceptedOnlyDefault
	property var cfg_clockNextEventMaxTitle
	property var cfg_clockNextEventMaxTitleDefault
	property var cfg_clockShowMeetingProgress
	property var cfg_clockShowMeetingProgressDefault
	property var cfg_eventReminderTimeout
	property var cfg_eventReminderTimeoutDefault
	property var cfg_eventReminderSnoozeMinutes
	property var cfg_eventReminderSnoozeMinutesDefault
	property var cfg_eventStartingPersistent
	property var cfg_eventStartingPersistentDefault
	property var cfg_eventStartingCritical
	property var cfg_eventStartingCriticalDefault
	property var cfg_eventNotificationActions
	property var cfg_eventNotificationActionsDefault
	property var cfg_eventNotifySkipAllDay
	property var cfg_eventNotifySkipAllDayDefault
	property var cfg_eventNotifySkipDeclined
	property var cfg_eventNotifySkipDeclinedDefault
	property var cfg_enabledCalendarPlugins
	property var cfg_enabledCalendarPluginsDefault
	property var cfg_enabledCalendarPluginsAllowEmpty
	property var cfg_enabledCalendarPluginsAllowEmptyDefault
	property var cfg_tickTickAccounts
	property var cfg_tickTickAccountsDefault
	property var cfg_googleAccounts
	property var cfg_googleAccountsDefault
	property var cfg_googleActiveAccountId
	property var cfg_googleActiveAccountIdDefault
	property var cfg_latestClientId
	property var cfg_latestClientIdDefault
	property var cfg_latestClientSecret
	property var cfg_latestClientSecretDefault
	property var cfg_useDesktopClient
	property var cfg_useDesktopClientDefault
	property var cfg_customClientId
	property var cfg_customClientIdDefault
	property var cfg_customClientSecret
	property var cfg_customClientSecretDefault
	property var cfg_sessionClientId
	property var cfg_sessionClientIdDefault
	property var cfg_sessionClientSecret
	property var cfg_sessionClientSecretDefault
	property var cfg_accessToken
	property var cfg_accessTokenDefault
	property var cfg_accessTokenType
	property var cfg_accessTokenTypeDefault
	property var cfg_accessTokenExpiresAt
	property var cfg_accessTokenExpiresAtDefault
	property var cfg_refreshToken
	property var cfg_refreshTokenDefault
	property var cfg_calendarList
	property var cfg_calendarListDefault
	property var cfg_calendarIdList
	property var cfg_calendarIdListDefault
	property var cfg_tasklistList
	property var cfg_tasklistListDefault
	property var cfg_tasklistIdList
	property var cfg_tasklistIdListDefault
	property var cfg_googleEventClickAction
	property var cfg_googleEventClickActionDefault
	property var cfg_eventLook
	property var cfg_eventLookDefault
	property var cfg_uiStyle
	property var cfg_uiStyleDefault
	property var cfg_animationsEnabled
	property var cfg_dayUpNextCount
	property var cfg_dayUpNextCountDefault
	property var cfg_animationsEnabledDefault
	property var cfg_googleColorPalette
	property var cfg_googleColorPaletteDefault
	property var cfg_googleHideGoalsDesc
	property var cfg_googleHideGoalsDescDefault
	property var cfg_access_token
	property var cfg_access_tokenDefault
	property var cfg_openWeatherMapAppId
	property var cfg_openWeatherMapAppIdDefault
	property var cfg_openWeatherMapApi
	property var cfg_openWeatherMapApiDefault
	property var cfg_openWeatherMapCityId
	property var cfg_openWeatherMapCityIdDefault
	property var cfg_weatherCanadaCityId
	property var cfg_weatherCanadaCityIdDefault
	property var cfg_weatherService
	property var cfg_weatherServiceDefault
	property var cfg_weatherUnits
	property var cfg_weatherUnitsDefault
	property var cfg_weatherIconStyle
	property var cfg_weatherIconStyleDefault
	property var cfg_weatherIconBackground
	property var cfg_weatherIconBackgroundDefault
	property var cfg_weatherChartStyle
	property var cfg_weatherChartStyleDefault
	property var cfg_weatherChartLargeIcons
	property var cfg_weatherChartLargeIconsDefault
	property var cfg_weatherChartRainAmounts
	property var cfg_weatherChartRainAmountsDefault
	property var cfg_meteogramHours
	property var cfg_meteogramHoursDefault
	property var cfg_eventCacheEnabled
	property var cfg_eventCacheEnabledDefault
	property var cfg_tasksInProgress
	property var cfg_tasksInProgressDefault
	property var cfg_dayShowMiniMonth
	property var cfg_dayShowMiniMonthDefault
	property var cfg_dayShowUpNext
	property var cfg_dayShowUpNextDefault
	property var cfg_dayShowWeather
	property var cfg_dayShowWeatherDefault
	property var cfg_dayShowTasks
	property var cfg_dayShowTasksDefault
	// END AUTO CFG PROPS

	property QtObject configBridge: QtObject {
		function read(key, fallback) {
			var prop = "cfg_" + key
			if (prop in page) {
				var value = page[prop]
				return typeof value === "undefined" ? fallback : value
			}
			if (typeof plasmoid !== "undefined" && plasmoid.configuration) {
				var directValue = plasmoid.configuration[key]
				return typeof directValue === "undefined" ? fallback : directValue
			}
			return fallback
		}

		function readDefault(key, fallback) {
			var prop = "cfg_" + key + "Default"
			if (prop in page) {
				var value = page[prop]
				return typeof value === "undefined" ? fallback : value
			}
			if (typeof plasmoid !== "undefined" && plasmoid.configuration) {
				var directValue = plasmoid.configuration[key + "Default"]
				return typeof directValue === "undefined" ? fallback : directValue
			}
			return fallback
		}

		function isEqual(a, b) {
			if (a === b) return true
			if (typeof a === 'object' && typeof b === 'object') {
				return JSON.stringify(a) === JSON.stringify(b)
			}
			return false
		}

		function write(key, value) {
			var prop = "cfg_" + key
			if (prop in page) {
				if (isEqual(page[prop], value)) {
					return
				}
				page[prop] = value
			} else if (typeof plasmoid !== "undefined" && plasmoid.configuration) {
				if (isEqual(plasmoid.configuration[key], value)) {
					return
				}
				plasmoid.configuration[key] = value
			}
			if (typeof kcm !== "undefined") {
				kcm.needsSave = true
			}
		}
	}


	ColumnLayout {
		id: content
		anchors.left: parent.left
		anchors.right: parent.right
		anchors.top: parent.top
		spacing: Kirigami.Units.smallSpacing

		// Workaround for crash when using default on a Layout.
		// https://bugreports.qt.io/browse/QTBUG-52490
		// Still affecting Qt 5.7.0
		Component.onDestruction: {
			while (children.length > 0) {
				children[children.length - 1].parent = page
			}
		}
	}

	function clearItemAnchors(item) {
		if (!item || !item.anchors) {
			return
		}
		item.anchors.left = undefined
		item.anchors.right = undefined
		item.anchors.top = undefined
		item.anchors.bottom = undefined
		item.anchors.fill = undefined
		item.anchors.centerIn = undefined
		item.anchors.horizontalCenter = undefined
		item.anchors.verticalCenter = undefined
	}

	Component.onCompleted: {
		var items = []
		for (var i = 0; i < scrollablePageChildren.length; i++) {
			items.push(scrollablePageChildren[i])
		}
		for (var j = 0; j < items.length; j++) {
			var child = items[j]
			if (!child || child === content) {
				continue
			}
			clearItemAnchors(child)
			child.parent = content
		}
	}
}
