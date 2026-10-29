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
	// Exclusive: Esc and Return work right away (on demand, only after a click). The alert is up for
	// a moment and goes with either.
	LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityExclusive
}
