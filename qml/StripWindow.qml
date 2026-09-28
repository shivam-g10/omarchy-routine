import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

PanelWindow {
    id: root
    required property var controller
    readonly property bool atBottom: controller.barAtBottom
    anchors.left: true
    anchors.right: true
    anchors.top: !atBottom
    anchors.bottom: atBottom
    implicitHeight: strip.implicitHeight
    color: Color.bar.background
    exclusionMode: ExclusionMode.Auto
    WlrLayershell.namespace: "omarchy-routine"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    function status() {
        return {
            loaded: true,
            screen: screen ? screen.name : "",
            width: width,
            height: height
        };
    }

    InlineStrip {
        id: strip
        anchors.fill: parent
        controller: root.controller
    }
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 1
        visible: root.controller.store.error.length > 0
        color: Color.urgent
    }
}
