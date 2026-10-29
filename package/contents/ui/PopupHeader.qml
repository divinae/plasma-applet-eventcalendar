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
	// Week and Day views (their own title and navigation: goPrevious, goNext, goToday), null: the
	// month view.
	property Item weekViewItem
	// 'tabs': a button per view; 'menu': one button with the view shown, the others in its menu
	// (little room taken).
	property string viewSwitcher: 'tabs'
	readonly property bool viewTabsShown: viewSwitcher !== 'menu'
	// The view shown ('month', 'week', 'today', 'classic', 'tasks').
	property string currentMode: plasmoid.configuration.popupMode
	// The Tasks tab (task lists selected).
	property bool showTasksTab: false
	// The Tasks view: no dates to go through, the title is "Tasks".
	property bool tasksMode: false
	property bool showPinButton: true
	property bool refreshing: false

	signal viewSelected(string mode)
	signal newEventClicked()
	signal searchClicked()
	signal refreshClicked()

	// Left: view switcher. Center: navigation and title. Right: calendars, search, new event, refresh, pin.
	contentItem: Item {
		id: topBar
		readonly property real sideWidth: Math.max(leftGroup.implicitWidth, rightGroup.implicitWidth)
		// Title and arrows: centered when they fit between the sides, else in the room between
		// the tabs and the buttons; when not even the arrows and a few letters fit there (a small
		// popup), on a second row. Never under the side buttons.
		readonly property real gap: Kirigami.Units.largeSpacing
		readonly property real centeredRoom: width - sideWidth * 2 - gap * 2
		readonly property real betweenRoom: width - leftGroup.implicitWidth - rightGroup.implicitWidth - gap * 2
		readonly property real navWidth: centerGroup.implicitWidth - titleHeading.Layout.preferredWidth
		readonly property bool secondRow: betweenRoom < navWidth + Kirigami.Units.gridUnit * 3
		// Little room (eg: a 320 px popup): the actions (calendars, search, new, refresh,
		// configure) in one menu button. From fixed widths, not the groups' current ones (those
		// change with this).
		readonly property real buttonWidth: searchButton.implicitWidth
		readonly property int actionCount: 4 + (configureButton.configureAction && configureButton.configureAction.enabled ? 1 : 0)
		readonly property real switcherWidth: header.viewTabsShown ? viewTabs.length * buttonWidth : buttonWidth + Math.round(Kirigami.Units.iconSizes.small * 0.75)
		readonly property bool menuActions: width < switcherWidth + actionCount * buttonWidth
			+ (header.showPinButton ? buttonWidth + Kirigami.Units.smallSpacing * 3 : 0)
			+ navWidth + Kirigami.Units.gridUnit * 6 + gap * 2 // Room for a short title ("October 2026")
		readonly property real rowHeight: Math.max(leftGroup.implicitHeight, rightGroup.implicitHeight, secondRow ? 0 : centerGroup.implicitHeight)
		implicitHeight: rowHeight + (secondRow ? centerGroup.implicitHeight : 0)
		// Not enough room for the view names next to the title: icons only (names in tooltips).
		// Icons only when the tab names don't fit beside a short title (a long one, eg: the Day view's
		// date, is elided first rather than taking the names away).
		readonly property bool compactTabs: header.viewTabsShown
			&& width < Math.max(fullTabsMeasure.implicitWidth, rightGroup.implicitWidth) * 2
				+ Math.min(centerGroup.implicitWidth, Kirigami.Units.gridUnit * 8) + Kirigami.Units.largeSpacing * 2

		readonly property var viewTabs: {
			var tabs = [
				{ mode: 'month', icon: "view-calendar-month", text: i18n("Month") },
				{ mode: 'week', icon: "view-calendar-week", text: i18n("Week") },
				{ mode: 'today', icon: "view-calendar-day", text: i18nc("calendar view showing one day", "Day") },
				{ mode: 'classic', icon: "view-calendar-agenda", text: i18n("Agenda") },
			]
			if (header.showTasksTab) {
				tabs.push({ mode: 'tasks', icon: "view-calendar-tasks", text: i18n("Tasks") })
			}
			// Settings > Views > Tabs: the ones left out. The view shown keeps its tab (the fallback
			// when every offered one is hidden), so the switcher is never empty.
			var hidden = plasmoid.configuration.hiddenViewTabs || []
			return tabs.filter(function(tab) { return hidden.indexOf(tab.mode) < 0 || tab.mode === header.currentMode })
		}
		// The view switcher's width with names, measured off screen.
		// (Not visible: false, a Row leaves out children that aren't visible and measured 0.)
		Row {
			id: fullTabsMeasure
			opacity: 0
			enabled: false
			Accessible.ignored: true
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
			y: Math.round((topBar.rowHeight - height) / 2)
			spacing: 0
			// View switcher: flat buttons with icon and text, the current view on a soft rounded tint.
			RowLayout {
				visible: header.viewTabsShown
				Layout.alignment: Qt.AlignVCenter
				spacing: 2

				Repeater {
					model: topBar.viewTabs
					Item {
						readonly property bool current: header.currentMode === modelData.mode
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
			// View switcher as one button: the view shown (its icon, and its name when there's room)
			// and a small arrow; the views in its menu.
			PlasmaComponents3.ToolButton {
				id: viewMenuButton
				visible: !header.viewTabsShown
				readonly property var current: {
					for (var i = 0; i < topBar.viewTabs.length; i++) {
						if (topBar.viewTabs[i].mode === header.currentMode) {
							return topBar.viewTabs[i]
						}
					}
					return topBar.viewTabs[0]
				}
				icon.name: current.icon
				text: current.text
				display: topBar.compactTabs || topBar.menuActions ? QQC2.AbstractButton.IconOnly : QQC2.AbstractButton.TextBesideIcon
				down: pressed || viewMenu.visible
				rightPadding: leftPadding + viewMenuArrow.width
				onClicked: viewMenu.popup(viewMenuButton, 0, viewMenuButton.height)
				PlasmaComponents3.ToolTip.text: i18n("Views")
				PlasmaComponents3.ToolTip.visible: hovered && !viewMenu.visible
				Accessible.name: i18n("Views")
				Kirigami.Icon {
					id: viewMenuArrow
					anchors.right: parent.right
					anchors.rightMargin: Math.round(parent.leftPadding / 2)
					anchors.verticalCenter: parent.verticalCenter
					width: Math.round(Kirigami.Units.iconSizes.small * 0.75)
					height: width
					source: "arrow-down"
					color: Kirigami.Theme.textColor
					isMask: true
					opacity: 0.7
				}
				PlasmaComponents3.Menu {
					id: viewMenu
					Instantiator {
						model: topBar.viewTabs
						delegate: PlasmaComponents3.MenuItem {
							required property var modelData
							text: modelData.text
							icon.name: modelData.icon
							checkable: true
							checked: header.currentMode === modelData.mode
							onTriggered: header.viewSelected(modelData.mode)
						}
						onObjectAdded: function(index, object) { viewMenu.insertItem(index, object) }
						onObjectRemoved: function(index, object) { viewMenu.removeItem(object) }
					}
				}
			}
		}

		RowLayout {
			id: centerGroup
			readonly property bool centered: topBar.secondRow || implicitWidth <= topBar.centeredRoom
			// Stay clear of the side groups; the title elides if needed.
			width: Math.max(0, Math.min(implicitWidth, topBar.secondRow ? topBar.width : centered ? topBar.centeredRoom : topBar.betweenRoom))
			x: centered ? Math.round((topBar.width - width) / 2) : leftGroup.implicitWidth + topBar.gap
			y: topBar.secondRow ? topBar.rowHeight : Math.round((topBar.rowHeight - height) / 2)
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
				text: header.tasksMode ? i18n("Tasks")
					: header.weekViewItem ? header.weekViewItem.title : (header.monthViewItem ? header.monthViewItem.currentTitle : "")
				MouseArea {
					anchors.fill: parent
					enabled: !header.weekViewItem && !header.tasksMode
					onClicked: header.monthViewItem.titleClicked() // Year / decade view
				}
			}
			Item {
				visible: !header.tasksMode
				implicitWidth: Kirigami.Units.smallSpacing
			}
			PlasmaComponents3.ToolButton {
				visible: !header.tasksMode
				icon.name: "go-previous"
				onClicked: header.weekViewItem ? header.weekViewItem.goPrevious() : header.monthViewItem.goPrevious()
				PlasmaComponents3.ToolTip.text: header.weekViewItem ? (header.weekViewItem.singleDay ? i18n("Previous Day") : i18n("Previous Week")) : i18n("Previous Month")
				PlasmaComponents3.ToolTip.visible: hovered
			}
			PlasmaComponents3.ToolButton {
				visible: !header.tasksMode
				icon.name: "go-jump-today"
				onClicked: header.weekViewItem ? header.weekViewItem.goToday() : header.monthViewItem.resetToToday()
				PlasmaComponents3.ToolTip.text: i18n("Today")
				PlasmaComponents3.ToolTip.visible: hovered
			}
			PlasmaComponents3.ToolButton {
				visible: !header.tasksMode
				icon.name: "go-next"
				onClicked: header.weekViewItem ? header.weekViewItem.goNext() : header.monthViewItem.goNext()
				PlasmaComponents3.ToolTip.text: header.weekViewItem ? (header.weekViewItem.singleDay ? i18n("Next Day") : i18n("Next Week")) : i18n("Next Month")
				PlasmaComponents3.ToolTip.visible: hovered
			}
		}

		RowLayout {
			id: rightGroup
			anchors.right: parent.right
			y: Math.round((topBar.rowHeight - height) / 2)
			spacing: 0
			CalendarToggles {
				id: calendarToggles
				visible: !topBar.menuActions
			}
			PlasmaComponents3.ToolButton {
				id: searchButton
				visible: !topBar.menuActions
				icon.name: "search"
				onClicked: header.searchClicked()
				PlasmaComponents3.ToolTip.text: i18n("Search")
				PlasmaComponents3.ToolTip.visible: hovered
			}
			PlasmaComponents3.ToolButton {
				visible: !topBar.menuActions
				icon.name: "list-add"
				onClicked: header.newEventClicked()
				PlasmaComponents3.ToolTip.text: header.tasksMode ? i18n("New Task") : i18n("New Event")
				PlasmaComponents3.ToolTip.visible: hovered
			}
			Item {
				visible: !topBar.menuActions
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
			// Right clicks in the popup don't open the widget menu, so its "Configure…" is here.
			PlasmaComponents3.ToolButton {
				id: configureButton
				readonly property var configureAction: plasmoid.internalAction("configure")
				visible: !topBar.menuActions && !!configureAction && configureAction.enabled
				icon.name: "configure"
				onClicked: configureAction.trigger()
				PlasmaComponents3.ToolTip.text: configureAction ? configureAction.text : ""
				PlasmaComponents3.ToolTip.visible: hovered
			}
			// The same actions in a menu, when there's little room.
			PlasmaComponents3.ToolButton {
				id: actionsButton
				visible: topBar.menuActions
				icon.name: "overflow-menu"
				down: pressed || actionsMenu.visible
				onClicked: actionsMenu.popup(actionsButton, 0, actionsButton.height)
				PlasmaComponents3.ToolTip.text: i18n("More Actions")
				PlasmaComponents3.ToolTip.visible: hovered && !actionsMenu.visible
				Accessible.name: i18n("More Actions")
				PlasmaComponents3.BusyIndicator {
					anchors.centerIn: parent
					width: Kirigami.Units.iconSizes.small
					height: width
					running: header.refreshing && actionsButton.visible
					visible: running
				}
			}
			PlasmaComponents3.Menu {
				id: actionsMenu
				PlasmaComponents3.MenuItem {
					text: i18n("Calendars")
					icon.name: "view-calendar-list"
					onTriggered: calendarToggles.open(actionsButton)
				}
				PlasmaComponents3.MenuItem {
					text: i18n("Search")
					icon.name: "search"
					onTriggered: header.searchClicked()
				}
				PlasmaComponents3.MenuItem {
					text: header.tasksMode ? i18n("New Task") : i18n("New Event")
					icon.name: "list-add"
					onTriggered: header.newEventClicked()
				}
				PlasmaComponents3.MenuItem {
					text: i18n("Refresh")
					icon.name: "view-refresh"
					enabled: !header.refreshing
					onTriggered: header.refreshClicked()
				}
				PlasmaComponents3.MenuItem {
					visible: configureButton.configureAction && configureButton.configureAction.enabled
					height: visible ? implicitHeight : 0
					text: configureButton.configureAction ? configureButton.configureAction.text : ""
					icon.name: "configure"
					onTriggered: configureButton.configureAction.trigger()
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
