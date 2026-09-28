import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "RoutineLogic.js" as Logic

// One shared service, one minute clock, and one strip per display.
Item {
    id: root
    property var shell: null
    property string dataPath: Quickshell.env("HOME") + "/.config/omarchy/routines.json"
    property bool showPanels: true
    property bool editorOpen: false
    property bool shuttingDown: false
    property alias store: definitions
    readonly property string barPosition: shell && shell.barConfig
        ? String(shell.barConfig.position || "top") : "bottom"
    readonly property bool barAtBottom: barPosition !== "top"
    readonly property var today: {
        if (!definitions.ready || !definitions.hasValidDocument)
            return { rows: [], activeIndex: -1, label: "Routine unavailable", dateKey: "" };
        try {
            return Logic.resolve(definitions.document, minuteClock.date);
        } catch (exception) {
            return { rows: [], activeIndex: -1, label: String(exception), dateKey: "" };
        }
    }

    function openEditor() {
        if (editorLoader.item) {
            editorLoader.item.activate();
            return;
        }
        editorOpen = true;
    }

    function closeEditor() {
        editorOpen = false;
    }

    function status() {
        return JSON.stringify({
            ready: definitions.ready,
            error: definitions.error,
            saving: definitions.busy,
            loading: definitions.loading,
            dataPath: root.dataPath,
            fresh: definitions.fresh,
            routineDate: today.dateKey,
            scope: today.scope || "",
            entries: today.rows.length,
            activeIndex: today.activeIndex,
            active: today.activeIndex >= 0 ? today.rows[today.activeIndex].name : null,
            editorOpen: editorOpen,
            screens: Quickshell.screens.length,
            panels: panels.instances.map(function(loader) {
                return loader.item ? loader.item.status() : { loaded: false };
            })
        });
    }

    Store {
        id: definitions
        path: root.dataPath
    }
    SystemClock {
        id: minuteClock
        precision: SystemClock.Minutes
    }
    Variants {
        id: panels
        model: root.showPanels && !root.shuttingDown ? Quickshell.screens : []
        delegate: Component {
            Loader {
                required property var modelData
                // Resolve the backend-specific window only for a real display.
                Component.onCompleted: setSource(Qt.resolvedUrl("StripWindow.qml"), {
                    screen: modelData,
                    controller: root
                })
                onStatusChanged: if (status === Loader.Error)
                    console.warn("Routine strip failed to load")
            }
        }
    }
    Loader {
        id: editorLoader
        active: root.editorOpen && !root.shuttingDown
        sourceComponent: Editor {
            controller: root
        }
        onStatusChanged: {
            if (status === Loader.Error) {
                console.warn("Routine editor failed to load");
                root.editorOpen = false;
            }
        }
    }
    IpcHandler {
        target: "omarchy-routine"
        function status(): string { return root.status(); }
        function edit(): void { root.openEditor(); }
        function reload(): void { definitions.reload(); }
    }
    Component.onDestruction: shuttingDown = true
}
