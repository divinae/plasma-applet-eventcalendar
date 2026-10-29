import org.kde.layershell as LayerShell

// MeetingAlertBlur as a layer surface (above panels, on every desktop): see MeetingAlertLayer.qml.
MeetingAlertBlur {
	LayerShell.Window.layer: LayerShell.Window.LayerOverlay
	LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
	LayerShell.Window.exclusionZone: -1
	LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityOnDemand
}
