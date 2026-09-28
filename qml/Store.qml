import QtQuick
import Quickshell.Io
import "RoutineLogic.js" as Logic

// Keep the last confirmed document separate from edits and in-flight writes.
Item {
    id: root
    required property string path
    property var document: Logic.defaults()
    property bool ready: false
    property bool loading: true
    property bool hasValidDocument: false
    property bool busy: false
    property bool fresh: false
    property bool writable: false
    property string error: ""
    property int revision: 0
    property var pending: null
    property bool hadFile: false
    property bool reloadPending: false

    signal saved()
    signal saveFailed(string message)

    function fail(message) {
        error = message;
        saveFailed(message);
        return false;
    }

    function save(value) {
        if (busy)
            return fail("A save is already in progress.");
        if (loading)
            return fail("The routine file is being reloaded. Try Save again when it finishes.");
        if (!ready || !writable)
            return fail(error || "The routine file is not ready.");
        var candidate;
        try {
            candidate = Logic.validateDocument(value);
        } catch (exception) {
            return fail(String(exception).replace(/^Error:\s*/, ""));
        }
        error = "";
        pending = candidate;
        busy = true;
        file.setText(JSON.stringify(candidate, null, 2) + "\n");
        return true;
    }

    function reload() {
        if (busy) {
            reloadPending = true;
            return;
        }
        loading = true;
        file.reload();
    }

    FileView {
        id: file
        path: root.path
        watchChanges: true
        atomicWrites: true
        blockWrites: false
        printErrors: false
        onLoaded: {
            root.loading = false;
            if (root.busy) {
                root.reloadPending = true;
                return;
            }
            try {
                var next = Logic.validateDocument(JSON.parse(text()));
                root.document = next;
                root.hasValidDocument = true;
                root.error = "";
                root.writable = true;
                root.fresh = false;
                root.hadFile = true;
                root.revision++;
            } catch (exception) {
                root.error = "Cannot read routine: " + String(exception).replace(/^Error:\s*/, "")
                    + ". The existing file has been preserved: " + root.path;
                root.writable = false;
            }
            root.ready = true;
        }
        onLoadFailed: function(reason) {
            root.loading = false;
            if (root.busy) {
                root.reloadPending = true;
                return;
            }
            if (reason === FileViewError.FileNotFound && !root.hadFile) {
                root.document = Logic.defaults();
                root.hasValidDocument = true;
                root.fresh = true;
                root.writable = true;
                root.error = "";
            } else {
                root.writable = false;
                root.error = "Cannot read " + root.path + ": " + FileViewError.toString(reason);
            }
            root.ready = true;
        }
        onFileChanged: root.reload()
        onSaved: {
            if (!root.pending)
                return;
            root.document = root.pending;
            root.hasValidDocument = true;
            root.pending = null;
            root.busy = false;
            root.error = "";
            root.fresh = false;
            root.writable = true;
            root.hadFile = true;
            root.revision++;
            root.saved();
            if (root.reloadPending) {
                root.reloadPending = false;
                Qt.callLater(root.reload);
            }
        }
        onSaveFailed: function(reason) {
            root.pending = null;
            root.busy = false;
            root.error = "Could not save routine: " + FileViewError.toString(reason)
                + ". Your edits are still available.";
            root.saveFailed(root.error);
            if (root.reloadPending) {
                root.reloadPending = false;
                Qt.callLater(root.reload);
            }
        }
    }
}
