import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

// Plasma's ComboBox derives its implicit size from its padding and indicator, which loops
// ("Binding loop detected for property implicitWidth") when it fills a layout. Use a fixed width
// hint (the layout stretches it) and the height of a text field, so form rows line up.
PlasmaComponents3.ComboBox {
	implicitWidth: Kirigami.Units.gridUnit * 8
	implicitHeight: heightProbe.implicitHeight

	PlasmaComponents3.TextField {
		id: heightProbe
		visible: false
	}
}
