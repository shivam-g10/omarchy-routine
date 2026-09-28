# Native smoke checks

Run from the repository root:

```sh
python tests/native_smoke.py
```

This requires the installed Quickshell `qs` command and the real Omarchy shell
modules at `/usr/share/omarchy/shell`. Use `--shell PATH` for another installed
shell. It does not need a nested compositor or extra Python dependencies.

The harness starts a separate Quickshell process with Qt's offscreen platform,
loads the real `Service.qml` with its backend-specific panels disabled and the
real `InlineStrip.qml`, and tests native `FileView` behavior:

- Service initialization, status output, and host bar-position changes work.
- A missing file exposes defaults without writing until Save is requested.
- Invalid documents are rejected; a valid document is persisted.
- A new process reads the saved document unchanged.
- A legacy version-1 Usual/Weekend document loads as version 2 with Default and
  separate Saturday/Sunday overrides. Reading leaves the original bytes intact;
  an explicit save writes version 2, which another process restores unchanged.
- Save is rejected while a reload is pending. An external malformed write keeps
  the last valid reference visible and blocks saving; an external repair is
  picked up by the file watcher and restores normal operation.
- Malformed existing data remains untouched and cannot be overwritten by Save.
- A filesystem write failure reports an error and preserves the prior document.
- The actual strip component creates all entry labels, fits their bounds, and
  avoids clipping a synthetic 24-activity fixture at widths of 2560, 1920, and
  1280 pixels. Generated labels exercise wrapped rows independently of the three
  generic placeholder activities shipped with the plugin.

Every run uses a temporary home, data directory, runtime directory, and shell
configuration. Desktop display and D-Bus addresses are not inherited. The actual
Omarchy `Commons` and `Ui` modules are loaded from the installed package; user
desktop configuration and routine data are not read or modified. The fixtures
and test processes are removed on exit.

The service lazily resolves its panels, allowing its initialization, minute
clock, store, and status wiring to load under the offscreen platform. Quickshell's
`PanelWindow` type still requires a real backend. These checks therefore do not
establish panel/window integration, compositor placement, exclusive zones,
fullscreen behavior, native keyboard or pointer
interaction, or production resource use. Those need separate validation with a
real Wayland backend.

## Editor checks

Run `python3 tests/editor_smoke.py` for native editor validation. It checks
independent Default, Monday, Tuesday, and specific-date drafts, scoped saving,
cancellation, weekday/date inheritance, conflicting external edits, write
failures, and dirty-close confirmation. Copy from Default is checked for new and
existing overrides, complete replacement, cancellation, and copying the latest
saved Default rather than another draft or a weekday override. A valid
128-activity fixture with 80-character names is checked at the minimum 700×620
window size for Default, Day, and Specific date to keep the preview and Save
button within bounds.

For an offscreen image of the Monday override using a read-only copy of the
current theme:

```sh
python3 tests/editor_smoke.py --theme "$HOME/.local/state/omarchy/current/theme" --image evidence/editor-native.png
```

This exercises component methods and signals; it does not automate physical
pointer or keyboard input. The capture harness adds the window background below
the content because Qt's content-item capture excludes the native window color.
