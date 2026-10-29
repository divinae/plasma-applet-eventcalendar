import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "Shared.js" as Shared
import "Tasks.js" as Tasks

// The Day view's "Up next" (left column, under the small month): a few events after the shown day
// (at most limit, from the next days days), by day
// ("Tomorrow", "Thu 29 Oct"), each with its color bar, time and title (Shared.upcomingEvents;
// eventModel.eventsData, so declined or hidden ones are left out as everywhere; tasks left out). A
// click shows that day (dayRequested), a right click the event menu. Scrolls when long.
ColumnLayout {
	id: upNext

	property var eventModel: null
	// Events from this time on (the day after the one shown).
	property date after: new Date()
	property date today: new Date()
	// Kept short: a glance at what's next, not a second agenda; expanded ("Show more"): more of
	// the week, the list scrolls.
	property int limit: 5
	property int days: 3
	property bool expanded: false
	// Fills the height it's given (the Day view's left column): the events of the next two weeks,
	// as many as fit, the list at the top.
	property bool fill: false
	readonly property int shownLimit: expanded ? Math.max(15, collapsedLimit * 2) : collapsedLimit
	readonly property int shownDays: expanded ? Math.max(7, collapsedDays * 2) : collapsedDays
	readonly property int collapsedLimit: fill ? 50 : limit
	readonly property int collapsedDays: fill ? 14 : days
	// The height it may take (0: no limit): only the events that fit whole are listed.
	property real maxHeight: 0
	readonly property real titleHeight: titleMetrics.height * 1.25 + spacing
	readonly property real dayHeight: titleMetrics.height + Kirigami.Units.smallSpacing + 2
	readonly property real eventHeight: titleMetrics.height + 6 + 2
	FontMetrics {
		id: titleMetrics
		font: Kirigami.Theme.defaultFont
	}

	signal dayRequested(date day)

	readonly property var entries: {
		var items = eventModel && eventModel.eventsData ? Tasks.withoutTasks(eventModel.eventsData.items) : []
		var until = Shared.addDays(Shared.startOfDay(after), shownDays).getTime()
		var list = Shared.upcomingEvents(items, after, shownLimit).filter(function(entry) {
			return entry.day.getTime() < until
		})
		if (maxHeight <= 0 || expanded) {
			return list
		}
		// As many as fit, with their days' headings.
		var used = titleHeight + Kirigami.Units.smallSpacing * 2
		var lastKey = null
		var fit = []
		for (var i = 0; i < list.length; i++) {
			var key = Shared.dayKey(list[i].day)
			var add = eventHeight + (key !== lastKey ? dayHeight : 0)
			if (used + add > maxHeight) {
				break
			}
			used += add
			lastKey = key
			fit.push(list[i])
		}
		return fit
	}
	// More than shown (collapsed): "Show more" is offered.
	readonly property bool hasMore: {
		if (expanded) {
			return true
		}
		var items = eventModel && eventModel.eventsData ? Tasks.withoutTasks(eventModel.eventsData.items) : []
		var until = Shared.addDays(Shared.startOfDay(after), Math.max(7, collapsedDays * 2)).getTime()
		return Shared.upcomingEvents(items, after, entries.length + 1).filter(function(entry) {
			return entry.day.getTime() < until
		}).length > entries.length
	}
	// The entries with a heading row before each day's first: [{ type: 'day' | 'event', … }].
	readonly property var rows: {
		var out = []
		var lastKey = null
		entries.forEach(function(entry) {
			var key = Shared.dayKey(entry.day)
			if (key !== lastKey) {
				out.push({ type: 'day', day: entry.day })
				lastKey = key
			}
			out.push({ type: 'event', item: entry.item, day: entry.day })
		})
		return out
	}
	function dayTitle(day) {
		var start = Shared.startOfDay(today)
		if (Shared.isSameDate(day, start)) {
			return i18nc("tasks filter", "Today")
		}
		if (Shared.isSameDate(day, Shared.addDays(start, 1))) {
			return i18nc("tasks filter", "Tomorrow")
		}
		return Shared.formatDate(day, i18nc("Up next: a day's heading", "dddd, d MMM"))
	}

	spacing: Kirigami.Units.smallSpacing

	// Like the other side cards' titles ("Weather", "Tasks").
	PlasmaComponents3.Label {
		Layout.fillWidth: true
		text: i18n("Up next")
		textFormat: Text.PlainText
		font.weight: Font.Bold
		font.pointSize: appletConfig.fontPoints(Kirigami.Theme.defaultFont) * 1.25
		elide: Text.ElideRight
	}

	PlasmaComponents3.Label {
		visible: upNext.entries.length === 0
		Layout.fillWidth: true
		text: i18n("Nothing planned in the coming days.")
		textFormat: Text.PlainText
		wrapMode: Text.Wrap
		opacity: 0.75
	}

	PlasmaComponents3.ScrollView {
		id: scrollView
		visible: upNext.entries.length > 0
		Layout.fillWidth: true
		// As tall as its rows (expanded: at most the room there is, then it scrolls).
		Layout.preferredHeight: upNext.expanded && upNext.maxHeight > 0
			? Math.min(rowsColumn.implicitHeight, upNext.maxHeight - upNext.titleHeight - moreToggle.implicitHeight - Kirigami.Units.smallSpacing * 3)
			: rowsColumn.implicitHeight
		Layout.maximumHeight: Layout.preferredHeight
		Layout.fillHeight: true
		contentWidth: availableWidth
		QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff
		QQC2.ScrollBar.vertical: OverlayScrollBar {
			view: scrollView
		}

		ColumnLayout {
			id: rowsColumn
			width: scrollView.availableWidth
			spacing: 2
			Repeater {
				model: upNext.rows
				Loader {
					readonly property var row: modelData
					readonly property bool firstRow: index === 0
					Layout.fillWidth: true
					sourceComponent: modelData.type === 'day' ? dayComponent : eventComponent
				}
			}
		}
	}

	// "Show more" / "Show less", like the tasks' "N completed": a small arrow and text.
	QQC2.AbstractButton {
		id: moreToggle
		visible: upNext.hasMore
		Layout.fillWidth: true
		hoverEnabled: true
		topPadding: 2
		bottomPadding: 2
		text: upNext.expanded ? i18n("Show less") : i18n("Show more")
		Accessible.name: text
		onClicked: upNext.expanded = !upNext.expanded
		background: Rectangle {
			radius: 4
			color: moreToggle.hovered ? appletConfig.agendaHoverBackground : "transparent"
		}
		contentItem: RowLayout {
			spacing: Kirigami.Units.smallSpacing
			Kirigami.Icon {
				Layout.alignment: Qt.AlignVCenter
				Layout.topMargin: Math.round((moreMetrics.ascent - moreMetrics.descent - moreMetrics.xHeight))
				implicitWidth: Math.round(Kirigami.Units.iconSizes.small * 0.75)
				implicitHeight: implicitWidth
				source: upNext.expanded ? "arrow-up" : "arrow-down"
				color: Kirigami.Theme.textColor
				isMask: true
				opacity: 0.7
			}
			FontMetrics {
				id: moreMetrics
				font: moreLabel.font
			}
			PlasmaComponents3.Label {
				id: moreLabel
				Layout.fillWidth: true
				text: moreToggle.text
				textFormat: Text.PlainText
				font: Kirigami.Theme.smallFont
				opacity: 0.75
			}
		}
	}

	// Filling: the room left below the list.
	Item {
		visible: upNext.fill
		Layout.fillHeight: true
	}

	Component {
		id: dayComponent
		PlasmaComponents3.Label {
			readonly property var row: parent ? parent.row : null
			topPadding: parent && parent.firstRow ? 0 : Kirigami.Units.smallSpacing
			text: row ? upNext.dayTitle(row.day) : ""
			textFormat: Text.PlainText
			font.weight: Font.DemiBold
			opacity: 0.8
			elide: Text.ElideRight
		}
	}

	// An event: its color bar, time ("All day") and title; click: its day; right click: its menu.
	Component {
		id: eventComponent
		LinkRect {
			id: eventRow
			readonly property var row: parent ? parent.row : null
			readonly property var item: row ? row.item : null
			readonly property bool allDay: !!(item && item.start && item.start.date)
			implicitHeight: eventContent.implicitHeight + 6
			radius: 4
			backgroundColor: "transparent"
			onLeftClicked: upNext.dayRequested(row.day)
			onClicked: function(mouse) {
				if (mouse.button === Qt.RightButton && typeof popup !== "undefined" && popup) {
					mouse.accepted = true
					popup.showEventMenu(eventRow.item, eventRow, mouse.x, mouse.y)
				}
			}
			RowLayout {
				id: eventContent
				anchors.left: parent.left
				anchors.right: parent.right
				anchors.verticalCenter: parent.verticalCenter
				anchors.leftMargin: 2
				anchors.rightMargin: 2
				spacing: Kirigami.Units.smallSpacing
				Rectangle {
					Layout.fillHeight: true
					Layout.preferredWidth: 3
					radius: 1.5
					color: appletConfig.eventBarColor(appletConfig.eventColor(eventRow.item ? eventRow.item.backgroundColor : null))
				}
				PlasmaComponents3.Label {
					Layout.preferredWidth: Kirigami.Units.gridUnit * 3
					text: !eventRow.item ? "" : eventRow.allDay ? i18n("All day") : Shared.formatTime(eventRow.item.startDateTime, appletConfig.timeFormat)
					textFormat: Text.PlainText
					font: Kirigami.Theme.smallFont
					opacity: 0.75
					elide: Text.ElideRight
				}
				PlasmaComponents3.Label {
					Layout.fillWidth: true
					Layout.minimumWidth: 0
					text: eventRow.item ? eventRow.item.summary || "" : ""
					textFormat: Text.PlainText // User text: never parsed as HTML
					elide: Text.ElideRight
				}
			}
		}
	}
}
