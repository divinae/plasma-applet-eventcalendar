import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kirigamiaddons.formcard as FormCard

import QtCore

import ".."
import "../lib"

// Settings > Calendars > iCalendar: .ics files and links shown as calendars, read-only (also
// offline: a file is read where it is). Local files only from the widget's data folder (it reads
// nothing else). Kept in icalCalendarList, read by calendars/ICalManager.qml.
ConfigSection {
	id: page


	// ~/.local/share/plasma_org.kde.plasma.eventcalendar, wherever the home is (/var/home on
	// Silverblue / Kinoite): icsjson.py reads local files from there only.
	readonly property string localCalendarDir: decodeURIComponent(String(StandardPaths.writableLocation(StandardPaths.HomeLocation)).replace(/^file:\/\//, '')) + '/.local/share/plasma_org.kde.plasma.eventcalendar'

	function normalizeLocalPath(value) {
		var path = String(value || "").trim()
		if (path.indexOf("file://") === 0) {
			path = path.slice(7)
		}
		return path
	}

	function isAllowedCalendarUrl(value) {
		var trimmed = String(value || "").trim()
		if (!trimmed) {
			return true
		}
		if (/^https?:\/\/\S+$/i.test(trimmed)) {
			return true
		}
		var path = normalizeLocalPath(trimmed)
		return path.indexOf(localCalendarDir + "/") === 0 && /\.ics$/i.test(path)
	}

	Base64JsonListModel {
		id: calendarsModel
		configKey: 'icalCalendarList'
		configBridge: page.configBridge

		function addCalendar() {
			addItem({
				url: '',
				name: 'Label',
				backgroundColor: '' + Kirigami.Theme.highlightColor,
				show: true,
				isReadOnly: true,
			})
		}

		function addNewCalendar() {
			var icsPath = localCalendarDir + '/calendar.ics'
			addItem({
				url: icsPath,
				name: 'Label',
				backgroundColor: '' + Kirigami.Theme.highlightColor,
				show: true,
				isReadOnly: true,
			})
		}
	}

	PythonModules {
		id: modulesCheck
		property string installError: ""
		Component.onCompleted: check()
	}
	// The Python modules missing (an install from the KDE Store): said before anything is tried,
	// with Install (lib/PythonModules.qml).
	Kirigami.InlineMessage {
		Layout.fillWidth: true
		Layout.margins: Kirigami.Units.largeSpacing
		visible: modulesCheck.present === false
		type: Kirigami.MessageType.Warning
		text: modulesCheck.installing ? i18n("Installing…")
			: i18n("The Python modules icalendar and recurring-ical-events aren't all installed: calendars, or their repeating events, can be missing.")
		actions: [
			Kirigami.Action {
				icon.name: "download"
				text: i18n("Install")
				enabled: !modulesCheck.installing
				tooltip: i18n("Downloads icalendar and recurring-ical-events into the widget's own folder.")
				onTriggered: modulesCheck.install(function(error) { modulesCheck.installError = error })
			}
		]
	}
	Kirigami.InlineMessage {
		Layout.fillWidth: true
		Layout.leftMargin: Kirigami.Units.largeSpacing
		Layout.rightMargin: Kirigami.Units.largeSpacing
		visible: !!modulesCheck.installError
		type: Kirigami.MessageType.Error
		text: modulesCheck.installError
	}

	FormCard.FormHeader {
		title: i18n("Calendars")
	}
	FormCard.FormCard {
		Repeater {
			model: calendarsModel
			delegate: ColumnLayout {
				id: calendarRow
				Layout.fillWidth: true
				spacing: 0
				FormCard.FormDelegateSeparator { visible: index > 0 }
				FormCard.AbstractFormDelegate {
					Layout.fillWidth: true
					background: null
					contentItem: ColumnLayout {
						spacing: Kirigami.Units.smallSpacing
						RowLayout {
							spacing: Kirigami.Units.smallSpacing
							CheckBox {
								checked: model.show
								onClicked: calendarsModel.setItemProperty(index, 'show', checked)
								ToolTip.text: i18n("Show this calendar")
								ToolTip.visible: hovered
							}
							Rectangle {
								implicitWidth: Kirigami.Units.iconSizes.small
								implicitHeight: implicitWidth
								radius: width / 2
								color: model.backgroundColor
							}
							TextField {
								Layout.fillWidth: true
								text: model.name
								placeholderText: i18n("Calendar Label")
								// The label was never saved before (no handler): now when edited.
								onEditingFinished: calendarsModel.setItemProperty(index, 'name', text.trim())
							}
							Button {
								icon.name: "edit-delete"
								onClicked: calendarsModel.removeIndex(index)
								ToolTip.text: i18n("Remove")
								ToolTip.visible: hovered
							}
						}
						RowLayout {
							spacing: Kirigami.Units.smallSpacing
							TextField {
								id: calendarUrlField
								Layout.fillWidth: true
								text: model.url
								placeholderText: i18n("https:// URL or local %1/*.ics file", localCalendarDir)
								onTextChanged: {
									if (isAllowedCalendarUrl(text)) {
										calendarsModel.setItemProperty(index, 'url', text.trim())
									}
								}
							}
							Button {
								icon.name: "folder-open"
								text: i18n("Browse")
								onClicked: filePicker.open()
								FileDialog {
									id: filePicker
									nameFilters: [ i18n("iCalendar (*.ics)") ]
									currentFolder: "file://" + localCalendarDir
									onAccepted: {
										var selected = selectedFile.toString()
										if (isAllowedCalendarUrl(selected)) {
											calendarUrlField.text = selected
										}
									}
								}
							}
						}
					}
				}
			}
		}
		FormCard.FormDelegateSeparator { visible: calendarsModel.count > 0 }
		FormCard.FormButtonDelegate {
			icon.name: "resource-calendar-insert"
			text: i18n("Add Calendar")
			description: i18n("An .ics link or a file")
			onClicked: calendarsModel.addCalendar()
		}
		FormCard.FormDelegateSeparator {}
		FormCard.FormButtonDelegate {
			icon.name: "resource-calendar-insert"
			text: i18n("New Calendar")
			description: i18n("A file in %1", localCalendarDir)
			onClicked: calendarsModel.addNewCalendar()
		}
	}
	FormCard.FormSectionText {
		Layout.fillWidth: true
		text: i18n(".ics files and links show here as calendars, read-only, offline too. Local files are read from %1. To add events to one of your calendars instead, import the file into a Google or CalDAV calendar (Calendars > General).", localCalendarDir)
	}
}
