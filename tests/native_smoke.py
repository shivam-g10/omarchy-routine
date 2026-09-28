#!/usr/bin/env python3
"""Exercise the plugin in Quickshell without connecting to the user's desktop."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import resource
import shutil
import signal
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
MARKER = "ROUTINE_NATIVE_RESULT="


def no_core() -> None:
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


def run_phase(config: Path, environment: dict[str, str], phase: str, data: Path) -> dict:
    env = {**environment, "ROUTINE_TEST_PHASE": phase, "ROUTINE_TEST_DATA": str(data)}
    process = subprocess.Popen(
        ["qs", "--no-color", "-p", str(config / "shell.qml")],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        start_new_session=True,
        preexec_fn=no_core,
    )
    try:
        output, _ = process.communicate(timeout=15)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        output, _ = process.communicate()
        raise RuntimeError(f"{phase}: Quickshell timed out\n{output}") from None
    finally:
        # Quickshell may launch helper processes while resolving theme tokens.
        # This process group belongs exclusively to this test invocation.
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    results = [json.loads(line.split(MARKER, 1)[1]) for line in output.splitlines() if MARKER in line]
    runtime_errors = ("TypeError:", "ReferenceError:", "Binding loop detected", "Unable to assign")
    if (process.returncode or len(results) != 1 or not results[0].get("ok")
            or any(error in output for error in runtime_errors)):
        raise RuntimeError(f"{phase}: native check failed (exit {process.returncode})\n{output}")
    return results[0]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--shell", type=Path, default=Path("/usr/share/omarchy/shell"),
                        help="Installed Omarchy shell containing the real Commons and Ui modules")
    args = parser.parse_args()
    if not shutil.which("qs"):
        parser.error("Quickshell (qs) is required")
    for path in (ROOT / "qml/Service.qml", ROOT / "qml/Store.qml", ROOT / "qml/InlineStrip.qml", args.shell / "Commons/qmldir", args.shell / "Ui/qmldir"):
        if not path.is_file():
            parser.error(f"Required file is missing: {path}")
    with tempfile.TemporaryDirectory(prefix="omarchy-routine-native-") as temporary:
        base = Path(temporary)
        for name in ("home", "runtime", "config", "data", "cache", "state", "harness"):
            (base / name).mkdir(mode=0o700)
        config = base / "harness"
        shutil.copy2(ROOT / "tests/NativeHarness.qml", config / "shell.qml")
        (config / "Plugin").symlink_to(ROOT / "qml", target_is_directory=True)
        for name in ("Commons", "Ui"):
            (config / name).symlink_to(args.shell / name, target_is_directory=True)
        environment = {key: os.environ[key] for key in ("PATH", "USER", "LOGNAME", "LANG", "TZ") if key in os.environ}
        environment.update(
            HOME=str(base / "home"),
            XDG_RUNTIME_DIR=str(base / "runtime"),
            XDG_CONFIG_HOME=str(base / "config"),
            XDG_DATA_HOME=str(base / "data"),
            XDG_STATE_HOME=str(base / "state"),
            XDG_CACHE_HOME=str(base / "cache"),
            XDG_DATA_DIRS="/usr/local/share:/usr/share",
            QT_QPA_PLATFORM="offscreen",
            QT_QPA_PLATFORMTHEME="",
            QT_QUICK_BACKEND="software",
            QSG_RHI_BACKEND="software",
            DBUS_SESSION_BUS_ADDRESS="unix:path=" + str(base / "runtime/unavailable-bus"),
            DBUS_SYSTEM_BUS_ADDRESS="unix:path=" + str(base / "runtime/unavailable-bus"),
            HYPRLAND_INSTANCE_SIGNATURE="omarchy-routine-test-unavailable",
            OMARCHY_PATH=str(args.shell.parent),
        )
        data = base / "data/routine.json"
        initial = run_phase(config, environment, "defaults", data)
        assert not data.exists(), "Loading defaults must not create the routine file"
        written = run_phase(config, environment, "write", data)
        on_disk = json.loads(data.read_text())
        assert on_disk == written["document"], "Native save did not persist the committed document"
        restored = run_phase(config, environment, "read", data)
        assert restored["document"] == on_disk, "A new native process did not restore the saved document"
        reloaded = run_phase(config, environment, "reload", data)
        assert json.loads(data.read_text()) == reloaded["document"], "An external repair was not preserved"
        data.write_text(json.dumps(on_disk))

        legacy = base / "data/legacy.json"
        legacy_weekend = json.loads(json.dumps(on_disk["default"]))
        legacy_weekend[0]["name"] = "Legacy weekend activity"
        legacy_date = json.loads(json.dumps(on_disk["default"]))
        legacy_date[0]["name"] = "Legacy date activity"
        legacy_document = {"version": 1, "usual": on_disk["default"],
                           "weekend": legacy_weekend, "dates": {"2026-12-28": legacy_date}}
        legacy_text = json.dumps(legacy_document, indent=4)
        legacy.write_text(legacy_text)
        migrated_read = run_phase(config, environment, "read", legacy)
        expected_migration = {"version": 2, "default": on_disk["default"],
                              "days": {"sat": legacy_weekend, "sun": legacy_weekend},
                              "dates": legacy_document["dates"]}
        assert migrated_read["document"] == expected_migration, "Legacy Usual/Weekend did not migrate to Default and Saturday/Sunday"
        assert legacy.read_text() == legacy_text, "Reading a legacy routine must not rewrite its file"
        migrated_write = run_phase(config, environment, "migrate", legacy)
        assert json.loads(legacy.read_text()) == expected_migration, "An explicit save did not persist the migrated version-2 schema"
        migrated_restart = run_phase(config, environment, "read", legacy)
        assert migrated_restart["document"] == expected_migration, "A new native process did not restore the migrated routine"

        broken = base / "data/invalid.json"
        original = '{"broken":'
        broken.write_text(original)
        invalid = run_phase(config, environment, "invalid", broken)
        assert broken.read_text() == original, "Malformed user data was overwritten"

        protected = base / "protected"
        protected.mkdir(mode=0o500)
        try:
            failed = run_phase(config, environment, "write-failure", protected / "routine.json")
            assert not (protected / "routine.json").exists(), "The failed save unexpectedly created a file"
        finally:
            protected.chmod(0o700)
        geometry = run_phase(config, environment, "geometry", data)
        print(json.dumps({"ok": True, "checks": [initial["phase"], written["phase"], restored["phase"], reloaded["phase"], "legacy-read", migrated_write["phase"], "migration-restart", invalid["phase"], failed["phase"], geometry["phase"]],
                          "geometry": geometry["sizes"],
                          "runtime": "Quickshell offscreen with installed Omarchy modules",
                          "limitations": "No compositor, native input, stacking, or reserved-space validation"}, indent=2))


if __name__ == "__main__":
    main()
