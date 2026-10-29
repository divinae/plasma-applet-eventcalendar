import QtQml
import org.kde.layershell as LayerShell

// Nothing but the import. main.qml creates this with Qt.createComponent() and reads the
// component's status: a dynamic creation reports a missing module as an error it can act on,
// where a static import in a file the applet loads takes the whole applet down.
// org.kde.layershell comes from layer-shell-qt, which is not installed everywhere (as in the Fokus
// plasmoid, gitlab #58 there).
QtObject {
}
