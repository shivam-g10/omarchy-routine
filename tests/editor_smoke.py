#!/usr/bin/env python3
"""Exercise native editor behavior and optionally render an offscreen preview."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import tempfile

from native_smoke import run_phase

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--shell", type=Path, default=Path("/usr/share/omarchy/shell"))
    parser.add_argument("--theme", type=Path, help="Render with a read-only copy of this Omarchy theme directory")
    parser.add_argument("--image", type=Path, help="Save an offscreen native editor screenshot")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="omarchy-routine-editor-") as temporary:
        base = Path(temporary)
        for name in ("home", "runtime", "config", "data", "cache", "state", "harness"):
            (base / name).mkdir(mode=0o700)
        if args.theme:
            theme_target = base / "home/.local/state/omarchy/current/theme"
            theme_target.mkdir(parents=True)
            for name in ("colors.toml", "shell.toml"):
                source = args.theme / name
                if source.is_file():
                    shutil.copy2(source, theme_target / name)
        config = base / "harness"
        shutil.copy2(ROOT / "tests/EditorHarness.qml", config / "shell.qml")
        (config / "Plugin").symlink_to(ROOT / "qml", target_is_directory=True)
        for name in ("Commons", "Ui"):
            (config / name).symlink_to(args.shell / name, target_is_directory=True)
        environment = {key: os.environ[key] for key in ("PATH", "USER", "LOGNAME", "LANG", "TZ") if key in os.environ}
        environment.update(
            HOME=str(base / "home"), XDG_RUNTIME_DIR=str(base / "runtime"),
            XDG_CONFIG_HOME=str(base / "config"), XDG_DATA_HOME=str(base / "data"),
            XDG_STATE_HOME=str(base / "state"), XDG_CACHE_HOME=str(base / "cache"),
            XDG_DATA_DIRS="/usr/local/share:/usr/share", QT_QPA_PLATFORM="offscreen",
            QT_QPA_PLATFORMTHEME="", QT_QUICK_BACKEND="software", QSG_RHI_BACKEND="software",
            DBUS_SESSION_BUS_ADDRESS="unix:path=" + str(base / "runtime/unavailable-bus"),
            DBUS_SYSTEM_BUS_ADDRESS="unix:path=" + str(base / "runtime/unavailable-bus"),
            HYPRLAND_INSTANCE_SIGNATURE="omarchy-routine-test-unavailable",
            OMARCHY_PATH=str(args.shell.parent),
        )
        if args.image:
            args.image.parent.mkdir(parents=True, exist_ok=True)
            environment["ROUTINE_TEST_IMAGE"] = str(args.image.resolve())
        editor = run_phase(config, environment, "editor", base / "data/routine.json")
        environment.pop("ROUTINE_TEST_IMAGE", None)
        protected = base / "protected"
        protected.mkdir(mode=0o500)
        try:
            failure = run_phase(config, environment, "editor-write-failure", protected / "routine.json")
        finally:
            protected.chmod(0o700)
        print(json.dumps({"ok": True, "checks": editor["checks"] + failure["checks"],
                          "image": str(args.image.resolve()) if args.image else None,
                          "runtime": "Quickshell offscreen with real Editor, Store, and Omarchy theme components",
                          "limitations": "Methods and signals exercised; no compositor or physical input coverage"}, indent=2))


if __name__ == "__main__":
    main()
