import org.kde.layershell as LayerShell

// MeetingAlertWindow as a layer surface: above panels and normal windows, on every virtual desktop
// (a Wayland client can't ask to be on all of them, a layer surface isn't on one). In a file of its
// own so the optional module is only imported once it's known to be there (LayerShellProbe.qml).
MeetingAlertWindow {
	LayerShell.Window.layer: LayerShell.Window.LayerOverlay
	// All four edges: the whole output rather than a size of its own (the output: the window's screen).
	LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
	// -1: other surfaces' exclusive zones (a panel) don't shorten it.
	LayerShell.Window.exclusionZone: -1
	// On demand: the keyboard when clicked (Esc, Return), without taking every key on the machine.
	LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityOnDemand
}
