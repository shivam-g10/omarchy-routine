import QtQuick
import Quickshell
import Quickshell.Io
import "Plugin" as Routine
import "Plugin/RoutineLogic.js" as Logic

ShellRoot {
    id: harness

    property string phase: Quickshell.env("ROUTINE_TEST_PHASE")
    property bool started: false
    property bool completed: false
    property var before: null
    property var widths: [2560, 1920, 1280]
    property var sizes: []
    property int widthIndex: 0
    property string reloadStage: ""
    property var repaired: null
    readonly property var geometryRows: makeGeometryRows()

    function makeGeometryRows() {
        var rows = []
        for (var index = 0; index < 24; ++index)
            rows.push({id: "geometry-" + index, start: Logic.formatTime(index * 60), end: "",
                       name: "Geometry activity " + (index + 1) + " with sample text"})
        return Logic.normalize(rows)
    }

    function stepReload() {
        if (phase !== "reload" || completed || service.store.loading) return
        try {
            if (reloadStage === "reading") {
                check(service.store.writable, "The initial explicit reload must finish successfully")
                reloadStage = "corrupting"
                externalWriter.setText('{"broken":')
            } else if (reloadStage === "corrupting" && !service.store.writable) {
                check(service.store.hasValidDocument, "An external parse failure must retain the last valid document")
                check(service.store.error.length > 0, "An external parse failure must report an error")
                check(JSON.stringify(service.store.document) === JSON.stringify(before), "An external parse failure changed the last good document")
                check(service.today.rows.length === before.default.length, "The reference strip must retain the last good routine")
                check(service.store.save(before) === false, "Save must not overwrite an externally corrupted file")
                repaired = Logic.clone(before)
                repaired.default[0].name = "Repaired externally"
                reloadStage = "repairing"
                externalWriter.setText(JSON.stringify(repaired))
            } else if (reloadStage === "repairing" && service.store.writable && !service.store.error) {
                check(service.store.hasValidDocument, "An externally repaired file must become a valid document")
                check(JSON.stringify(service.store.document) === JSON.stringify(repaired), "The repaired external document was not loaded")
                finish(true, {document: service.store.document})
            }
        } catch (error) {
            finish(false, {error: String(error), stage: reloadStage})
        }
    }

    function labelsBelow(item, result) {
        if (item.text !== undefined && item.parent && item.parent.modelData !== undefined)
            result.push(item)
        var children = item.children || []
        for (var index = 0; index < children.length; ++index)
            labelsBelow(children[index], result)
        return result
    }

    function checkGeometry() {
        try {
            // An Item without a visible window does not receive scene-graph
            // polish. Run the positioner's documented layout method explicitly.
            for (var child = 0; child < strip.children.length; ++child) {
                if (typeof strip.children[child].forceLayout === "function")
                    strip.children[child].forceLayout()
            }
            var labels = labelsBelow(strip, [])
            check(labels.length === strip.rows.length, "The strip must create a label for every entry")
            check(labels.length > 0, "The geometry fixture must include a routine")
            var rowPositions = {}
            var rowEnds = {}
            for (var index = 0; index < labels.length; ++index) {
                var label = labels[index]
                var entry = label.parent
                var point = entry.mapToItem(strip, 0, 0)
                check(point.x >= 0 && point.x + entry.width <= strip.width + 1, "An entry extends outside the strip width")
                check(point.y >= 0 && point.y + entry.height <= strip.implicitHeight + 1, "An entry extends outside the strip height")
                check(label.contentWidth <= label.width + 1, "A synthetic geometry entry label is clipped")
                check(rowEnds[String(point.y)] === undefined || point.x >= rowEnds[String(point.y)] - 1,
                      "Routine entries overlap")
                rowPositions[String(point.y)] = true
                rowEnds[String(point.y)] = point.x + entry.width
            }
            check(Object.keys(rowPositions).length > 1, "The synthetic geometry fixture must exercise wrapped rows")
            var next = sizes.slice()
            next.push({width: strip.width, height: strip.implicitHeight, entries: labels.length, rows: Object.keys(rowPositions).length})
            sizes = next
            widthIndex++
            if (widthIndex === widths.length) {
                finish(true, {sizes: sizes})
            } else {
                strip.width = widths[widthIndex]
                geometryDelay.restart()
            }
        } catch (error) {
            finish(false, {error: String(error)})
        }
    }

    function finish(ok, details) {
        if (completed) return
        completed = true
        var result = details || {}
        result.ok = ok
        result.phase = phase
        console.log("ROUTINE_NATIVE_RESULT=" + JSON.stringify(result))
        Qt.quit()
    }

    function check(condition, message) {
        if (!condition) throw new Error(message)
    }

    function begin() {
        if (started || !service.store.ready) return
        started = true
        try {
            check(!service.store.busy, "The store must finish loading before it is ready")
            var status = JSON.parse(service.status())
            check(status.ready, "The service status must reflect the loaded store")
            check(status.dataPath === Quickshell.env("ROUTINE_TEST_DATA"), "The service ignored its isolated data path")
            check(status.entries === service.today.rows.length, "The service status and visible routine differ")
            service.shell = {barConfig: {position: "top"}}
            check(!service.barAtBottom, "The service must follow the host's top bar")
            service.shell = {barConfig: {position: "bottom"}}
            check(service.barAtBottom, "The service must follow the host's bottom bar")
            before = JSON.parse(JSON.stringify(service.store.document))
            if (phase === "geometry") {
                strip.width = widths[0]
                geometryDelay.restart()
            } else if (phase === "defaults") {
                check(service.store.fresh, "A missing file must expose fresh defaults")
                check(service.store.writable, "A missing file must permit the first save")
                check(!service.store.error, "A missing file must not be reported as corrupt")
                finish(true, {document: before})
            } else if (phase === "invalid") {
                check(!service.store.writable, "Malformed input must disable saving")
                check(service.store.error.length > 0, "Malformed input must report a useful error")
                check(service.store.save(before) === false, "Malformed input must never be overwritten by Save")
                finish(true, {error: service.store.error})
            } else if (phase === "read") {
                check(!service.store.fresh, "A saved file must not be treated as a fresh routine")
                check(service.store.writable, "A valid saved file must be writable")
                check(!service.store.error, "A valid saved file must load without an error")
                finish(true, {document: before})
            } else if (phase === "reload") {
                check(service.store.hasValidDocument, "The reload fixture must start from a valid document")
                reloadStage = "reading"
                service.store.reload()
                check(service.store.loading, "An explicit reload must enter loading state before returning")
                check(service.store.save(before) === false, "Save must be rejected while an external reload is in progress")
            } else {
                check(service.store.fresh === (phase !== "migrate"), "The write fixture freshness must match its source")
                check(service.store.writable, "The write fixture must permit saving")
                if (phase === "write") {
                    check(service.store.save({}) === false, "Invalid documents must be rejected before writing")
                }
                check(service.store.save(before) === true, "Saving a valid document must start a write")
            }
        } catch (error) {
            finish(false, {error: String(error)})
        }
    }

    // The real service keeps backend-specific panels lazy. Disabling them
    // leaves the clock, persistence, status, and editor wiring intact.
    Routine.Service {
        id: service
        dataPath: Quickshell.env("ROUTINE_TEST_DATA")
        showPanels: false
    }

    // A second native FileView simulates an independent external writer. Only
    // the temporary test fixture is touched; the store must react via its watcher.
    FileView {
        id: externalWriter
        path: harness.phase === "reload" ? Quickshell.env("ROUTINE_TEST_DATA") : ""
        atomicWrites: true
        blockWrites: false
        printErrors: false
        onSaveFailed: function(reason) { harness.finish(false, {error: "External fixture write failed: " + reason}) }
    }

    Routine.InlineStrip {
        id: strip
        controller: service
        rows: harness.phase === "geometry" ? harness.geometryRows : service.today.rows
        width: 2560
        height: implicitHeight
    }

    Timer {
        id: geometryDelay
        interval: 100
        onTriggered: harness.checkGeometry()
    }

    Connections {
        target: service.store
        function onReadyChanged() { Qt.callLater(harness.begin) }
        function onLoadingChanged() { Qt.callLater(harness.stepReload) }
        function onErrorChanged() { Qt.callLater(harness.stepReload) }
        function onSaved() {
            if (harness.phase !== "write" && harness.phase !== "migrate") {
                harness.finish(false, {error: "An unexpected save completed"})
                return
            }
            try {
                harness.check(!service.store.busy, "The save signal must follow busy-state cleanup")
                harness.check(!service.store.fresh, "A successful save must clear fresh state")
                harness.check(JSON.stringify(service.store.document) === JSON.stringify(harness.before),
                              "The committed document differs from the requested save")
                harness.finish(true, {document: service.store.document})
            } catch (error) {
                harness.finish(false, {error: String(error)})
            }
        }
        function onSaveFailed(message) {
            // Validation failures are synchronous and expected in the write phase.
            if (harness.phase !== "write-failure") return
            try {
                harness.check(!service.store.busy, "A failed write must clear busy state")
                harness.check(message.length > 0, "A failed write must report a useful error")
                harness.check(JSON.stringify(service.store.document) === JSON.stringify(harness.before),
                              "A failed write must preserve the previous document")
                harness.finish(true, {error: message})
            } catch (error) {
                harness.finish(false, {error: String(error)})
            }
        }
    }

    Timer {
        interval: 10000
        running: true
        onTriggered: harness.finish(false, {error: "Timed out waiting for the native store"})
    }

    Component.onCompleted: Qt.callLater(begin)
}
