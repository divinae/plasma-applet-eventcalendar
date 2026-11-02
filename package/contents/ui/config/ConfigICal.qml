import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import org.kde.coreaddons as KCoreAddons

import ".."
import "../lib"

ConfigPage {
	id: page

	KCoreAddons.KUser {
		id: kuser
	}

	readonly property string localCalendarDir: '/home/' + kuser.loginName + '/.local/share/plasma_org.kde.plasma.eventcalendar'

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

	// Import: the events of an .ics file copied into one of your calendars (the widget opens its
	// import card for it: importRequest, see main.qml), as the widget menu's "Import Events…".
	HeaderText {
		text: i18n("Import Events")
	}
	Label {
		Layout.fillWidth: true
		text: i18n("Copy the events of an .ics file (exported from another calendar app) into one of your calendars. The widget shows them first, to pick the calendar.")
		wrapMode: Text.Wrap
	}
	Button {
		icon.name: "document-import"
		text: i18n("Import Events from a File…")
		onClicked: importFileDialog.open()
	}
	FileDialog {
		id: importFileDialog
		title: i18n("Import Events")
		nameFilters: [ i18n("iCalendar (*.ics)") ]
		onAccepted: {
			// Straight to the widget (not a setting applied with OK, no cfg_ property): it opens the
			// import card now.
			page.configBridge.write("importRequest", Date.now() + "|" + String(selectedFile))
		}
	}

	RowLayout {
		HeaderText {
			text: i18n("Calendars")
		}
		Button {
			icon.name: "resource-calendar-insert"
			text: i18n("Add Calendar")
			onClicked: calendarsModel.addCalendar()
		}
		Button {
			icon.name: "resource-calendar-insert"
			text: i18n("New Calendar")
			onClicked: calendarsModel.addNewCalendar()
		}
	}

	ColumnLayout {
		Layout.fillWidth: true
		spacing: 20 * Kirigami.Units.devicePixelRatio // x4 the default spacing (5px)

		Repeater {
			model: calendarsModel
			delegate: RowLayout {
				spacing: 0

				CheckBox {
					Layout.preferredHeight: labelTextField.height
					Layout.preferredWidth: height
					Layout.alignment: Qt.AlignTop
					checked: show

					onClicked: {
						calendarsModel.setProperty(index, 'show', checked)
					}
				}
				ColumnLayout {
					RowLayout {
						Rectangle {
							Layout.preferredHeight: labelTextField.height
							Layout.preferredWidth: height
							color: model.backgroundColor
						}
						TextField {
							id: labelTextField
							Layout.fillWidth: true
							text: model.name
							placeholderText: i18n("Calendar Label")
						}
						Button {
							icon.name: "trash-empty"
							onClicked: calendarsModel.removeIndex(index)
						}
					}
					RowLayout {
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
							onClicked: {
								filePicker.open()
							}

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
}
