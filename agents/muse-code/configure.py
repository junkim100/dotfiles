#!/usr/bin/env python3
"""Merge Muse preferences into local settings without copying credentials into dotfiles."""

import json
import os
from pathlib import Path
import sys
import tempfile


def configure(path: Path) -> None:
    # Follow an existing settings symlink without replacing it.
    path = path.resolve()
    settings = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {"schema_version": 1}
    if not isinstance(settings, dict) or settings.get("schema_version") != 1:
        raise ValueError("expected a Muse settings object with schema_version 1; leaving it unchanged")
    preferences = {
        "contributor_mode_enabled": False,
        "contributor_mode_disclosure_acknowledged": True,
    }
    if all(settings.get(key) is value for key, value in preferences.items()):
        print(f"  [SKIP] Contributor mode already disabled in {path}")
        return
    settings.update(preferences)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent, prefix=".settings-", delete=False) as output:
            temporary = Path(output.name)
            json.dump(settings, output, indent=2, ensure_ascii=False)
            output.write("\n")
        os.replace(temporary, path)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()
    print(f"  [OK] Contributor mode disabled in {path}; unrelated settings preserved")


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: configure.py <settings.json>", file=sys.stderr)
        return 2
    try:
        configure(Path(sys.argv[1]))
    except (OSError, ValueError) as error:
        print(f"  [ERROR] Cannot configure Muse Code: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
