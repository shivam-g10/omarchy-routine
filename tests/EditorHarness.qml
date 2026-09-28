import QtQuick
import Quickshell
import qs.Commons
import "Plugin" as Routine
import "Plugin/RoutineLogic.js" as Logic

ShellRoot {
    id: harness
    property string phase: Quickshell.env("ROUTINE_TEST_PHASE")
    property int stage: 0
    property bool finished: false
    property int closeRequests: 0
    property var checks: []
    property string originalName: ""
    property int originalRowCount: 0

    function check(condition, message) {
        if (!condition) throw new Error(message)
        checks = checks.concat([message])
    }
    function finish(ok, error) {
        if (finished) return
        finished = true
        console.log("ROUTINE_NATIVE_RESULT=" + JSON.stringify({ok: ok, phase: phase, checks: checks, error: error || ""}))
        Qt.quit()
    }
    function control(name, item) {
        if (item.objectName === name) return item
        var children = item.children || []
        for (var index = 0; index < children.length; ++index) {
            var result = control(name, children[index])
            if (result) return result
        }
        return null
    }
    function checkMinimumActions(editor, scopeName) {
        var preview = control("routinePreview", editor.contentItem)
        var rows = control("routineRows", editor.contentItem)
        var save = control("saveRoutine", editor.contentItem)
        var copy = control("copyFromDefault", editor.contentItem)
        var copyPoint = copy.mapToItem(editor.contentItem, 0, 0)
        check(copy.visible && copy.enabled && copyPoint.x >= 0 && copyPoint.x + copy.width <= editor.contentItem.width + 1
              && copyPoint.y >= 0 && copyPoint.y + copy.height <= editor.contentItem.height + 1,
              scopeName + " Copy from Default remains available inside the minimum-size window")
        check(preview.height <= Style.space(100) + 1, scopeName + " preview remains capped at the minimum window size")
        check(rows.height >= 60, scopeName + " rows retain usable height at the minimum window size")
        var point = save.mapToItem(editor.contentItem, 0, 0)
        check(point.y >= 0 && point.y + save.height <= editor.contentItem.height + 1,
              scopeName + " Save remains inside the minimum-size window")
    }
    function next() {
        if (!editorLoader.item || !editorLoader.item.initialized || store.loading || store.busy) {
            delay.restart()
            return
        }
        var editor = editorLoader.item
        try {
            if (stage === 0) {
                check(editor.rows.length === 3, "Editor loads the three generic placeholder activities")
                originalName = editor.rows[0].name
                originalRowCount = editor.rows.length
                check(editor.currentDirty, "Fresh defaults can be saved")
                check(editor.validationError === "", "Default routine validates")
                check(control("saveRoutine", editor.contentItem).enabled, "Initial save button is enabled")
                stage = 1
                editor.saveCurrent()
            } else if (stage === 1) {
                check(editor.message === "Routine saved", "Successful save is acknowledged")
                check(!editor.currentDirty, "Successful save clears the selected draft")
                editor.editRow(0, "name", "Unsaved Default name")
                check(editor.currentDirty, "Editing creates a Default draft")
                editor.scope = "day"
                editor.selectedDay = "mon"
                check(!editor.hasRows, "Monday initially inherits Default")
                editor.copyFromDefault()
                check(editor.rows[0].name === originalName, "Monday copies saved Default instead of an unsaved draft")
                editor.editRow(0, "name", "Monday activity")
                stage = 2
                editor.saveCurrent()
            } else if (stage === 2) {
                check(store.document.days.mon[0].name === "Monday activity", "Monday save persists its scope")
                check(store.document.default[0].name === originalName, "Monday save does not persist a Default draft")
                editor.addRow()
                editor.editRow(editor.rows.length - 1, "name", "Extra Monday activity")
                check(editor.rows.length === originalRowCount + 1, "An existing day override can add rows before copying")
                editor.copyFromDefault()
                check(JSON.stringify(editor.rows) === JSON.stringify(store.document.default), "Copy from Default replaces every row and value in an existing day override")
                editor.cancelCurrentEdits()
                check(editor.rows.length === originalRowCount && editor.rows[0].name === "Monday activity", "Cancelling a day copy restores its saved override")
                editor.editRow(0, "name", "Monday draft")
                editor.selectedDay = "tue"
                check(!editor.hasRows, "Tuesday has an independent inherited scope")
                editor.copyFromDefault()
                editor.editRow(0, "name", "Tuesday activity")
                stage = 3
                editor.saveCurrent()
            } else if (stage === 3) {
                check(store.document.days.tue[0].name === "Tuesday activity", "Tuesday save persists its scope")
                check(store.document.days.mon[0].name === "Monday activity", "Tuesday save does not persist a Monday draft")
                editor.selectedDay = "mon"
                check(editor.rows[0].name === "Monday draft", "Switching weekdays preserves their independent drafts")
                stage = 4
                editor.saveCurrent()
            } else if (stage === 4) {
                check(store.document.days.mon[0].name === "Monday draft", "Monday draft saves independently")
                editor.scope = "default"
                check(editor.rows[0].name === "Unsaved Default name", "Saving weekday scopes preserves the Default draft")
                editor.cancelCurrentEdits()
                check(editor.rows[0].name === originalName && !editor.currentDirty, "Cancel restores the selected scope")
                editor.editRow(2, "start", "15:00")
                check(editor.validationError === "", "Moving the next start earlier does not create a stale end-time conflict")
                check(editor.normalizedRows[1].endMinute === 900, "Editing a start updates the preceding activity duration")
                editor.cancelCurrentEdits()
                editor.editRow(0, "start", "invalid")
                check(editor.validationError !== "", "Invalid input receives a useful error")
                check(!control("saveRoutine", editor.contentItem).enabled, "Invalid input disables Save")
                editor.cancelCurrentEdits()
                editor.addRow()
                check(editor.rows.length === originalRowCount + 1, "Add activity creates an editable row")
                editor.removeRow(editor.rows.length - 1)
                check(editor.rows.length === originalRowCount, "Remove activity restores the routine")
                editor.moveRow(0, 1)
                check(editor.rows[1].name === originalName, "Move activity changes draft order")
                editor.cancelCurrentEdits()
                editor.scope = "date"
                editor.selectedDate = "2026-02-30"
                check(editor.scopeKey === "", "Impossible calendar dates are rejected")
                editor.copyFromDefault()
                check(!editor.hasRows, "Invalid dates cannot create an override")
                editor.selectedDate = "0099-09-28"
                check(editor.inheritedScope === "day:mon", "Date inheritance preserves four-digit years below 0100")
                editor.selectedDate = "2026-12-28"
                check(editor.previewRows[0].name === "Monday draft", "An unconfigured Monday date previews the saved Monday override")
                editor.copyFromDefault()
                check(JSON.stringify(editor.rows) === JSON.stringify(store.document.default), "Specific-date copy always uses Default even when that weekday has an override")
                editor.editRow(0, "name", "Date activity")
                stage = 5
                editor.saveCurrent()
            } else if (stage === 5) {
                check(store.document.dates["2026-12-28"][0].name === "Date activity", "Specific-date save persists its override")
                editor.addRow()
                editor.editRow(editor.rows.length - 1, "name", "Extra date activity")
                editor.copyFromDefault()
                check(JSON.stringify(editor.rows) === JSON.stringify(store.document.default), "Copy from Default replaces every row and value in an existing date override")
                editor.cancelCurrentEdits()
                check(editor.rows.length === originalRowCount && editor.rows[0].name === "Date activity", "Cancelling a date copy restores its saved override")
                editor.useInherited()
                check(!editor.hasRows && editor.currentDirty, "Use inherited routine stages removal of an override")
                check(editor.previewRows[0].name === "Monday draft", "Removing a date override previews the saved weekday routine")
                stage = 6
                editor.saveCurrent()
            } else if (stage === 6) {
                check(Object.keys(store.document.dates).length === 0, "Saving inherited routine removes the date override")
                editor.scope = "day"
                editor.selectedDay = "tue"
                editor.useInherited()
                stage = 7
                editor.saveCurrent()
            } else if (stage === 7) {
                check(!Object.prototype.hasOwnProperty.call(store.document.days, "tue"), "Saving Use Default removes only the Tuesday override")
                check(store.document.days.mon[0].name === "Monday draft", "Removing Tuesday preserves the Monday override")
                editor.scope = "default"
                editor.editRow(0, "name", "Pending draft")
                var external = Logic.clone(store.document)
                external.default[0].name = "External change"
                stage = 8
                check(store.save(external), "External fixture save starts")
            } else if (stage === 8) {
                editor.scope = "day"
                editor.selectedDay = "wed"
                editor.copyFromDefault()
                check(editor.rows[0].name === "External change", "Copy from Default reads its latest saved values while the editor stays open")
                editor.cancelCurrentEdits()
                editor.scope = "default"
                editor.saveCurrent()
                check(editor.messageIsError && editor.message.indexOf("changed outside") >= 0, "Editor blocks overwriting a changed scope")
                check(editor.rows[0].name === "Pending draft", "Conflict preserves the draft")
                editor.requestClose()
                check(closeRequests === 0, "Closing with drafts requires confirmation")
                editorLoader.active = false
                stage = 9
                delay.restart()
            } else if (stage === 9) {
                check(editor.rows[0].name === "External change", "Reopening loads the latest saved routine")
                check(!editor.currentDirty, "Reopened saved routine is clean")
                var manyRows = []
                for (var row = 0; row < 128; ++row)
                    manyRows.push({id: "large-" + row, start: Logic.formatTime(480 + row), end: "", name: "界".repeat(80)})
                editor.setDraft("default", manyRows)
                editor.loadRows()
                check(editor.validationError === "", "The 128-row, 80-character-name fixture is valid")
                editor.implicitWidth = 700
                editor.implicitHeight = 620
                stage = 10
                delay.restart()
            } else if (stage === 10) {
                var preview = control("routinePreview", editor.contentItem)
                var previewFlow = control("routinePreviewFlow", editor.contentItem)
                var save = control("saveRoutine", editor.contentItem)
                var rows = control("routineRows", editor.contentItem)
                check(editor.contentItem.width === 700 && editor.contentItem.height === 620, "Geometry is checked at the 700 by 620 minimum window size")
                check(preview.height <= Style.space(100) + 1, "Large-routine preview height remains capped")
                check(preview.contentHeight > preview.height, "Large-routine preview can scroll vertically")
                check(rows.height >= 60, "Editing rows retain usable height at the minimum window size")
                var savePosition = save.mapToItem(editor.contentItem, 0, 0)
                check(savePosition.y >= 0 && savePosition.y + save.height <= editor.contentItem.height + 1, "Save remains inside the minimum-size window")
                var count = 0
                var labelsFit = true
                for (var child = 0; child < previewFlow.children.length; ++child) {
                    var label = previewFlow.children[child]
                    if (label.text === undefined) continue
                    labelsFit = labelsFit && label.x >= 0 && label.x + label.width <= previewFlow.width + 1 && label.contentWidth <= label.width + 1
                    count++
                }
                check(labelsFit, "All maximum-length preview names wrap within the content width")
                check(count === 128, "Large-routine preview retains every entry")
                var dayRows = Logic.clone(editor.rows)
                editor.cancelCurrentEdits()
                editor.scope = "day"
                editor.selectedDay = "thu"
                editor.setDraft(editor.scopeKey, dayRows)
                editor.loadRows()
                stage = 11
                delay.restart()
            } else if (stage === 11) {
                checkMinimumActions(editor, "Day")
                var dateRows = Logic.clone(editor.rows)
                editor.cancelCurrentEdits()
                editor.scope = "date"
                editor.selectedDate = "2026-12-28"
                editor.setDraft(editor.scopeKey, dateRows)
                editor.loadRows()
                stage = 12
                delay.restart()
            } else if (stage === 12) {
                checkMinimumActions(editor, "Specific date")
                editor.cancelCurrentEdits()
                editor.scope = "default"
                editor.implicitWidth = 880
                editor.implicitHeight = 860
                if (Quickshell.env("ROUTINE_TEST_IMAGE")) {
                    editor.scope = "day"
                    editor.selectedDay = "mon"
                    stage = 13
                    renderDelay.restart()
                } else {
                    editor.requestClose()
                    check(closeRequests === 1, "Clean close completes immediately")
                    finish(true)
                }
            }
        } catch (error) {
            finish(false, String(error))
        }
    }

    Item {
        id: harnessController
        property alias store: store
        function closeEditor() { harness.closeRequests++ }
    }
    Routine.Store {
        id: store
        path: Quickshell.env("ROUTINE_TEST_DATA")
    }
    Loader {
        id: editorLoader
        active: true
        sourceComponent: Routine.Editor { controller: harnessController }
    }
    Connections {
        target: store
        function onReadyChanged() { delay.restart() }
        function onSaved() { delay.restart() }
        function onSaveFailed(message) {
            if (harness.phase === "editor-write-failure") {
                Qt.callLater(function () {
                    try {
                        var editor = editorLoader.item
                        harness.check(editor.currentDirty, "Failed save keeps the draft")
                        harness.check(editor.messageIsError && editor.message.length > 0, "Failed save surfaces its error")
                        harness.check(editor.pendingKey === "", "Failed save clears the pending operation")
                        harness.finish(true)
                    } catch (error) { harness.finish(false, String(error)) }
                })
            } else harness.finish(false, message)
        }
    }
    Timer {
        id: delay
        interval: 80
        onTriggered: {
            if (harness.stage === 9 && !editorLoader.active) editorLoader.active = true
            harness.next()
        }
    }
    Component {
        id: captureBackground
        Rectangle { anchors.fill: parent; z: -1 }
    }
    Timer {
        id: renderDelay
        interval: 400
        onTriggered: {
            var content = harness.control("routineEditorContent", editorLoader.item.contentItem)
            // grabToImage captures the item subtree, excluding the FloatingWindow
            // background. Add the same color beneath the content for this capture.
            var background = captureBackground.createObject(content, {color: editorLoader.item.color})
            content.grabToImage(function (result) {
                try {
                    harness.check(result.saveToFile(Quickshell.env("ROUTINE_TEST_IMAGE")), "Editor renders a native screenshot")
                    background.destroy()
                    editorLoader.item.cancelCurrentEdits()
                    editorLoader.item.requestClose()
                    harness.check(harness.closeRequests === 1, "Clean close completes immediately")
                    harness.finish(true)
                } catch (error) { harness.finish(false, String(error)) }
            })
        }
    }
    Timer {
        interval: 10000
        running: true
        onTriggered: harness.finish(false, "Editor native test timed out at stage " + stage)
    }
    Component.onCompleted: delay.restart()
}
