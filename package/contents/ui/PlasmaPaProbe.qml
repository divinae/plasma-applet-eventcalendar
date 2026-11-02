import QtQml
import org.kde.plasma.private.volume

// Nothing but the import, probed like LayerShellProbe.qml: the camera check's microphone level and
// device choice (MicMeter.qml) use Plasma's audio applet module (plasma-pa), a private API that a
// system may not have or may change. Without it the camera check shows the camera only.
QtObject {
}
