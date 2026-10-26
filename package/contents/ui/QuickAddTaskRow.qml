import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "Tasks.js" as Tasks
import "QuickParse.js" as QuickParse

// "Add a task…" at the bottom of a task list (Tasks view) or of the day's tasks (Day view): a flat
// field lined up with the TaskRows, a "+" where their check is. Enter adds the task (on listId,
// else on the picked one of lists, due on dueDay or undated) without the editor, then the field is
// empty and ready for the next one; Esc empties it, or leaves it when empty.
// Smart recognition (Settings > Tasks, tasksSmartQuickAdd; QuickParse.js): the day, time, priority
// (!high), list (#Name) and repeat in the text are shown as chips under the field, each with an ✕
// to keep its words in the title instead.
Item {
	id: quickAdd

	property var eventModel: null
	// The list to add to; '' picks one of lists (the last used, else the first), with a picker when
	// there are several.
	property string listId: ""
	property var lists: []
	// The lists '#Name' can pick from (every list, also when lists is only the filter's).
	property var parseLists: lists
	// The new task's due day, 'YYYY-MM-DD', or '' for none.
	property string dueDay: ""
	// Lined up with compact TaskRows (Day view).
	property bool compact: false

	// The Tasks view makes its rows again on every change: the text typed so far and the focus
	// are kept in addDrafts ({ key: { text, focused } }, owned by the view) under draftKey.
	property string draftKey: ""
	property var addDrafts: null
	Component.onCompleted: {
		var draft = addDrafts && draftKey ? addDrafts[draftKey] : null
		if (draft) {
			field.text = draft.text || ""
			ignored = draft.ignored || []
			if (draft.focused) {
				field.forceActiveFocus()
			}
		}
	}
	function saveDraft() {
		if (addDrafts && draftKey) {
			var draft = addDrafts[draftKey] || {}
			draft.text = field.text
			draft.ignored = ignored
			addDrafts[draftKey] = draft
		}
	}

	property bool saving: false
	property string errorText: ""
	property string pickedListId: ""
	// The list picked or given, without what the text says.
	readonly property string baseListId: listId || Tasks.quickAddList(lists, pickedListId || String(plasmoid.configuration.tasksLastListId || ""))
	// '#Name' in the text wins over the picker and the filter's list.
	readonly property string targetListId: parsed.listId || baseListId
	function findList(id) {
		var all = parseLists.concat(lists)
		for (var i = 0; i < all.length; i++) {
			if (all[i].id === id) {
				return all[i]
			}
		}
		return null
	}
	readonly property var targetList: findList(targetListId)

	//--- Smart recognition
	readonly property bool smart: plasmoid.configuration.tasksSmartQuickAdd !== false
	// The tokens ruled out with their ✕ (QuickParse.tokenKey), until the field is emptied.
	property var ignored: []
	readonly property string today: Tasks.dayString(typeof timeModel !== "undefined" && timeModel ? timeModel.currentTime : new Date())
	readonly property var parsed: smart && field.text ? QuickParse.parse(field.text, {
		today: today,
		lists: parseLists,
		dayFirst: appletConfig.quickParseLocale.dayFirst,
		dayNames: appletConfig.quickParseLocale.dayNames,
		monthNames: appletConfig.quickParseLocale.monthNames,
		ignore: ignored,
	}) : { title: field.text, dueDay: '', dueTime: '', priority: 0, listId: '', repeatRule: '', tokens: [] }
	// What the target list's provider has: Google Tasks has no time, priority or repeat.
	readonly property var caps: eventModel && typeof eventModel.taskCapabilities === "function" && targetListId
		? eventModel.taskCapabilities(targetListId) : { dueTime: true, priority: true, repeat: true }
	function supports(kind) {
		return kind === 'time' ? !!caps.dueTime : kind === 'priority' ? !!caps.priority : kind === 'repeat' ? !!caps.repeat : true
	}
	function ignoreToken(token) {
		ignored = ignored.concat([QuickParse.tokenKey(token)])
		saveDraft()
		field.forceActiveFocus()
	}
	function priorityColor(priority) {
		return priority >= 5 ? "#e03b30" : priority >= 3 ? "#f0a020" : "#4c7cf6" // TaskCheck's
	}
	function dateFrom(day) {
		var parts = day.split('-')
		return new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
	}
	// A chip's text.
	function tokenLabel(token) {
		switch (token.kind) {
		case 'date':
			if (token.value === today) {
				return i18n("Today")
			}
			if (token.value === Tasks.addDays(today, 1)) {
				return i18n("Tomorrow")
			}
			var date = dateFrom(token.value)
			return i18nc("%1 = weekday, %2 = short date", "%1, %2", Qt.formatDate(date, "ddd"),
				Qt.formatDate(date, i18nc("short month+date format", "MMM d")))
		case 'time':
			return Qt.formatTime(new Date(2000, 0, 1, Number(token.value.substring(0, 2)), Number(token.value.substring(3, 5))), appletConfig.timeFormat)
		case 'priority':
			return token.value >= 5 ? i18n("High priority") : token.value >= 3 ? i18n("Medium priority") : i18n("Low priority")
		case 'list':
			var list = findList(token.value)
			return list ? list.name : token.text
		case 'repeat':
			return repeatLabel(token.value)
		}
		return token.text
	}
	function repeatLabel(rule) {
		var freq = (/FREQ=([A-Z]+)/.exec(rule) || [])[1] || ''
		var interval = Number((/INTERVAL=(\d+)/.exec(rule) || [])[1] || 1)
		var byDay = (/BYDAY=([A-Z,]+)/.exec(rule) || [])[1] || ''
		if (byDay === 'MO,TU,WE,TH,FR') {
			return i18n("Every weekday")
		}
		if (byDay) {
			var codes = ['SU', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA']
			return i18nc("%1 = weekday", "Every %1", Qt.locale().standaloneDayName(codes.indexOf(byDay), Locale.LongFormat))
		}
		switch (freq) {
		case 'DAILY': return interval > 1 ? i18np("Every day", "Every %1 days", interval) : i18n("Daily")
		case 'WEEKLY': return interval > 1 ? i18np("Every week", "Every %1 weeks", interval) : i18n("Weekly")
		case 'MONTHLY': return interval > 1 ? i18np("Every month", "Every %1 months", interval) : i18n("Monthly")
		case 'YEARLY': return interval > 1 ? i18np("Every year", "Every %1 years", interval) : i18n("Yearly")
		}
		return i18n("Repeats")
	}
	// A chip's color: the priority's, the list's, else the accent.
	function tokenColor(token) {
		if (token.kind === 'priority') {
			return priorityColor(token.value)
		}
		if (token.kind === 'list') {
			var list = findList(token.value)
			return appletConfig.eventColoredTextColor(appletConfig.eventColor(list && list.color ? list.color : null))
		}
		return Kirigami.Theme.highlightColor
	}
	readonly property bool showPicker: !listId && lists.length > 1
	readonly property real sideMargin: compact ? Kirigami.Units.smallSpacing * 2 : Kirigami.Units.largeSpacing
	readonly property int checkSize: 2 * Math.round(Math.min(Kirigami.Units.iconSizes.small * 1.1, field.implicitHeight) / 2)

	implicitWidth: layout.implicitWidth + sideMargin * 2
	implicitHeight: layout.implicitHeight + (compact ? 2 : Kirigami.Units.smallSpacing * 2)

	// The keyboard ("N" in the Tasks tab).
	function focusField() {
		field.forceActiveFocus()
	}
	// The new task: the text, or with smart recognition what's left of it and what was recognized
	// (only what the list's provider has).
	function taskBody() {
		if (!smart || !parsed.tokens.length) {
			return Tasks.quickAddBody(field.text, dueDay)
		}
		var title = parsed.title || field.text.trim()
		if (!title) {
			return null
		}
		var changes = { title: title }
		var time = supports('time') ? parsed.dueTime : ''
		var priority = supports('priority') ? parsed.priority : 0
		var repeat = supports('repeat') ? parsed.repeatRule : ''
		// A time or repeat needs a day: today when nothing says which.
		var day = parsed.dueDay || dueDay || (time || repeat ? today : '')
		if (day) {
			changes.dueDay = day
		}
		if (time) {
			changes.dueTime = time
		}
		if (priority) {
			changes.priority = priority
		}
		if (repeat) {
			changes.repeatRule = repeat
		}
		return Tasks.editBody(changes)
	}
	function add() {
		var body = taskBody()
		var target = targetListId
		var fromText = !!parsed.listId
		if (!body || !target || saving || !eventModel) {
			return
		}
		saving = true
		errorText = ""
		var row = quickAdd
		var drafts = addDrafts
		var key = draftKey
		eventModel.createEventFromData(target, body, function(err, item) {
			if (!err) {
				// Not the one '#Name' picked: the picker stays as it was.
				if (!fromText) {
					plasmoid.configuration.tasksLastListId = target
				}
				if (drafts && key && drafts[key]) {
					drafts[key].text = ""
				}
			}
			if (!row) {
				return // Gone meanwhile (rows made again)
			}
			row.saving = false
			if (err) {
				row.errorText = i18n("Couldn't add the task")
				row.restartErrorTimer()
				return
			}
			row.clear()
		})
	}

	function clear() {
		field.text = ""
		ignored = []
	}
	function restartErrorTimer() {
		errorTimer.restart()
	}
	Timer {
		id: errorTimer
		interval: 5000
		onTriggered: quickAdd.errorText = ""
	}

	ColumnLayout {
		id: layout
		anchors.left: parent.left
		anchors.right: parent.right
		anchors.verticalCenter: parent.verticalCenter
		anchors.leftMargin: quickAdd.sideMargin
		// The picker's arrow at the column's right edge, where the rows' chips end.
		anchors.rightMargin: quickAdd.showPicker ? Math.max(0, quickAdd.sideMargin - pickerButton.rightPadding) : quickAdd.sideMargin
		spacing: 0

		RowLayout {
			Layout.fillWidth: true
			spacing: Kirigami.Units.largeSpacing

			// The "+" where the rows have their check.
			Item {
				Layout.preferredWidth: quickAdd.checkSize
				Layout.preferredHeight: quickAdd.checkSize
				Kirigami.Icon {
					anchors.fill: parent
					visible: !quickAdd.saving
					source: "list-add"
					color: Kirigami.Theme.textColor
					isMask: true
					opacity: field.activeFocus ? 0.9 : 0.7
				}
				PlasmaComponents3.BusyIndicator {
					anchors.centerIn: parent
					width: parent.width + 4
					height: width
					visible: quickAdd.saving
					running: visible
				}
			}

			PlasmaComponents3.TextField {
				id: field
				Layout.fillWidth: true
				Layout.minimumWidth: 0
				leftPadding: 0
				rightPadding: 0
				// The recognized words, tinted behind the text.
				background: Item {
					clip: true // The text scrolls
					Repeater {
						model: quickAdd.parsed.tokens
						delegate: Rectangle {
							required property var modelData
							// Again when the text scrolls or changes.
							readonly property rect startRect: field.cursorPosition >= 0 && field.width > 0 ? field.positionToRectangle(modelData.start) : Qt.rect(0, 0, 0, 0)
							readonly property rect endRect: field.cursorPosition >= 0 && field.width > 0 ? field.positionToRectangle(modelData.end) : Qt.rect(0, 0, 0, 0)
							readonly property color tint: quickAdd.supports(modelData.kind) ? quickAdd.tokenColor(modelData) : Kirigami.Theme.disabledTextColor
							x: startRect.x - 1
							y: startRect.y
							width: Math.max(0, endRect.x - startRect.x) + 2
							height: startRect.height
							radius: 3
							color: Qt.rgba(tint.r, tint.g, tint.b, 0.2)
						}
					}
				}
				placeholderText: i18n("Add a task…")
				// Clear on the popup's translucent background too.
				placeholderTextColor: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.7)
				font.family: appletConfig.eventFont.family
				font.pointSize: appletConfig.eventFont.pointSize
				readOnly: quickAdd.saving
				opacity: quickAdd.saving ? 0.6 : 1
				Accessible.name: quickAdd.targetList ? i18nc("%1 = task list name", "Add a task to %1", quickAdd.targetList.name) : placeholderText
				onTextEdited: quickAdd.errorText = ""
				onTextChanged: {
					if (!text && quickAdd.ignored.length) {
						quickAdd.ignored = []
					}
					quickAdd.saveDraft()
				}
				onAccepted: quickAdd.add()
				Keys.onEscapePressed: function(event) {
					if (text) {
						quickAdd.clear()
						quickAdd.errorText = ""
					} else {
						focus = false
						// Back to the popup's keys (the Tasks tab's Up / Down, …).
						if (typeof popup !== "undefined" && popup && typeof popup.focusForKeys === "function") {
							popup.focusForKeys()
						}
					}
					event.accepted = true
				}
			}

			// The list it adds to, when there's a choice.
			PlasmaComponents3.ToolButton {
				id: pickerButton
				visible: quickAdd.showPicker
				Layout.maximumWidth: Kirigami.Units.gridUnit * 8
				flat: true
				text: quickAdd.targetList ? quickAdd.targetList.name : ""
				Accessible.name: i18nc("%1 = task list name", "Task list: %1", text)
				PlasmaComponents3.ToolTip.text: i18n("The list new tasks go to")
				PlasmaComponents3.ToolTip.visible: hovered
				contentItem: RowLayout {
					spacing: Kirigami.Units.smallSpacing
					Rectangle {
						implicitWidth: Math.round(Kirigami.Units.gridUnit * 0.5)
						implicitHeight: implicitWidth
						radius: width / 2
						color: appletConfig.eventColoredTextColor(appletConfig.eventColor(quickAdd.targetList && quickAdd.targetList.color ? quickAdd.targetList.color : null))
					}
					PlasmaComponents3.Label {
						Layout.fillWidth: true
						Layout.minimumWidth: 0
						text: pickerButton.text
						textFormat: Text.PlainText // User text (list name)
						font: quickAdd.detailFont
						opacity: 0.85
						elide: Text.ElideRight
					}
					Kirigami.Icon {
						implicitWidth: Kirigami.Units.iconSizes.small / 2 + 4
						implicitHeight: implicitWidth
						source: "arrow-down"
						opacity: 0.75
					}
				}
				onClicked: listMenu.popup(pickerButton, 0, pickerButton.height)
			}
		}

		// What the text says, under it: a chip each, with an ✕ to keep its words in the title.
		Flow {
			id: chips
			visible: quickAdd.parsed.tokens.length > 0
			Layout.fillWidth: true
			Layout.minimumWidth: 0
			Layout.leftMargin: quickAdd.checkSize + Kirigami.Units.largeSpacing
			Layout.topMargin: 2
			Layout.bottomMargin: 2
			spacing: Kirigami.Units.smallSpacing
			Repeater {
				model: quickAdd.parsed.tokens
				delegate: Rectangle {
					id: chip
					required property var modelData
					readonly property bool supported: quickAdd.supports(modelData.kind)
					readonly property color tint: supported ? quickAdd.tokenColor(modelData) : Kirigami.Theme.textColor
					readonly property string label: quickAdd.tokenLabel(modelData)
					width: Math.min(chips.width, chipRow.implicitWidth + Kirigami.Units.smallSpacing + 2)
					height: chipRow.implicitHeight + 2
					radius: height / 2
					color: Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.backgroundColor, tint, supported ? 0.16 : 0.08)
					border.width: 1
					border.color: Qt.rgba(tint.r, tint.g, tint.b, supported ? 0.35 : 0.15)
					opacity: supported ? 1 : 0.6
					Accessible.role: Accessible.StaticText
					Accessible.name: supported ? label : i18nc("%1 = recognized day, time, …", "%1 (not supported by Google Tasks)", label)

					HoverHandler {
						id: chipHover
					}
					PlasmaComponents3.ToolTip.text: i18n("Not supported by Google Tasks")
					PlasmaComponents3.ToolTip.visible: !chip.supported && chipHover.hovered

					RowLayout {
						id: chipRow
						anchors.left: parent.left
						anchors.right: parent.right
						anchors.verticalCenter: parent.verticalCenter
						anchors.leftMargin: Kirigami.Units.smallSpacing
						anchors.rightMargin: 2
						spacing: Math.round(Kirigami.Units.smallSpacing * 0.75)
						Rectangle {
							visible: chip.modelData.kind === 'list'
							implicitWidth: Math.round(Kirigami.Units.gridUnit * 0.45)
							implicitHeight: implicitWidth
							radius: width / 2
							color: chip.tint
						}
						Kirigami.Icon {
							visible: chip.modelData.kind !== 'list'
							implicitWidth: Math.round(Kirigami.Units.iconSizes.small * 0.75)
							implicitHeight: implicitWidth
							source: chip.modelData.kind === 'date' ? "view-calendar-day"
								: chip.modelData.kind === 'time' ? "clock"
								: chip.modelData.kind === 'priority' ? "flag"
								: "media-playlist-repeat"
							color: chip.modelData.kind === 'priority' && chip.supported ? chip.tint : Kirigami.Theme.textColor
							isMask: true
						}
						PlasmaComponents3.Label {
							Layout.fillWidth: true
							Layout.minimumWidth: 0
							text: chip.label
							textFormat: Text.PlainText // May be a list name or the user's words
							font.family: quickAdd.detailFont.family
							font.pointSize: quickAdd.detailFont.pointSize
							font.strikeout: !chip.supported
							elide: Text.ElideRight
						}
						QQC2.AbstractButton {
							id: ignoreButton
							implicitWidth: Kirigami.Units.iconSizes.small
							implicitHeight: implicitWidth
							focusPolicy: Qt.NoFocus
							Accessible.name: i18nc("%1 = the recognized words", "Keep \"%1\" in the title", chip.modelData.text)
							PlasmaComponents3.ToolTip.text: i18n("Keep these words in the title")
							PlasmaComponents3.ToolTip.visible: hovered
							contentItem: Kirigami.Icon {
								source: "window-close-symbolic"
								color: Kirigami.Theme.textColor
								isMask: true
								opacity: ignoreButton.hovered ? 1 : 0.6
							}
							background: Rectangle {
								radius: width / 2
								color: Kirigami.Theme.textColor
								opacity: ignoreButton.hovered ? 0.12 : 0
							}
							onClicked: quickAdd.ignoreToken(chip.modelData)
						}
					}
				}
			}
		}

		PlasmaComponents3.Label {
			visible: !!quickAdd.errorText
			Layout.fillWidth: true
			Layout.minimumWidth: 0
			Layout.leftMargin: quickAdd.checkSize + Kirigami.Units.largeSpacing
			text: quickAdd.errorText
			textFormat: Text.PlainText
			color: Kirigami.Theme.negativeTextColor
			font: quickAdd.detailFont
			elide: Text.ElideRight
		}
	}

	readonly property font detailFont: appletConfig.scaledFont(appletConfig.eventFont, 0.9)

	PlasmaComponents3.Menu {
		id: listMenu
		Instantiator {
			model: quickAdd.showPicker ? quickAdd.lists : []
			delegate: PlasmaComponents3.MenuItem {
				id: listMenuItem
				readonly property var list: modelData
				text: list.name // Shown by the plain text label below
				readonly property bool current: list.id === quickAdd.targetListId
				contentItem: RowLayout {
					spacing: Kirigami.Units.smallSpacing
					Rectangle {
						implicitWidth: Math.round(Kirigami.Units.gridUnit * 0.5)
						implicitHeight: implicitWidth
						radius: width / 2
						color: appletConfig.eventColoredTextColor(appletConfig.eventColor(listMenuItem.list.color || null))
					}
					PlasmaComponents3.Label {
						Layout.fillWidth: true
						text: listMenuItem.list.name
						textFormat: Text.PlainText // User text (list name)
						font.weight: listMenuItem.current ? Font.DemiBold : Font.Normal
						elide: Text.ElideRight
					}
				}
				onTriggered: {
					quickAdd.pickedListId = list.id
					plasmoid.configuration.tasksLastListId = list.id
					field.forceActiveFocus()
				}
			}
			onObjectAdded: function(index, object) { listMenu.insertItem(index, object) }
			onObjectRemoved: function(index, object) { listMenu.removeItem(object) }
		}
	}
}
