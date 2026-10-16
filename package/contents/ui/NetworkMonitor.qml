import QtQuick

QtObject {
	id: networkMonitor

	// https://invent.kde.org/plasma/plasma-nm

	// We need to dynamically import PlasmaNM since it's not preinstalled on every distro (Issue #212)
	readonly property Loader plasmaNMStatusLoader: Loader {
		id: plasmaNMStatusLoader
		source: "NetworkMonitorPlasmaNM.qml"
	}

	// Since the network status state isn't exposed, we need to either parse the icon or user message to know the state.
	// We could compare the icon, however it has a number of network types (wired/wireless) with different wireless strengths
	// like network-wireless-connected-80 for 80% signal. There's a ton of disconnected types too.
	// (network-flightmode-on/network-unavailable/network-wired-available/network-mobile-available)
	// While comparing the i18n messages could be buggy in certain locales, at least we have a simple complete list of states.

	readonly property int connectivity: {
		if (plasmaNMStatusLoader.status === Loader.Ready && plasmaNMStatusLoader.item) {
			return plasmaNMStatusLoader.item.connectivity
		}
		return -1
	}
	readonly property bool isConnected: {
		if (plasmaNMStatusLoader.status === Loader.Error) {
			// Failed to load PlasmaNM, so treat it as connected.
			return true
		}
		if (connectivity < 0) {
			return true
		}
		// NetworkManager::Connectivity::NoConnectivity == 1
		return connectivity !== 1
	}

	onIsConnectedChanged: logger.debug('NetworkMonitor.isConnected', isConnected)
	Component.onCompleted: {
		logger.debug('NetworkMonitor.isConnected', isConnected)
	}
}
