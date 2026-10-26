import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "LocaleFuncs.js" as LocaleFuncs
import "IcsImport.js" as IcsImport
import "Recurrence.js" as Recurrence
import "ScriptPath.js" as ScriptPath
import "lib"

// Import the events of a .ics file (eg: an invitation saved from an email, or an export) into a
// Google calendar. The file is read with scripts/icsjson.py; each event is sent to Google's
// events.import, which keeps its iCalUID: importing the same file again updates the events.
Item {
	id: importView

	property string fileUrl: ""
	signal closeRequested()
	signal chooseFileRequested()

	property var items: [] // icsjson.py events
	property var checked: [] // Per item
	property var rowStatus: [] // Per item: '' | 'ok' | an error message
	property int skippedCount: 0 // Cancelled events in the file
	property bool loading: false
	property string loadError: ""
	property bool importing: false
	property bool finished: false
	property int importedCount: 0
	property int failedCount: 0
	property string firstError: ""
	property int generation: 0 // Answers for an older file are ignored.

	readonly property int checkedCount: checked.filter(function(c) { return c }).length
	readonly property bool hasCalendars: !!calendarSelector.selectedCalendarId
	readonly property bool canImport: !loading && !importing && !finished && checkedCount > 0 && hasCalendars

	readonly property string fileName: {
		var name = decodeURIComponent(String(fileUrl).replace(/^file:\/\//, ''))
		return name.slice(name.lastIndexOf('/') + 1)
	}

	implicitHeight: actionsRow.implicitHeight + Kirigami.Units.smallSpacing * 2 + 1
		+ fieldsColumn.implicitHeight + Kirigami.Units.largeSpacing * 2

	ExecUtil { id: executable }

	function readFile() {
		generation += 1
		var gen = generation
		items = []
		checked = []
		rowStatus = []
		skippedCount = 0
		loadError = ""
		finished = false
		importedCount = 0
		failedCount = 0
		firstError = ""
		if (!fileUrl) {
			return
		}
		loading = true
		var cmd = [
			'python3',
			ScriptPath.scriptPath("icsjson.py"),
			'events',
			String(fileUrl),
		]
		executable.execArgv(cmd, function(cmd, exitCode, exitStatus, stdout, stderr) {
			if (gen !== importView.generation) {
				return
			}
			importView.loading = false
			if (exitCode) {
				importView.loadError = importView.processError(stderr || stdout)
				return
			}
			try {
				var parsed = JSON.parse(stdout)
				if (!(parsed && Array.isArray(parsed.items))) {
					throw new Error("invalid event list")
				}
				importView.skippedCount = parsed.skipped || 0
				importView.items = parsed.items
				importView.checked = parsed.items.map(function() { return true })
				importView.rowStatus = parsed.items.map(function() { return '' })
			} catch (err) {
				importView.loadError = i18n("Could not read the file.")
			}
		})
	}

	// The helper's error, for the card only (it's never logged: it may quote the file).
	function processError(output) {
		var text = String(output || "")
		if (/No module named '?icalendar/.test(text)) {
			return i18n("Reading .ics files needs the Python icalendar module (python-icalendar).")
		}
		var lines = text.split('\n').map(function(l) { return l.trim() }).filter(function(l) { return l })
		var last = lines.length ? lines[lines.length - 1].replace(/^\w+(Error|Exception): /, '') : ""
		return last ? i18n("Could not read the file: %1", last.slice(0, 200)) : i18n("Could not read the file.")
	}

	function setChecked(index, value) {
		var list = checked.slice()
		list[index] = value
		checked = list
	}

	function startImport() {
		if (!canImport) {
			return
		}
		var calendarId = calendarSelector.selectedCalendarId
		var timeZone = calendarSelector.selectedCalendar.timeZone || 'UTC'
		var queue = IcsImport.importOrder(items).filter(function(i) { return checked[i] })
		var statuses = items.map(function() { return '' })
		importing = true
		importedCount = 0
		failedCount = 0
		firstError = ""
		if (plasmoid.configuration.agendaNewEventRememberCalendar) {
			plasmoid.configuration.agendaNewEventLastCalendarId = calendarId
		}
		var gen = generation
		// One at a time: a series goes in before its changed occurrences.
		var next = function() {
			if (gen !== importView.generation) {
				return
			}
			if (!queue.length) {
				importView.rowStatus = statuses
				importView.importing = false
				importView.finished = true
				if (importView.importedCount > 0) {
					logic.update()
				}
				return
			}
			var index = queue.shift()
			var body = IcsImport.googleEventBody(items[index], timeZone)
			eventModel.importEvent(calendarId, body, function(err, data) {
				if (err) {
					statuses[index] = String(err)
					importView.failedCount += 1
					if (!importView.firstError) {
						importView.firstError = String(err)
					}
				} else {
					statuses[index] = 'ok'
					importView.importedCount += 1
				}
				importView.rowStatus = statuses.slice()
				next()
			})
		}
		next()
	}

	// "Thu 22 Oct · 14:00 – 15:00" (local time), "Mon 2 Nov – Tue 3 Nov", ...
	function whenText(item) {
		var e = {
			start: item.start,
			end: item.end,
			startDateTime: IcsImport.toDate(item.start),
			endDateTime: IcsImport.toDate(item.end),
		}
		if (!e.startDateTime || !e.endDateTime) {
			return ""
		}
		return LocaleFuncs.formatWhen(e, appletConfig.timeFormat, timeModel.currentTime)
	}

	// "Weekly on Mon, Wed, until 31/12/2026 · 3 exceptions"
	function repeatText(item) {
		var rule = Recurrence.ruleOf(item.recurrence)
		if (!rule) {
			return item.recurrenceId ? i18n("Changed occurrence of a repeating event") : ""
		}
		var r = Recurrence.parseRule(rule)
		var n = r.interval
		var text
		if (r.freq === 'DAILY') {
			text = n > 1 ? i18np("Every %1 day", "Every %1 days", n) : i18n("Daily")
		} else if (r.freq === 'WEEKLY') {
			text = n > 1 ? i18np("Every %1 week", "Every %1 weeks", n) : i18n("Weekly")
			var days = r.byDay.map(function(code) {
				var index = Recurrence.dayCodes.indexOf(code)
				return index >= 0 ? Qt.locale().dayName(index, Locale.ShortFormat) : ''
			}).filter(function(d) { return d })
			if (days.length) {
				text = i18nc("%1 = Weekly / Every 2 weeks, %2 = days", "%1 on %2", text, days.join(', '))
			}
		} else if (r.freq === 'MONTHLY') {
			text = n > 1 ? i18np("Every %1 month", "Every %1 months", n) : i18n("Monthly")
		} else if (r.freq === 'YEARLY') {
			text = n > 1 ? i18np("Every %1 year", "Every %1 years", n) : i18n("Yearly")
		} else {
			text = i18n("Repeats")
		}
		if (r.count > 0) {
			text = i18ncp("%2 = Weekly on Monday, ...", "%2, %1 time", "%2, %1 times", r.count, text)
		} else if (r.until) {
			text = i18nc("%1 = Weekly on Monday, ..., %2 = date", "%1, until %2", text,
				Qt.formatDate(r.until, Qt.locale().dateFormat(Locale.ShortFormat)))
		}
		var exceptions = IcsImport.exceptionCount(item)
		if (exceptions > 0) {
			text += ' · ' + i18np("%1 exception", "%1 exceptions", exceptions)
		}
		return text
	}

	onFileUrlChanged: readFile()
	Keys.onEscapePressed: closeRequested()
	Component.onCompleted: {
		var calendarList = eventModel.getCalendarList().filter(function(c) {
			return !c.isTasklist && eventModel.supportsImport(c.id)
		})
		calendarSelector.populate(calendarList, plasmoid.configuration.agendaNewEventLastCalendarId)
		readFile()
		forceActiveFocus()
	}

	ColumnLayout {
		anchors.fill: parent
		spacing: 0

		// Cancel on the left, title centered, Import on the right.
		CardHeader {
			id: actionsRow
			Layout.fillWidth: true
			Layout.margins: Kirigami.Units.smallSpacing
			title: i18n("Import Events")
			cancelText: importView.finished ? i18n("Close") : i18n("Cancel")
			actionText: i18n("Import")
			actionIcon: "document-import"
			actionEnabled: importView.canImport
			onCancelClicked: importView.closeRequested()
			onActionClicked: importView.startImport()
		}

		Kirigami.Separator {
			Layout.fillWidth: true
		}

		ColumnLayout {
			id: fieldsColumn
			Layout.fillWidth: true
			Layout.fillHeight: true
			Layout.margins: Kirigami.Units.largeSpacing
			spacing: Kirigami.Units.largeSpacing

			// The file, and another one.
			RowLayout {
				Layout.fillWidth: true
				Kirigami.Icon {
					source: "text-calendar"
					Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
					Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
				}
				PlasmaComponents3.Label {
					Layout.fillWidth: true
					elide: Text.ElideMiddle
					font.bold: true
					text: importView.fileName || i18n("No file chosen")
					textFormat: Text.PlainText
				}
				PlasmaComponents3.ToolButton {
					icon.name: "document-open"
					text: i18n("Choose File…")
					enabled: !importView.importing
					onClicked: importView.chooseFileRequested()
				}
			}

			PlasmaComponents3.Label {
				visible: importView.loading || !!importView.loadError || (!importView.loading && !!importView.fileUrl && importView.items.length === 0)
				Layout.fillWidth: true
				wrapMode: Text.Wrap
				color: importView.loadError ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
				opacity: importView.loadError ? 1 : 0.6
				text: {
					if (importView.loading) {
						return i18n("Reading the file…")
					}
					if (importView.loadError) {
						return importView.loadError
					}
					return i18n("No events in this file")
				}
			}

			// The file's events, all checked.
			PlasmaComponents3.ScrollView {
				id: scrollView
				visible: importView.items.length > 0
				Layout.fillWidth: true
				Layout.fillHeight: true
				Layout.preferredHeight: Math.min(eventsColumn.implicitHeight, Kirigami.Units.gridUnit * 16)
				Layout.minimumHeight: Math.min(eventsColumn.implicitHeight, Kirigami.Units.gridUnit * 4)
				contentWidth: availableWidth
				QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

				ColumnLayout {
					id: eventsColumn
					width: scrollView.availableWidth
					spacing: Kirigami.Units.smallSpacing

					Repeater {
						model: importView.items
						RowLayout {
							id: eventRow
							readonly property var item: modelData
							readonly property string status: importView.rowStatus[index] || ''
							Layout.fillWidth: true
							spacing: Kirigami.Units.smallSpacing

							PlasmaComponents3.CheckBox {
								Layout.alignment: Qt.AlignTop
								checked: !!importView.checked[index]
								enabled: !importView.importing && !importView.finished
								onToggled: importView.setChecked(index, checked)
							}
							ColumnLayout {
								Layout.fillWidth: true
								spacing: 0
								PlasmaComponents3.Label {
									Layout.fillWidth: true
									wrapMode: Text.Wrap
									text: eventRow.item.summary || i18n("(No title)")
									textFormat: Text.PlainText // User text: never parsed as HTML
								}
								PlasmaComponents3.Label {
									Layout.fillWidth: true
									wrapMode: Text.Wrap
									opacity: 0.7
									font: Kirigami.Theme.smallFont
									text: {
										var parts = [importView.whenText(eventRow.item)]
										var repeat = importView.repeatText(eventRow.item)
										if (repeat) {
											parts.push(repeat)
										}
										if (eventRow.item.location) {
											parts.push(eventRow.item.location)
										}
										return parts.filter(function(p) { return p }).join(' · ')
									}
								}
								PlasmaComponents3.Label {
									visible: eventRow.status !== '' && eventRow.status !== 'ok'
									Layout.fillWidth: true
									wrapMode: Text.Wrap
									color: Kirigami.Theme.negativeTextColor
									font: Kirigami.Theme.smallFont
									text: eventRow.status
								}
							}
							Kirigami.Icon {
								visible: eventRow.status !== ''
								Layout.alignment: Qt.AlignTop
								Layout.preferredWidth: Kirigami.Units.iconSizes.small
								Layout.preferredHeight: Kirigami.Units.iconSizes.small
								source: eventRow.status === 'ok' ? "dialog-ok-apply" : "dialog-error"
							}
						}
					}
				}
			}

			PlasmaComponents3.Label {
				visible: importView.skippedCount > 0
				Layout.fillWidth: true
				wrapMode: Text.Wrap
				opacity: 0.6
				font: Kirigami.Theme.smallFont
				text: i18np("%1 cancelled event isn't imported.", "%1 cancelled events aren't imported.", importView.skippedCount)
			}

			RowLayout {
				Layout.fillWidth: true
				visible: importView.hasCalendars
				PlasmaComponents3.Label {
					text: i18n("Calendar:")
				}
				CalendarSelector {
					id: calendarSelector
					Layout.fillWidth: true
					enabled: !importView.importing && !importView.finished
				}
			}

			PlasmaComponents3.Label {
				Layout.fillWidth: true
				wrapMode: Text.Wrap
				opacity: importView.hasCalendars ? 0.6 : 1
				color: importView.hasCalendars ? Kirigami.Theme.textColor : Kirigami.Theme.negativeTextColor
				font: Kirigami.Theme.smallFont
				text: importView.hasCalendars
					? i18n("Guests and the organizer aren't imported, and no invitations are sent. Importing the same event again updates it.")
					: i18n("Importing needs a Google Calendar you can edit. Log in to Google Calendar in the settings.")
			}

			// Progress, then the result.
			RowLayout {
				visible: importView.importing || importView.finished
				Layout.fillWidth: true
				PlasmaComponents3.BusyIndicator {
					visible: importView.importing
					Layout.preferredWidth: Kirigami.Units.iconSizes.small
					Layout.preferredHeight: Kirigami.Units.iconSizes.small
					running: visible
				}
				PlasmaComponents3.Label {
					Layout.fillWidth: true
					wrapMode: Text.Wrap
					color: importView.failedCount > 0 ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.positiveTextColor
					text: {
						if (importView.importing) {
							return i18n("Importing… %1 of %2", importView.importedCount + importView.failedCount + 1, importView.checkedCount)
						}
						var parts = [i18np("%1 event imported", "%1 events imported", importView.importedCount)]
						if (importView.failedCount > 0) {
							parts.push(i18np("%1 failed: %2", "%1 failed, eg: %2", importView.failedCount, importView.firstError))
						}
						return parts.join(' · ')
					}
				}
			}
		}
	}
}
