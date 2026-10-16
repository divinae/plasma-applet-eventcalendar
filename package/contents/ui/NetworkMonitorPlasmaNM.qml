import QtQuick
import org.kde.plasma.networkmanagement as PlasmaNM

PlasmaNM.NetworkStatus {
	id: plasmaNMStatus
	function onConnectivityChanged(connectivity) {
		logger.debug('NetworkStatus.connectivity', connectivity)
	}
	Component.onCompleted: {
		logger.debug('NetworkStatus.connectivity', connectivity)
	}
}
