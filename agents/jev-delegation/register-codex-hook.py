#!/usr/bin/env python3
"""Idempotently register the jev-observe PreToolUse hook in a Codex hooks.json.

Codex owns this file and Orca rewrites it, so it cannot be symlinked from the
repo. Merge in place instead, preserving every entry we did not write.
"""

import json
import sys
from pathlib import Path

COMMAND = '"$HOME/.local/bin/jev-observe" --agent codex'


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: register-codex-hook.py <hooks.json>", file=sys.stderr)
        return 2

    path = Path(sys.argv[1])
    data = {}

    if path.exists():
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            # Never clobber a file we cannot parse; Codex or Orca owns it.
            print(f"  [WARN] {path} is not valid JSON; leaving it alone", file=sys.stderr)
            return 0

    hooks = data.setdefault("hooks", {})
    pre = hooks.setdefault("PreToolUse", [])
    already = [e for e in pre if "jev-observe" in json.dumps(e)]

    if already:
        print(f"  [SKIP] {path} already registers jev-observe")
        return 0

    pre.append({"matcher": "Bash", "hooks": [{"type": "command", "command": COMMAND}]})
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    print(f"  [OK] registered jev-observe in {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
