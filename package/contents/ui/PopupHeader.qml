import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras

// Native Plasma header for all popup views: view switcher, title with navigation (month or
// week / day), new event, refresh and pin. The month and week views hide their own header rows.
PlasmaExtras.PlasmoidHeading {
	id: header

	property Item monthViewItem
	property Item weekViewItem // Week and Day views, null otherwise
	// The view with its own title and navigation (goPrevious, goNext, goToday), null: the month view.
	readonly property Item navViewItem: weekViewItem
	property bool showViewTabs: true
	property bool showPinButton: true
	property bool refreshing: false

	signal viewSelected(string mode)
	signal newEventClicked()
	signal searchClicked()
	signal refreshClicked()

	// Left: view switcher. Center: navigation and title. Right: calendars, search, new event, refresh, pin.
	contentItem: Item {
		id: topBar
		implicitHeight: Math.max(leftGroup.implicitHeight, centerGroup.implicitHeight, rightGroup.implicitHeight)
		readonly property real sideWidth: Math.max(leftGroup.implicitWidth, rightGroup.implicitWidth)
		// Not enough room for the view names next to the title: icons only (names in tooltips).
		readonly property bool compactTabs: header.showViewTabs
			&& width < Math.max(fullTabsMeasure.implicitWidth, rightGroup.implicitWidth) * 2 + centerGroup.implicitWidth + Kirigami.Units.largeSpacing * 2

		readonly property var viewTabs: [
			{ mode: 'month', icon: "view-calendar-month", text: i18n("Month") },
			{ mode: 'week', icon: "view-calendar-week", text: i18n("Week") },
			{ mode: 'today', icon: "view-calendar-day", text: i18nc("calendar view showing one day", "Day") },
			{ mode: 'classic', icon: "view-calendar-agenda", text: i18n("Agenda") },
		]
		// The view switcher's width with names, measured off screen.
		Row {
			id: fullTabsMeasure
			visible: false
			spacing: 2
			Repeater {
				model: topBar.viewTabs
				PlasmaComponents3.ToolButton {
					icon.name: modelData.icon
					text: modelData.text
					display: QQC2.AbstractButton.TextBesideIcon
				}
			}
		}

		RowLayout {
			id: leftGroup
			anchors.left: parent.left
			anchors.verticalCenter: parent.verticalCenter
			spacing: 0
			// View switcher: flat buttons with icon and text, the current view on a soft rounded tint.
			RowLayout {
				visible: header.showViewTabs
				Layout.alignment: Qt.AlignVCenter
				spacing: 2

				Repeater {
					model: topBar.viewTabs
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
							display: topBar.compactTabs ? QQC2.AbstractButton.IconOnly : QQC2.AbstractButton.TextBesideIcon
							PlasmaComponents3.ToolTip.text: modelData.text
							PlasmaComponents3.ToolTip.visible: topBar.compactTabs && hovered
							// Not checkable: the style's checked look changes the size and elides the text.
							onClicked: header.viewSelected(modelData.mode)
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
			// Full text width (a Text's implicitWidth ignores eliding), and the gap to the buttons as
			// its own item: a Layout margin was taken out of that width and cut the title off.
			Kirigami.Heading {
				id: titleHeading
				Layout.preferredWidth: Math.ceil(implicitWidth) // Fractional at 2x scale: rounding down elided it
				Layout.maximumWidth: Math.ceil(implicitWidth)
				Layout.minimumWidth: 0
				Layout.fillWidth: true
				level: 2
				elide: Text.ElideRight
				wrapMode: Text.NoWrap
				font.capitalization: Font.Capitalize
				text: header.navViewItem ? header.navViewItem.title : (header.monthViewItem ? header.monthViewItem.currentTitle : "")
				MouseArea {
					anchors.fill: parent
					enabled: !header.navViewItem
					onClicked: header.monthViewItem.titleClicked() // Year / decade view
				}
			}
			Item {
				implicitWidth: Kirigami.Units.smallSpacing
			}
			PlasmaComponents3.ToolButton {
				icon.name: "go-previous"
				onClicked: header.navViewItem ? header.navViewItem.goPrevious() : header.monthViewItem.goPrevious()
				PlasmaComponents3.ToolTip.text: header.weekViewItem ? (header.weekViewItem.singleDay ? i18n("Previous Day") : i18n("Previous Week")) : i18n("Previous Month")
				PlasmaComponents3.ToolTip.visible: hovered
			}
			PlasmaComponents3.ToolButton {
				icon.name: "go-jump-today"
				onClicked: header.navViewItem ? header.navViewItem.goToday() : header.monthViewItem.resetToToday()
				PlasmaComponents3.ToolTip.text: i18n("Today")
				PlasmaComponents3.ToolTip.visible: hovered
			}
			PlasmaComponents3.ToolButton {
				icon.name: "go-next"
				onClicked: header.navViewItem ? header.navViewItem.goNext() : header.monthViewItem.goNext()
				PlasmaComponents3.ToolTip.text: header.weekViewItem ? (header.weekViewItem.singleDay ? i18n("Next Day") : i18n("Next Week")) : i18n("Next Month")
				PlasmaComponents3.ToolTip.visible: hovered
			}
		}

		RowLayout {
			id: rightGroup
			anchors.right: parent.right
			anchors.verticalCenter: parent.verticalCenter
			spacing: 0
			CalendarToggles {
				id: calendarToggles
			}
			PlasmaComponents3.ToolButton {
				icon.name: "search"
				onClicked: header.searchClicked()
				PlasmaComponents3.ToolTip.text: i18n("Search")
				PlasmaComponents3.ToolTip.visible: hovered
			}
			PlasmaComponents3.ToolButton {
				icon.name: "list-add"
				onClicked: header.newEventClicked()
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
					enabled: !header.refreshing
					opacity: header.refreshing ? 0 : 1
					onClicked: header.refreshClicked()
					PlasmaComponents3.ToolTip.text: i18n("Refresh")
					PlasmaComponents3.ToolTip.visible: hovered
				}
				PlasmaComponents3.BusyIndicator {
					anchors.centerIn: parent
					width: refreshButton.icon.width || Kirigami.Units.iconSizes.small
					height: width
					running: header.refreshing
					visible: running
				}
			}
			Kirigami.Separator {
				visible: header.showPinButton
				Layout.fillHeight: true
				Layout.topMargin: Kirigami.Units.smallSpacing
				Layout.bottomMargin: Kirigami.Units.smallSpacing
				Layout.leftMargin: Kirigami.Units.smallSpacing
				Layout.rightMargin: Kirigami.Units.smallSpacing
			}
			// Keeps the popup open for reference.
			PlasmaComponents3.ToolButton {
				visible: header.showPinButton
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
