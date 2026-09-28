# Validation

Run `./scripts/check` inside an Omarchy session with Node.js, Python 3, Qt's
`qmlformat`, and Quickshell installed. Native checks use private temporary
directories and synthetic schedules; they do not load or alter desktop routine
data. Run as a normal user so permission-denied write checks remain meaningful.

## Coverage

- Schedule resolution in Asia/Kolkata and America/New_York: exact activity
  boundaries, equal starts, overnight ownership, clock changes, weekday/date
  priority, schema validation, and version-1 migration.
- Real QML service/store components offscreen: first launch, atomic save,
  process restart, external reload, corruption recovery, and write failures.
  Legacy data remains unchanged on read and migrates only during explicit Save.
- Real QML editor components offscreen: scoped drafts, independent weekday saves,
  Copy from Default replacing the entire day/date draft, cancel, inheritance,
  external-edit conflicts, validation, and unsaved-change handling.
- Synthetic strip layouts at multiple widths and editor layouts at the minimum
  700×620 size, including 128 activities and long names.
- Native manifest validation, QML parsing, and whitespace checks.

GitHub Actions runs `./scripts/check-portable`: schedule tests, QML parsing,
manifest structure checks, Bash syntax, and Python syntax. It does not include
native integration because the hosted runner has no installed Omarchy shell.

## Limits

Offscreen checks exercise methods, signals, and layout. They do not prove physical
mouse/keyboard behavior, multi-monitor compositor integration, or fullscreen
visibility. The strip uses the native bar's top layer and may be hidden by
fullscreen applications. The compositor chooses whether to tile or float the
editor window. Multiple simultaneous external writers are unsupported.

The plugin shares the shell process, one minute clock, and filesystem change
notifications. The editor is created on demand. It launches no resident helper
process. Plugin-specific memory and CPU costs have not been established by a
controlled measurement; whole-shell usage cannot be attributed to one plugin.
