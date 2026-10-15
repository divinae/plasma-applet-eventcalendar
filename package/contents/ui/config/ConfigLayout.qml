import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Qt5Compat.GraphicalEffects as QtGraphicalEffects // Colorize

import ".."
import "../lib"

ConfigPage {
	id: page

	SystemPalette {
		id: syspal
	}

	//---
	HeaderText {
		text: i18n("Popup Mode")
	}
	ConfigSection {
		ConfigRadioButtonGroup {
			id: popupModeGroup
			configKey: 'popupMode'
			model: [
				{ value: 'month', text: i18n("Month: full month view with event titles, like mobile calendar apps") },
				{ value: 'week', text: i18n("Week: hour grid with events") },
				{ value: 'classic', text: i18n("Agenda: agenda and calendar (layout below)") },
			]
		}
		ConfigCheckBox {
			configKey: 'showViewTabs'
			text: i18n("Show Month / Week / Agenda tabs in the popup")
		}
		RowLayout {
			ConfigSpinBox {
				configKey: 'monthModeWidth'
				before: i18n("Month and week view size:")
				suffix: i18n("px")
				minimumValue: 300
				maximumValue: 3000
			}
			Label { text: "×" }
			ConfigSpinBox {
				configKey: 'monthModeHeight'
				suffix: i18n("px")
				minimumValue: 250
				maximumValue: 3000
			}
		}
	}

	HeaderText {
		text: i18n("Agenda and Calendar Layout")
	}

	//---
	ButtonGroup { id: layoutGroup }
	RadioButton {
		text: i18n("Calendar to the left of the Agenda (Two Columns)")
		ButtonGroup.group: layoutGroup
		checked: page.configBridge.read("twoColumns", true)
		onClicked: page.configBridge.write("twoColumns", true)
		Layout.fillWidth: false
		Layout.alignment: Qt.AlignHCenter
	}
	GridLayout {
		Layout.fillWidth: false
		Layout.alignment: Qt.AlignHCenter
		Layout.preferredWidth: 400 * Kirigami.Units.devicePixelRatio
		columns: 3

		//--- Row1
		ConfigDimension {
			configKey: 'leftColumnWidth'
			suffix: i18n("px")
			orientation: Qt.Horizontal
			lineColor: syspal.text
			Layout.column: 1
			Layout.row: 0
		}

		ConfigDimension {
			configKey: 'rightColumnWidth'
			suffix: i18n("px")
			orientation: Qt.Horizontal
			lineColor: syspal.text
			Layout.column: 2
			Layout.row: 0
		}

		//--- Row2
		ConfigDimension {
			configKey: 'topRowHeight'
			suffix: i18n("px")
			orientation: Qt.Vertical
			lineColor: syspal.text
			Layout.column: 0
			Layout.row: 1
		}

		//--- Row3
		ConfigDimension {
			configKey: 'bottomRowHeight'
			suffix: i18n("px")
			orientation: Qt.Vertical
			lineColor: syspal.text
			Layout.column: 0
			Layout.row: 2
		}

		//--- Center
		Item {
			Layout.column: 1
			Layout.row: 1
			Layout.columnSpan: 2
			Layout.rowSpan: 2

			implicitWidth: 300 * Kirigami.Units.devicePixelRatio
			implicitHeight: 300 * Kirigami.Units.devicePixelRatio

			Layout.fillWidth: true
			Layout.fillHeight: true

			Image {
				id: twoColumnsImage
				anchors.fill: parent
				source: Qt.resolvedUrl("../../images/twocolumns.svg")
				smooth: true
				visible: false
			}

			QtGraphicalEffects.ColorOverlay {
				anchors.fill: parent
				source: twoColumnsImage
				color: syspal.text
				opacity: 0.8
			}
		}
	}

	//---
	Item {
		implicitHeight: Kirigami.Units.largeSpacing * 2
	}

	//---
	RadioButton {
		text: i18n("Agenda below the Calendar (Single Column)")
		ButtonGroup.group: layoutGroup
		checked: !page.configBridge.read("twoColumns", true)
		onClicked: page.configBridge.write("twoColumns", false)
		Layout.fillWidth: false
		Layout.alignment: Qt.AlignHCenter
	}

	GridLayout {
		Layout.fillWidth: false
		Layout.alignment: Qt.AlignHCenter
		Layout.preferredWidth: 400 * Kirigami.Units.devicePixelRatio
		columns: 3

		//--- Row1
		Item {
			implicitWidth: 150 * Kirigami.Units.devicePixelRatio
			Layout.fillWidth: true
			Layout.column: 0
			Layout.row: 0
		}
		ConfigDimension {
			configKey: 'leftColumnWidth'
			suffix: i18n("px")
			orientation: Qt.Horizontal
			lineColor: syspal.text
			Layout.column: 1
			Layout.row: 0
		}

		//--- Row2
		ConfigDimension {
			configKey: 'monthHeightSingleColumn'
			suffix: i18n("px")
			orientation: Qt.Vertical
			lineColor: syspal.text
			Layout.column: 2
			Layout.row: 1
		}

		//--- Row3
		Item {
			implicitHeight: 150 * Kirigami.Units.devicePixelRatio
			Layout.column: 2
			Layout.row: 2
		}

		//--- Center
		Item {
			Layout.column: 0
			Layout.row: 1
			Layout.columnSpan: 2
			Layout.rowSpan: 2

			implicitWidth: 300 * Kirigami.Units.devicePixelRatio
			implicitHeight: 300 * Kirigami.Units.devicePixelRatio

			Layout.fillWidth: true
			Layout.fillHeight: true

			Image {
				id: singleColumnImage
				anchors.fill: parent
				source: Qt.resolvedUrl("../../images/singlecolumn.svg")
				smooth: true
				visible: false
			}

			QtGraphicalEffects.ColorOverlay {
				anchors.fill: parent
				source: singleColumnImage
				color: syspal.text
				opacity: 0.8
			}
		}
	}
}
