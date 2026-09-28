import QtQuick
import qs.Commons
import qs.Ui as Ui

// Each row is centered on the screen, with matching clearance around the cog.
Item {
    id: root
    required property var controller
    property var rows: controller.today.rows
    property int activeIndex: controller.today.activeIndex
    property int itemsRevision: 0
    readonly property real availableWidth: Math.max(1, width - 2 * (settings.width + Style.space(12)))
    readonly property var arrangement: arrangeEntries()

    function arrangeEntries() {
        itemsRevision;
        var positions = [];
        var line = [];
        var lineWidth = 0;
        var lineHeight = 0;
        var top = Style.space(4);
        function finishLine() {
            var left = (root.width - lineWidth) / 2;
            for (var j = 0; j < line.length; j++) {
                positions[line[j].index] = { x: left, y: top };
                left += line[j].width;
            }
            top += lineHeight;
            line = [];
            lineWidth = 0;
            lineHeight = 0;
        }
        for (var i = 0; i < entries.count; i++) {
            var item = entries.itemAt(i);
            if (!item) continue;
            var itemWidth = Math.min(availableWidth, item.implicitWidth);
            if (line.length && lineWidth + itemWidth > availableWidth)
                finishLine();
            line.push({ index: i, width: itemWidth });
            lineWidth += itemWidth;
            lineHeight = Math.max(lineHeight, item.implicitHeight);
        }
        finishLine();
        return { positions: positions, height: top + Style.space(4) };
    }
    implicitHeight: Math.max(Style.space(30), arrangement.height)

    Repeater {
        id: entries
        model: root.rows
        onItemAdded: root.itemsRevision++
        onItemRemoved: root.itemsRevision++
        delegate: Item {
            id: entry
            required property var modelData
            required property int index
            implicitWidth: label.implicitWidth + Style.space(18)
            implicitHeight: Math.max(Style.space(22), label.implicitHeight + Style.space(6))
            width: Math.min(root.availableWidth, implicitWidth)
            height: implicitHeight
            x: root.arrangement.positions[index] ? root.arrangement.positions[index].x : 0
            y: root.arrangement.positions[index] ? root.arrangement.positions[index].y : Style.space(4)
            Text {
                id: label
                x: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, parent.width - Style.space(16))
                text: entry.modelData.start + " " + entry.modelData.name
                textFormat: Text.PlainText
                color: entry.index === root.activeIndex ? Color.bar.text : Color.muted
                font.family: Style.font.family
                font.pixelSize: Math.max(11, Style.font.bodySmall)
                font.weight: entry.index === root.activeIndex ? Font.DemiBold : Font.Normal
                elide: Text.ElideRight
            }
            Rectangle {
                width: 1
                height: Style.space(12)
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                color: Util.alpha(Color.muted, .35)
                visible: entry.index !== root.rows.length - 1
            }
        }
    }
    Text {
        anchors.centerIn: parent
        width: root.availableWidth
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        visible: root.rows.length === 0
        text: root.controller.store.ready
            ? "Routine unavailable · open settings" : "Loading routine…"
        color: root.controller.store.error ? Color.urgent : Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        textFormat: Text.PlainText
    }
    Ui.Button {
        id: settings
        objectName: "routineSettings"
        anchors.right: parent.right
        anchors.rightMargin: Style.space(4)
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(26)
        height: Style.space(26)
        iconText: "\uf013"
        iconSize: Style.space(14)
        horizontalPadding: 0
        verticalPadding: 0
        foreground: hot ? Color.bar.text : Color.muted
        Accessible.role: Accessible.Button
        Accessible.name: "Edit routine"
        onClicked: root.controller.openEditor()
    }
}
