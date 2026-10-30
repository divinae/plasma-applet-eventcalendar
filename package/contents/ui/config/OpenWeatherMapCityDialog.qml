import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import ".."
import "../lib"
import "../lib/ConfigUtils.js" as ConfigUtils
import "../lib/Requests.js" as Requests

// Settings > Weather > OpenWeatherMap > Find City…: OpenWeatherMap's own search (data/2.5/find), the
// largest places first, with their country and coordinates (one name can be several places).
Dialog {
	id: chooseCityDialog
	title: i18n("Select city")
	standardButtons: Dialog.Ok | Dialog.Cancel
	modal: true

	// Within the settings window, so the buttons stay in sight.
	parent: Overlay.overlay
	anchors.centerIn: parent
	width: Math.min(Kirigami.Units.gridUnit * 30, parent ? parent.width - Kirigami.Units.gridUnit * 2 : 500)
	height: Math.min(Kirigami.Units.gridUnit * 30, parent ? parent.height - Kirigami.Units.gridUnit * 2 : 600)

	property string selectedCityId: ""
	property var configBridge: null
	property bool loadingCityList: false
	property string statusText: "" // An error, or that nothing was found

	Logger {
		id: logger
		showDebug: configBridge ? configBridge.read("debugging", false) : false
	}

	ListModel { id: cityListModel }

	Timer {
		id: debounceSearch
		interval: 600
		onTriggered: chooseCityDialog.searchCityList(cityNameInput.text)
	}

	onOpened: {
		selectedCityId = ""
		cityListView.currentIndex = -1 // A click on the last pick's row picks it again
		cityNameInput.forceActiveFocus()
		cityNameInput.selectAll()
	}
	// OK needs a city.
	onSelectedCityIdChanged: {
		var ok = standardButton(Dialog.Ok)
		if (ok) {
			ok.enabled = !!selectedCityId
		}
	}
	Component.onCompleted: {
		configBridge = ConfigUtils.findBridge(chooseCityDialog)
		var ok = standardButton(Dialog.Ok)
		if (ok) {
			ok.enabled = false
		}
	}

	ColumnLayout {
		anchors.fill: parent
		spacing: Kirigami.Units.smallSpacing

		LinkText {
			Layout.fillWidth: true
			text: i18n("Fetched from <a href=\"%1\">%1</a>", "https://openweathermap.org/find")
		}
		Kirigami.SearchField {
			id: cityNameInput
			Layout.fillWidth: true
			placeholderText: i18n("City name, eg: Berlin or Berlin, DE")
			onTextEdited: debounceSearch.restart()
			onAccepted: {
				debounceSearch.stop()
				chooseCityDialog.searchCityList(text)
			}
			Keys.onDownPressed: {
				cityListView.forceActiveFocus()
				if (cityListView.count > 0) {
					cityListView.currentIndex = 0
				}
			}
		}

		ScrollView {
			Layout.fillWidth: true
			Layout.fillHeight: true
			Component.onCompleted: {
				if (background) {
					background.visible = true // The list's frame
				}
			}

			ListView {
				id: cityListView
				clip: true
				model: cityListModel
				currentIndex: -1
				onCurrentIndexChanged: chooseCityDialog.selectedCityId = currentIndex >= 0 ? String(cityListModel.get(currentIndex).cityId) : ""
				Keys.onReturnPressed: {
					if (chooseCityDialog.selectedCityId) {
						chooseCityDialog.accept()
					}
				}

				delegate: ItemDelegate {
					width: cityListView.width
					highlighted: ListView.isCurrentItem
					onClicked: cityListView.currentIndex = index
					onDoubleClicked: {
						cityListView.currentIndex = index
						chooseCityDialog.accept()
					}
					contentItem: RowLayout {
						spacing: Kirigami.Units.largeSpacing
						ColumnLayout {
							Layout.fillWidth: true
							spacing: 0
							Label {
								Layout.fillWidth: true
								text: model.name
								textFormat: Text.PlainText // From the service: never parsed as HTML
								elide: Text.ElideRight
							}
							Label {
								Layout.fillWidth: true
								text: model.details
								textFormat: Text.PlainText
								elide: Text.ElideRight
								font: Kirigami.Theme.smallFont
								opacity: 0.7
							}
						}
						LinkText {
							text: "<a href=\"https://openweathermap.org/city/" + model.cityId + "\">" + i18n("Open Link") + "</a>"
							linkColor: parent.parent.highlighted ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.highlightColor
						}
					}
				}

				Kirigami.PlaceholderMessage {
					anchors.centerIn: parent
					width: parent.width - Kirigami.Units.gridUnit * 2
					visible: !chooseCityDialog.loadingCityList && cityListView.count === 0 && !!chooseCityDialog.statusText
					text: chooseCityDialog.statusText
				}
				BusyIndicator {
					anchors.centerIn: parent
					running: visible
					visible: chooseCityDialog.loadingCityList
				}
			}
		}
	}

	// "Bingen am Rhein, DE" / "Id 2948825 · 49.97° N, 7.90° E"
	function coordinates(coord) {
		if (!coord || !isFinite(coord.lat) || !isFinite(coord.lon)) {
			return ""
		}
		var lat = Math.abs(coord.lat).toFixed(2) + "° " + (coord.lat >= 0 ? i18nc("north", "N") : i18nc("south", "S"))
		var lon = Math.abs(coord.lon).toFixed(2) + "° " + (coord.lon >= 0 ? i18nc("east", "E") : i18nc("west", "W"))
		return lat + ", " + lon
	}
	function parseCityList(data) {
		var list = data && data.list ? data.list : []
		for (var i = 0; i < list.length; i++) {
			var item = list[i]
			var country = item.sys && item.sys.country ? item.sys.country : ""
			cityListModel.append({
				cityId: item.id,
				name: item.name + (country ? ", " + country : ""),
				details: [i18nc("OpenWeatherMap city id", "Id %1", String(item.id)), coordinates(item.coord)].filter(function(s) { return !!s }).join(" · "),
			})
		}
	}

	property int searchGeneration: 0 // Answers to an older search are dropped.
	function searchCityList(q) {
		q = String(q || "").trim()
		logger.debug("searchCityList", q)
		cityListModel.clear()
		cityListView.currentIndex = -1
		statusText = ""
		var generation = ++searchGeneration
		if (!q) {
			loadingCityList = false
			return
		}
		loadingCityList = true
		fetchCityList({
			appId: configBridge ? configBridge.read("openWeatherMapAppId", "") : "",
			q: q,
		}, function(err, data, xhr) {
			if (generation !== searchGeneration) {
				return
			}
			loadingCityList = false
			if (err) {
				console.log('[eventcalendar] searchCityList.err', err, xhr && xhr.status)
				var body = data
				if (typeof body === "string") {
					try {
						body = JSON.parse(body) // An error's body comes unparsed: { cod, message }
					} catch (e) {
						body = null
					}
				}
				var message = body && body.message ? body.message : String(err)
				statusText = xhr && xhr.status === 401
					? i18n("OpenWeatherMap didn't accept the app id: %1", message)
					: i18n("The search failed: %1", message)
				return
			}
			parseCityList(data)
			if (cityListModel.count === 0) {
				statusText = i18n("No city found.")
			}
		})
	}

	function fetchCityList(args, callback) {
		if (!args.appId) {
			return callback(i18n("No app id set."))
		}
		var url = "https://api.openweathermap.org/data/2.5/"
		url += "find?q=" + encodeURIComponent(args.q)
		url += "&type=like"
		url += "&sort=population"
		url += "&cnt=30"
		url += "&appid=" + encodeURIComponent(args.appId)
		Requests.getJSON(url, callback)
	}
}
