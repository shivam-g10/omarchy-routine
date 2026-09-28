# Omarchy Routine

A daily reference strip for the Omarchy desktop. The current activity uses the
theme's primary text color; the rest stay muted. Each row is centered on the
screen. A settings cog at the far right opens the editor; hovering does not open
a popup. There are no completion checkboxes, accounts, or calendar services.

This is a proof of concept built with QML and embedded JavaScript inside the
existing Omarchy Quickshell process. It shares one minute clock across displays
and creates the editor only when needed. No additional resident
process or backend is required.

## Install

Run inside an existing Omarchy desktop session with its Quickshell shell running:

```sh
git clone https://github.com/shivam-g10/omarchy-routine.git
cd omarchy-routine
./scripts/install-local
```

The plugin ID is `omarchy-routine`. It requires an Omarchy desktop with the
Quickshell shell and its native plugin API; it does not run as a standalone app.

The installer copies the manifest, license, and QML to
`~/.config/omarchy/plugins/omarchy-routine`, validates them, then rescans and enables
the plugin through Omarchy's CLI. It does not restart the shell. Re-run it after
changing the source. Installed QML lives under `qml/<source-hash>/`; the staged
manifest points there so changed builds receive fresh component URLs in the
running shell. The repository manifest stays unchanged.

Before replacement the installer saves the previous plugin, `shell.json`, and
any existing `routines.json` under `~/.local/state/omarchy-routine/backups/` and
prints the private backup directory's path. The routine backup contains the file's
contents even when the original path is a symlink.
If installation fails, it attempts to restore this plugin's code and enabled
state. Configuration and routine snapshots are retained for manual recovery;
automatic recovery does not overwrite shell settings or routine edits made since
the backup.

Disable the strip without deleting the saved routine:

```sh
omarchy plugin disable omarchy-routine
```

## Use

- The strip follows the top or bottom bar position on every display. Narrow
  displays wrap entries into additional rows rather than hiding activities.
- Click the cog at the far right to open the editor. Routine text remains a
  passive reference; it does not open a hover popup.
- **Default** applies every day unless overridden. **Day** provides independent
  Monday through Sunday routines. **Specific date** takes precedence over the
  matching day's routine, which takes precedence over Default.
- An unset day inherits Default. An unset date inherits its matching day's
  routine, if one exists, or Default. Removing an override restores that inherited
  routine when saved.
- Every day and date has **Copy from Default**. It replaces all activities in the
  selected draft with the latest saved Default, including any edits already in
  that draft. It does not merge activities or copy unsaved Default edits. Review
  or edit the copy, then Save to persist the override.
- Enter each activity's start as `HH:MM` in 24-hour format. It lasts until the
  next activity starts; the final activity continues until the next routine's
  first start. A decreasing start time marks the following day, so activities can
  continue after midnight. There is no separate end time to maintain.
- Save affects only the selected scope. Other open drafts remain editable;
  closing with unsaved edits asks before discarding them.

New installations show three generic placeholders: Activity 1, Activity 2, and
Activity 3. Replace their names and start times in the editor. The example is a
starting draft and is not written to disk until Save. No personal schedule is
bundled in the plugin.
Saved routines live in `~/.config/omarchy/routines.json`, separate from plugin code.
Writes use Quickshell's atomic file replacement. The
editor validates start times, ordering, dates, and names before saving and reports read
or write failures. Invalid existing data is not silently replaced with defaults.

Saved files use version 2, with `default`, `days` (keys `mon` through `sun`), and
`dates` (keys `YYYY-MM-DD`). Older version-1 files remain readable: `usual` becomes
Default, and a shared `weekend` becomes independent Saturday and Sunday overrides.
Existing date overrides are preserved. Explicit end values in older files are
ignored; durations are derived from consecutive starts. Loading or installing
does not rewrite an existing routine file. Saving writes the version-2 format.

The routine day starts at its first activity rather than midnight. For example,
Saturday at 01:00 still shows Friday's overnight routine. A dated override belongs
to the date on which that routine starts.

Useful commands:

```sh
omarchy-shell omarchy-routine edit
omarchy-shell omarchy-routine status
omarchy-shell omarchy-routine reload
```

## Check the source

The development checks require Node.js, Python 3, Qt's `qmlformat`, and the already
installed Omarchy and Quickshell tools. They do not install packages.

```sh
./scripts/check
```

GitHub Actions runs the portable checks with `./scripts/check-portable`: model
tests in both time zones, QML parsing, manifest structure, and script syntax.
The complete command above additionally checks native Omarchy integration.

This checks schedule resolution in two time zones, the plugin manifest, QML
parsing, native offscreen persistence and strip geometry, scoped editor behavior,
large-routine layout, and whitespace errors. See [tests/README.md](tests/README.md)
for the native harness's isolation and validation boundaries.

## PoC limits

The strip reserves space beside the native bar and runs inside the same shell
process. See [VALIDATION.md](VALIDATION.md) for reproducible checks and their
validation boundaries.

Physical pointer/keyboard interaction and multiple displays still need manual
validation. The strip uses the same top layer as the native bar and may be hidden
by fullscreen applications. Shared-shell resource samples cannot establish an
exact plugin memory cost. Multiple simultaneous external writers to the JSON file
are unsupported. The editor is a regular native window; the compositor chooses
whether to tile or float it.

The editor supports independent weekday schedules and individual date overrides.
It does not import public holidays, notify about activities, or sync data
elsewhere.

## License

MIT. See [LICENSE](LICENSE).
