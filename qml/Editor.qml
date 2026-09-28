pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import Quickshell
import qs.Commons
import qs.Ui as Ui
import "RoutineLogic.js" as Logic

// The editor is loaded only on demand. Each scope keeps its own draft, and
// only the selected scope is included in a save operation.
FloatingWindow {
    id: editor
    required property var controller
    title: "Edit routine"
    implicitWidth: 880
    implicitHeight: 860
    minimumSize: Qt.size(700, 620)
    color: Color.background
    visible: true

    property bool initialized: false
    property bool closing: false
    property var baselineDocument: null
    property var drafts: ({})
    property string scope: "default"
    property string selectedDay: Logic.dayKey(new Date())
    property string selectedDate: Qt.formatDate(new Date(), "yyyy-MM-dd")
    property string message: ""
    property bool messageIsError: false
    property string pendingKey: ""
    property string pendingSnapshot: ""
    readonly property string scopeKey: selectedScopeKey()
    readonly property var rows: scopeKey && baselineDocument ? rowsForKey(scopeKey) : null
    readonly property bool hasRows: rows !== null
    readonly property bool currentDirty: initialized && scopeKey !== "" && (JSON.stringify(rows) !== JSON.stringify(savedRows(scopeKey, baselineDocument)) || (scopeKey === "default" && controller.store.fresh))
    readonly property var dirtyKeys: changedKeys()
    readonly property bool dirty: dirtyKeys.length > 0
    readonly property string validationError: routineError(rows)
    readonly property string displayError: messageIsError ? message : controller.store.error || validationError
    readonly property var normalizedRows: normalized(rows || [])
    readonly property string inheritedScope: inheritedRoutineScope()
    readonly property string inheritedLabel: scopeName(inheritedScope)
    readonly property var inheritedRows: baselineDocument ? savedRows(inheritedScope, baselineDocument) : []
    readonly property var previewRows: rows !== null ? rows : inheritedRows
    readonly property var previewTimeline: normalized(previewRows)
    readonly property string scopeLabel: scopeName(scopeKey)
    readonly property string saveLabel: scope === "date" ? "Save for this date" : "Save " + scopeLabel

    function selectedScopeKey() {
        if (scope === "default")
            return "default";
        if (scope === "day")
            return Logic.dayKeys().indexOf(selectedDay) >= 0 ? "day:" + selectedDay : "";
        return scope === "date" && validDate(selectedDate) ? "date:" + selectedDate : "";
    }

    function scopeName(key) {
        if (key === "default")
            return "Default";
        if (key.indexOf("day:") === 0)
            return Logic.dayLabel(key.slice(4));
        return key.indexOf("date:") === 0 ? key.slice(5) : "";
    }

    function activate() {
        minimized = false;
        visible = true;
        contentItem.Window.window.requestActivate();
    }

    function validDate(value) {
        return Logic.validateDateKey(value);
    }

    function savedRows(key, document) {
        if (!document || !key)
            return null;
        if (key === "default")
            return document.default;
        if (key.indexOf("day:") === 0)
            return document.days[key.slice(4)] || null;
        return document.dates[key.slice(5)] || null;
    }

    function assignRows(document, key, value) {
        if (key === "default") {
            document.default = value;
            return;
        }
        var collection = key.indexOf("day:") === 0 ? document.days : document.dates;
        var entry = key.slice(key.indexOf(":") + 1);
        if (value === null)
            delete collection[entry];
        else
            collection[entry] = value;
    }

    function rowsForKey(key) {
        return Object.prototype.hasOwnProperty.call(drafts, key) ? drafts[key] : savedRows(key, baselineDocument);
    }

    function changedKeys() {
        if (!initialized)
            return [];
        var result = Object.keys(drafts).filter(function (key) {
            return JSON.stringify(drafts[key]) !== JSON.stringify(savedRows(key, baselineDocument));
        });
        if (controller.store.fresh && result.indexOf("default") < 0)
            result.unshift("default");
        return result;
    }

    function initialize() {
        if (initialized || !controller.store.ready)
            return;
        baselineDocument = Logic.clone(controller.store.document || Logic.defaults());
        initialized = true;
        loadRows();
    }

    function loadRows() {
        rowModel.clear();
        var list = scopeKey && baselineDocument ? rowsForKey(scopeKey) : null;
        if (list !== null) {
            for (var i = 0; i < list.length; ++i) {
                rowModel.append({
                    rowId: list[i].id,
                    start: list[i].start,
                    name: list[i].name
                });
            }
        }
        message = "";
        messageIsError = false;
        rowsView.contentY = 0;
    }

    function setDraft(key, value) {
        var next = Object.assign({}, drafts);
        next[key] = value;
        drafts = next;
        message = "";
        messageIsError = false;
    }

    function captureRows() {
        var list = [];
        for (var i = 0; i < rowModel.count; ++i) {
            var row = rowModel.get(i);
            list.push({id: row.rowId, name: row.name, start: row.start, end: ""});
        }
        setDraft(scopeKey, list);
    }

    function editRow(index, field, value) {
        if (!scopeKey || controller.store.busy || index < 0 || index >= rowModel.count || (field !== "start" && field !== "name"))
            return;
        rowModel.setProperty(index, field, value);
        captureRows();
    }

    function addRow() {
        if (!hasRows || controller.store.busy || rowModel.count >= 128)
            return;
        var last = rowModel.count ? rowModel.get(rowModel.count - 1) : null;
        rowModel.append({
            rowId: "activity-" + Date.now().toString(36) + "-" + Math.random().toString(36).slice(2, 8),
            start: last ? last.start : "09:00",
            name: ""
        });
        captureRows();
        Qt.callLater(function () {
            rowsView.positionViewAtEnd();
            var item = rowsView.itemAtIndex(rowModel.count - 1);
            if (item)
                item.focusName();
        });
    }

    function removeRow(index) {
        rowModel.remove(index);
        captureRows();
    }

    function moveRow(index, offset) {
        var target = index + offset;
        if (target < 0 || target >= rowModel.count)
            return;
        rowModel.move(index, target, 1);
        captureRows();
        rowsView.positionViewAtIndex(target, ListView.Contain);
    }

    function inheritedRoutineScope() {
        if (scope === "date" && validDate(selectedDate) && baselineDocument) {
            var parts = selectedDate.split("-");
            var date = new Date(0);
            date.setHours(12, 0, 0, 0);
            date.setFullYear(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
            var day = Logic.dayKey(date);
            if (Object.prototype.hasOwnProperty.call(baselineDocument.days, day))
                return "day:" + day;
        }
        return "default";
    }

    function copyFromDefault() {
        if (!initialized || !scopeKey || scope === "default" || controller.store.busy || controller.store.loading)
            return;
        // Always replace the entire draft with the latest saved Default.
        // A date's inherited weekday and unrelated drafts are not copy sources.
        setDraft(scopeKey, Logic.clone(controller.store.document.default));
        loadRows();
    }

    function useInherited() {
        if (!scopeKey || scope === "default" || controller.store.busy)
            return;
        setDraft(scopeKey, null);
        loadRows();
    }

    function cancelCurrentEdits() {
        var next = Object.assign({}, drafts);
        delete next[scopeKey];
        drafts = next;
        loadRows();
    }

    function routineError(list) {
        if (!initialized || list === null)
            return "";
        try {
            Logic.validateRoutine(list);
            return "";
        } catch (error) {
            return String(error).replace(/^Error: /, "");
        }
    }

    function saveCurrent() {
        if (!initialized || !scopeKey || !currentDirty || controller.store.busy || controller.store.loading || !controller.store.writable)
            return;
        try {
            var latest = controller.store.document || baselineDocument;
            if (JSON.stringify(savedRows(scopeKey, latest)) !== JSON.stringify(savedRows(scopeKey, baselineDocument)))
                throw Error("This routine changed outside the editor. Reopen the editor before saving.");
            var document = Logic.clone(latest);
            var value = rows === null ? null : Logic.clone(rows);
            assignRows(document, scopeKey, value);
            Logic.validateDocument(document);
            pendingKey = scopeKey;
            pendingSnapshot = JSON.stringify(value);
            message = "";
            messageIsError = false;
            if (!controller.store.save(document)) {
                pendingKey = "";
                pendingSnapshot = "";
                throw Error(controller.store.error || "A file operation is already in progress. Try again.");
            }
        } catch (error) {
            message = String(error).replace(/^Error: /, "");
            messageIsError = true;
        }
    }

    function requestClose() {
        if (controller.store.busy)
            return;
        if (dirty)
            discardDialog.open();
        else {
            closing = true;
            controller.closeEditor();
        }
    }

    function normalized(list) {
        try {
            return Logic.normalize(list);
        } catch (error) {
            // A partially typed row should not prevent further editing.
            return [];
        }
    }

    function nextDayStarts(index) {
        return index > 0 && !!normalizedRows[index] && normalizedRows[index].dayOffset > normalizedRows[index - 1].dayOffset;
    }

    function activeInPreview(index) {
        var entry = previewTimeline[index];
        if (!entry)
            return false;
        var now = 630;
        if (previewTimeline.length && now < previewTimeline[0].startMinute)
            now += 1440;
        var end = entry.endMinute === null ? previewTimeline[0].startMinute + 1440 : entry.endMinute;
        return now >= entry.startMinute && now < end;
    }

    onScopeKeyChanged: if (initialized) loadRows()
    onClosed: {
        if (closing)
            return;
        visible = true;
        requestClose();
    }
    Component.onCompleted: initialize()

    Connections {
        target: controller.store
        function onReadyChanged() { editor.initialize(); }
        function onSaved() {
            if (!editor.pendingKey)
                return;
            var savedKey = editor.pendingKey;
            var next = Object.assign({}, editor.drafts);
            if (JSON.stringify(editor.rowsForKey(savedKey)) === editor.pendingSnapshot)
                delete next[savedKey];
            // Other scopes retain their original baseline so an external edit
            // cannot be silently overwritten by a previously opened draft.
            var baseline = Logic.clone(editor.baselineDocument);
            var value = editor.savedRows(savedKey, editor.controller.store.document);
            editor.assignRows(baseline, savedKey, Logic.clone(value));
            editor.baselineDocument = baseline;
            editor.drafts = next;
            editor.pendingKey = "";
            editor.pendingSnapshot = "";
            if (editor.scopeKey === savedKey)
                editor.loadRows();
            editor.message = "Routine saved";
            editor.messageIsError = false;
        }
        function onSaveFailed(message) {
            editor.pendingKey = "";
            editor.pendingSnapshot = "";
            editor.message = message || "Could not save the routine. Your edits are still here.";
            editor.messageIsError = true;
        }
    }

    ListModel { id: rowModel }

    component Caption: Text {
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        textFormat: Text.PlainText
    }

    Item {
        id: content
        objectName: "routineEditorContent"
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: editor.requestClose()

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 16

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "Edit routine"
                    color: Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.title + 6
                    font.bold: true
                }
                Item { Layout.fillWidth: true }
                Caption {
                    text: controller.store.busy ? "Saving…" : editor.currentDirty ? "Unsaved changes" : editor.hasRows ? editor.scopeLabel : "Uses " + editor.inheritedLabel
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 16
                enabled: editor.initialized && !controller.store.busy
                Ui.Dropdown {
                    Layout.preferredWidth: 250
                    label: "Applies to"
                    value: editor.scope
                    options: [
                        {value: "default", label: "Default"},
                        {value: "day", label: "Day"},
                        {value: "date", label: "Specific date"}
                    ]
                    onChanged: value => editor.scope = value
                }
                Ui.Dropdown {
                    visible: editor.scope === "day"
                    Layout.preferredWidth: 180
                    label: "Day"
                    value: editor.selectedDay
                    options: [
                        {value: "mon", label: "Monday"},
                        {value: "tue", label: "Tuesday"},
                        {value: "wed", label: "Wednesday"},
                        {value: "thu", label: "Thursday"},
                        {value: "fri", label: "Friday"},
                        {value: "sat", label: "Saturday"},
                        {value: "sun", label: "Sunday"}
                    ]
                    onChanged: value => editor.selectedDay = value
                }
                ColumnLayout {
                    visible: editor.scope === "date"
                    spacing: 4
                    Caption { text: "Date · YYYY-MM-DD" }
                    Ui.TextField {
                        id: dateInput
                        Layout.preferredWidth: 160
                        text: editor.selectedDate
                        placeholderText: "YYYY-MM-DD"
                        maximumLength: 10
                        selectByMouse: true
                        Accessible.name: "Date in YYYY-MM-DD format"
                        onTextEdited: editor.selectedDate = text
                    }
                }
                Item { Layout.fillWidth: true }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                visible: editor.scope !== "default"
                enabled: editor.initialized && editor.scopeKey !== "" && !controller.store.busy && !controller.store.loading
                Caption {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: editor.hasRows ? "Copy replaces all activities. Save to apply." : "Uses " + editor.inheritedLabel + ". Copy Default to customize."
                }
                Ui.Button {
                    objectName: "copyFromDefault"
                    text: "Copy from Default"
                    tooltipText: "Replace all activities with saved Default. Save to apply."
                    bordered: true
                    focusable: true
                    onClicked: editor.copyFromDefault()
                }
                Ui.Button {
                    text: "Use " + editor.inheritedLabel
                    tooltipText: "Remove this override after saving"
                    visible: editor.hasRows
                    bordered: true
                    focusable: true
                    onClicked: editor.useInherited()
                }
            }

            Caption {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: "24-hour times · Each activity lasts until the next one starts."
            }

            Ui.BorderSurface {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !editor.hasRows
                color: Util.alpha(Color.foreground, 0.025)
                borderSpec: Border.controlSpec("normal", Color.foreground, Color.accent)
                radius: Style.cornerRadius
                ColumnLayout {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 48, 420)
                    spacing: 12
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: !editor.initialized ? "Loading routine…" : !editor.scopeKey ? "Choose a date" : "Uses " + editor.inheritedLabel
                        color: Color.foreground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.title
                    }
                    Caption {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: !editor.scopeKey ? "Enter a valid date for a holiday or a one-day change." : "Copy from Default above, then adjust the activities for this " + (editor.scope === "day" ? "day." : "date.")
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: editor.hasRows
                enabled: !controller.store.busy
                spacing: 6
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Caption { text: "Start"; Layout.preferredWidth: 84 }
                    Caption { text: "Activity"; Layout.fillWidth: true }
                    Item { Layout.preferredWidth: 112 }
                }
                ListView {
                    id: rowsView
                    objectName: "routineRows"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 6
                    boundsBehavior: Flickable.StopAtBounds
                    model: rowModel
                    Controls.ScrollBar.vertical: Controls.ScrollBar {}
                    delegate: ColumnLayout {
                        id: activityRow
                        required property int index
                        required property string rowId
                        required property string start
                        required property string name
                        width: rowsView.width - 12
                        spacing: 4
                        function focusName() { nameInput.forceActiveFocus(); }
                        Caption {
                            visible: editor.nextDayStarts(activityRow.index)
                            text: "After midnight · next day"
                            Layout.topMargin: visible ? 6 : 0
                            Layout.bottomMargin: visible ? 4 : 0
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Ui.TextField {
                                Layout.preferredWidth: 84
                                text: activityRow.start
                                placeholderText: "HH:MM"
                                maximumLength: 5
                                selectByMouse: true
                                Accessible.name: "Start time for activity " + (activityRow.index + 1)
                                onTextEdited: editor.editRow(activityRow.index, "start", text)
                            }
                            Ui.TextField {
                                id: nameInput
                                Layout.fillWidth: true
                                text: activityRow.name
                                placeholderText: "Activity name"
                                maximumLength: 80
                                selectByMouse: true
                                Accessible.name: "Name for activity " + (activityRow.index + 1)
                                onTextEdited: editor.editRow(activityRow.index, "name", text)
                            }
                            RowLayout {
                                Layout.preferredWidth: 112
                                spacing: 2
                                Ui.Button {
                                    text: "↑"
                                    tooltipText: "Move activity up"
                                    horizontalPadding: 6
                                    focusable: true
                                    enabled: activityRow.index > 0
                                    opacity: enabled ? 1 : 0.3
                                    onClicked: editor.moveRow(activityRow.index, -1)
                                }
                                Ui.Button {
                                    text: "↓"
                                    tooltipText: "Move activity down"
                                    horizontalPadding: 6
                                    focusable: true
                                    enabled: activityRow.index + 1 < rowModel.count
                                    opacity: enabled ? 1 : 0.3
                                    onClicked: editor.moveRow(activityRow.index, 1)
                                }
                                Ui.Button {
                                    text: "×"
                                    tooltipText: "Remove activity"
                                    horizontalPadding: 6
                                    focusable: true
                                    onClicked: editor.removeRow(activityRow.index)
                                }
                            }
                        }
                    }
                }
                Ui.Button {
                    text: "+ Add activity"
                    bordered: true
                    focusable: true
                    enabled: rowModel.count < 128
                    onClicked: editor.addRow()
                }
            }

            Caption {
                Layout.fillWidth: true
                visible: editor.displayError !== "" || editor.message !== ""
                text: editor.displayError || editor.message
                color: editor.displayError !== "" ? Color.urgent : Color.muted
                wrapMode: Text.WordWrap
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Util.alpha(Color.foreground, 0.14)
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
                RowLayout {
                    Layout.fillWidth: true
                    Caption { text: "Inline strip preview · 10:30" }
                    Item { Layout.fillWidth: true }
                    Caption { text: "Wraps to fit this preview" }
                }
                Controls.ScrollView {
                    id: previewScroll
                    objectName: "routinePreview"
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(previewFlow.implicitHeight, Style.space(100))
                    Layout.maximumHeight: Style.space(100)
                    clip: true
                    contentWidth: availableWidth
                    contentHeight: previewFlow.implicitHeight
                    Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff
                    Flow {
                        id: previewFlow
                        objectName: "routinePreviewFlow"
                        width: previewScroll.availableWidth
                        spacing: 0
                        Repeater {
                            model: editor.previewRows
                            delegate: Text {
                                required property var modelData
                                required property int index
                                width: Math.min(implicitWidth, previewFlow.width)
                                text: (index ? "  |  " : "") + (modelData.start || "--:--") + " " + (modelData.name || "Activity")
                                textFormat: Text.PlainText
                                wrapMode: Text.Wrap
                                color: editor.activeInPreview(index) ? Color.foreground : Color.muted
                                font.family: Style.font.family
                                font.pixelSize: Style.font.bodySmall
                                font.bold: editor.activeInPreview(index)
                                bottomPadding: 6
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Util.alpha(Color.foreground, 0.14)
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Caption {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: editor.scope === "default" ? "Used when no day or date override applies." : editor.scope === "day" ? "Every " + Logic.dayLabel(editor.selectedDay) + ", unless a date overrides it." : editor.scopeKey ? "Only " + editor.selectedDate + "." : "Choose a date to customize."
                }
                Ui.Button {
                    text: "Close"
                    bordered: true
                    focusable: true
                    enabled: !controller.store.busy
                    onClicked: editor.requestClose()
                }
                Ui.Button {
                    text: "Cancel edits"
                    tooltipText: "Discard edits to this scope only"
                    bordered: true
                    focusable: true
                    enabled: editor.currentDirty && !controller.store.busy
                    onClicked: editor.cancelCurrentEdits()
                }
                Ui.Button {
                    objectName: "saveRoutine"
                    text: controller.store.busy ? "Saving…" : editor.saveLabel
                    selected: true
                    bordered: true
                    focusable: true
                    enabled: editor.currentDirty && editor.validationError === "" && !controller.store.busy && !controller.store.loading && controller.store.writable
                    onClicked: editor.saveCurrent()
                }
            }
        }

        Controls.Dialog {
            id: discardDialog
            objectName: "discardRoutineDialog"
            anchors.centerIn: parent
            width: 450
            modal: true
            focus: true
            closePolicy: Controls.Popup.CloseOnEscape
            background: Ui.BorderSurface {
                color: Color.popups.background
                radius: Style.cornerRadius
                borderSpec: Border.controlSpec("focus", Color.foreground, Color.accent)
            }
            contentItem: ColumnLayout {
                spacing: 16
                Text {
                    text: "Discard unsaved changes?"
                    color: Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.title
                    font.bold: true
                }
                Caption {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: editor.dirtyKeys.length > 1 ? "You have unsaved edits in " + editor.dirtyKeys.length + " routines. Keep editing to save each routine, or discard all edits and close." : "Keep editing to save your routine, or discard its edits and close."
                }
                RowLayout {
                    Item { Layout.fillWidth: true }
                    Ui.Button {
                        text: "Keep editing"
                        bordered: true
                        focusable: true
                        onClicked: discardDialog.close()
                    }
                    Ui.Button {
                        text: "Discard and close"
                        bordered: true
                        focusable: true
                        foreground: Color.urgent
                        onClicked: {
                            editor.closing = true;
                            discardDialog.close();
                            controller.closeEditor();
                        }
                    }
                }
            }
        }
    }
}
