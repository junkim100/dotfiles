"""Read-only checks: no CLI startup, network request, auth lookup, or repair."""

import json
from pathlib import Path
import re
import shutil

import package_store as packages


def codex_enabled(path, plugin_id):
    if not path.exists():
        return False
    text = path.read_text()
    try:
        import tomllib
    except ImportError:
        # Older system Pythons can read the explicit plugin tables written by
        # Codex. Unrecognized layouts remain unverified rather than guessed.
        pattern = r"(?m)^\[plugins\.(['\"])" + re.escape(plugin_id) + r"\1\]\s*\n([^\[]*)"
        match = re.search(pattern, text)
        return bool(match and re.search(r"(?m)^enabled\s*=\s*true\s*(?:#.*)?$", match.group(2)))
    return tomllib.loads(text).get("plugins", {}).get(plugin_id, {}).get("enabled", False)


def codex_homes():
    import os
    homes = [Path.home() / ".codex"]
    if os.environ.get("CODEX_HOME"):
        homes.append(Path(os.environ["CODEX_HOME"]).expanduser())
    orca = Path.home() / "Library/Application Support/orca/codex-runtime-home/home"
    if orca.is_dir():
        homes.append(orca)
    return list(dict.fromkeys(homes))


def doctor(catalog, root, as_json=False):
    checks = []

    def record(label, status, detail):
        checks.append({"check": label, "status": status, "detail": detail})

    try:
        receipt = packages.verify_release(catalog)
        record("shared packages", "ok", "Pinned source checksums and authored files match")
    except (OSError, ValueError, KeyError) as error:
        receipt = None
        record("shared packages", "fail", str(error))

    def link(label, path, target):
        good = path.is_symlink() and path.exists() and path.resolve() == target.resolve()
        record(label, "ok" if good else "fail", str(path))

    def cache_matches(cache, name):
        if not cache.is_dir():
            return False
        if receipt:
            prefix = "plugins/" + name + "/"
            for relative, expected in receipt["files"].items():
                if relative.startswith(prefix):
                    path = cache / relative[len(prefix):]
                    if not path.is_file() or packages.file_hash(path) != expected:
                        return False
        return True

    link("marketplace", packages.store_root() / "marketplace", packages.release_path(catalog))
    for skill in sorted((root / "agents/skills").iterdir()):
        if (skill / "SKILL.md").is_file():
            for host in (".agents", ".claude"):
                link(host + " " + skill.name, Path.home() / host / "skills" / skill.name, skill)
    for plugin in catalog["plugins"]:
        package = packages.package_path(catalog, plugin)
        for skill in plugin["skills"]:
            for host in (".agents", ".claude"):
                link(host + " " + skill, Path.home() / host / "skills" / skill, package / "skills" / skill)
        if plugin.get("root_link"):
            link(plugin["id"] + " root", Path.home() / plugin["root_link"], package)
        if plugin.get("mcp"):
            try:
                mcp = json.loads((package / ".mcp.json").read_text())
                if not isinstance(mcp, dict) or not mcp:
                    raise ValueError("empty MCP definition")
                record(plugin["id"] + " MCP", "ok", "Configuration present; account authorization is not checked")
            except (OSError, ValueError) as error:
                record(plugin["id"] + " MCP", "fail", str(error))

    settings_path = Path.home() / ".claude/settings.json"
    registry_path = Path.home() / ".claude/plugins/installed_plugins.json"
    try:
        settings = json.loads(settings_path.read_text())
        registry = json.loads(registry_path.read_text()).get("plugins", {})
        managed = {p[key] for p in catalog["plugins"] for key in ("id", "legacy_id")}
        extra = {name for name, enabled in settings.get("enabledPlugins", {}).items() if enabled and name not in managed}
        if extra:
            record("unmanaged Claude plugins", "warn", "Outside the shared catalog: " + ", ".join(sorted(extra)))
        for plugin in catalog["plugins"]:
            expected = packages.plugin_version(catalog, plugin)
            rows = registry.get(plugin["id"], [])
            row = next((r for r in rows if r.get("scope") == "user" and r.get("version") == expected), None)
            enabled = settings.get("enabledPlugins", {}).get(plugin["id"]) is True
            good = enabled and row and cache_matches(Path(row.get("installPath", "")), plugin["id"].split("@")[0])
            record("claude " + plugin["id"], "ok" if good else "fail", "Expected " + expected)
    except (OSError, ValueError) as error:
        record("claude plugins", "fail", str(error))

    for home in codex_homes():
        for plugin in catalog["plugins"]:
            if not plugin["codex"]:
                continue
            name = plugin["id"].split("@")[0]
            version = packages.plugin_version(catalog, plugin)
            cache = home / "plugins/cache" / catalog["marketplace"] / name / version
            enabled = codex_enabled(home / "config.toml", plugin["id"])
            good = enabled and cache_matches(cache, name)
            record(str(home) + " " + name, "ok" if good else "fail", "Expected " + version)
    for tool in ("claude", "codex", "node", "pnpm", "pyright-langserver"):
        found = shutil.which(tool) or (str(Path.home() / ".local/bin" / tool) if (Path.home() / ".local/bin" / tool).is_file() else None)
        record("dependency " + tool, "ok" if found else "warn", found or "Not installed or not on PATH")
    record("runtime limits", "info", "Other agents need MCP adapters; Claude graph-update hooks and Pyright LSP are host-specific. OAuth grants and browser/model execution are not tested by this read-only check.")
    report = {"healthy": not any(c["status"] == "fail" for c in checks), "checks": checks}
    if as_json:
        print(json.dumps(report, indent=2))
    else:
        for check in checks:
            if check["status"] != "ok":
                print("[" + check["status"].upper() + "] " + check["check"] + ": " + check["detail"])
        print("Health check: " + str(sum(c["status"] == "ok" for c in checks)) + " passed, " +
              str(sum(c["status"] == "fail" for c in checks)) + " failed, " +
              str(sum(c["status"] == "warn" for c in checks)) + " warnings")
    return report["healthy"]
