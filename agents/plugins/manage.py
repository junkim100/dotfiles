#!/usr/bin/env python3
"""Reconcile the shared catalog through native CLIs; never edit auth or caches."""

import argparse
import json
import os
import re
from pathlib import Path
import selectors
import shutil
import subprocess
import sys
import time

sys.dont_write_bytecode = True
import package_store as packages
from health import doctor

ROOT = Path(__file__).resolve().parents[2]
CATALOG = Path(__file__).with_name("catalog.json")


def read_catalog():
    catalog = json.loads(CATALOG.read_text())
    seen = set()
    skills = set()
    for source in catalog["sources"].values():
        if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", source["repo"]):
            raise ValueError("Invalid upstream repository")
        if not re.fullmatch(r"[a-f0-9]{40}", source["revision"]) or not re.fullmatch(r"[a-f0-9]{64}", source["sha256"]):
            raise ValueError("Every source needs a full commit and archive checksum")
    for plugin in catalog["plugins"]:
        name, marketplace = plugin["id"].split("@")
        if not re.fullmatch(r"[a-z0-9-]+", name) or marketplace != catalog["marketplace"] or plugin["id"] in seen:
            raise ValueError("Invalid or duplicate plugin: " + plugin["id"])
        if plugin["source"] not in catalog["sources"] or Path(plugin["path"]).is_absolute() or ".." in Path(plugin["path"]).parts:
            raise ValueError("Invalid source path for " + name)
        seen.add(plugin["id"])
        for agent in ("claude", "codex"):
            if not isinstance(plugin[agent], bool):
                raise ValueError("Each plugin must declare support for " + agent)
        if not plugin.get("limitations"):
            raise ValueError("Each plugin must describe its portability: " + name)
        for skill in plugin["skills"]:
            if skill in skills or not re.fullmatch(r"[a-z0-9-]+", skill):
                raise ValueError("Duplicate or unsafe skill: " + skill)
            skills.add(skill)
    return catalog


def call(args, env=None, json_output=False):
    result = subprocess.run(args, env=env, check=True, text=True,
                            stdout=subprocess.PIPE if json_output else None, timeout=600)
    return json.loads(result.stdout) if json_output else None


def binary(name):
    path = shutil.which(name)
    fallback = Path.home() / ".local/bin" / name
    if path:
        return path
    if fallback.is_file() and os.access(fallback, os.X_OK):
        return str(fallback)
    raise ValueError(name + " is missing; run agents/install.sh first")


def marketplaces(agent, cli, catalog, env):
    source = packages.store_root() / "marketplace"
    if agent == "codex":
        config = codex_rpc(cli, "config/read", {"includeLayers": False}, env)["config"]
        found = config.get("marketplaces", {}).get(catalog["marketplace"])
        actual = found.get("source", "") if found else ""
    else:
        registry = Path.home() / ".claude/plugins/known_marketplaces.json"
        data = json.loads(registry.read_text()) if registry.exists() else {}
        found = data.get(catalog["marketplace"])
        actual = found.get("source", {}).get("path", "") if found else ""
    if found:
        if not actual or Path(actual).resolve() != source.resolve():
            previous = Path(actual).resolve() if actual else None
            managed = previous and previous.parent == (packages.store_root() / "releases").resolve() and (previous / "receipt.json").is_file()
            if agent == "codex" and managed:
                print("[UPDATE] Codex marketplace to the selected pinned release", flush=True)
                codex_rpc(cli, "config/value/write", {"keyPath": "marketplaces.dotfiles.source", "value": str(source), "mergeStrategy": "upsert"}, env)
                return
            raise ValueError("Marketplace dotfiles points elsewhere; inspect it before changing it")
        print("[SKIP] " + agent + " shared marketplace", flush=True)
    else:
        call([cli, "plugin", "marketplace", "add", str(source)], env)
        if agent == "codex":
            # The CLI canonicalizes symlinks on add. Persist the stable pointer
            # so selecting a new release never requires removing a marketplace.
            codex_rpc(cli, "config/value/write", {"keyPath": "marketplaces.dotfiles.source", "value": str(source), "mergeStrategy": "upsert"}, env)


def installed(agent, cli, catalog, env):
    args = [cli, "plugin", "list"]
    if agent == "codex":
        args += ["--marketplace", catalog["marketplace"]]
    data = call(args + ["--json"], env, True)
    if agent == "claude":
        if not isinstance(data, list):
            raise ValueError("Claude returned an unexpected plugin list")
        return {row["id"]: row for row in data if row.get("scope") == "user"}
    if not isinstance(data, dict) or not isinstance(data.get("installed"), list):
        raise ValueError("Codex returned an unexpected plugin list")
    return {row["pluginId"]: row for row in data["installed"] if row.get("installed")}


def codex_rpc(cli, method, params, env):
    process = subprocess.Popen([cli, "app-server", "--stdio"], env=env,
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.DEVNULL)
    try:
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            requests = [
                {"id": 1, "method": "initialize", "params": {"clientInfo": {"name": "dotfiles", "version": "1.0.0"}}},
                {"id": 2, "method": method, "params": params},
            ]
            buffered = b""
            for request in requests:
                process.stdin.write((json.dumps(request) + "\n").encode())
                process.stdin.flush()
                deadline = time.monotonic() + 30
                while time.monotonic() < deadline:
                    if b"\n" not in buffered:
                        if not selector.select(1):
                            continue
                        chunk = os.read(process.stdout.fileno(), 65536)
                        if not chunk:
                            raise ValueError("Codex app-server closed during " + method)
                        buffered += chunk
                        continue
                    line, buffered = buffered.split(b"\n", 1)
                    response = json.loads(line)
                    if response.get("id") != request["id"]:
                        continue
                    if "error" in response:
                        raise ValueError("Codex " + method + " failed: " + str(response["error"]))
                    break
                else:
                    raise ValueError("Timed out waiting for Codex " + method)
        return response["result"]
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        process.stdin.close()
        process.stdout.close()


def set_codex_enabled(cli, plugin_id, enabled, env):
    codex_rpc(cli, "config/value/write", {
        "keyPath": 'plugins."' + plugin_id + '".enabled',
        "value": enabled, "mergeStrategy": "upsert"}, env)
    print("[CONFIG] codex " + plugin_id + " enabled=" + str(enabled), flush=True)


def reconcile(agent, catalog, codex_home):
    cli = binary(agent)
    env = dict(os.environ)
    if agent == "codex":
        env["CODEX_HOME"] = str(codex_home)
    marketplaces(agent, cli, catalog, env)
    rows = installed(agent, cli, catalog, env)
    for plugin in catalog["plugins"]:
        plugin_id = plugin["id"]
        if not plugin[agent]:
            print("[LIMIT] " + agent + " " + plugin_id + ": " + plugin["limitations"], flush=True)
            continue
        row = rows.get(plugin_id)
        version = packages.plugin_version(catalog, plugin)
        client_home = codex_home if agent == "codex" else Path.home() / ".claude"
        cache = client_home / "plugins/cache" / catalog["marketplace"] / plugin_id.split("@")[0] / version
        if not row or row.get("version") != version or not cache.is_dir():
            if agent == "claude":
                action = "update" if row else "install"
                call([cli, "plugin", action, plugin_id, "--scope", "user"], env)
            else:
                call([cli, "plugin", "add", plugin_id], env)
            row = installed(agent, cli, catalog, env).get(plugin_id, {})
        elif row.get("enabled"):
            print("[SKIP] " + agent + " " + plugin_id + " " + version, flush=True)
            continue
        if row.get("enabled"):
            continue
        if agent == "claude":
            call([cli, "plugin", "enable", plugin_id, "--scope", "user"], env)
        elif row:
            set_codex_enabled(cli, plugin_id, True, env)
    rows = installed(agent, cli, catalog, env)
    for plugin in catalog["plugins"]:
        row = rows.get(plugin["id"], {})
        if plugin[agent] and (not row.get("enabled") or row.get("version") != packages.plugin_version(catalog, plugin)):
            raise ValueError(agent + " does not have the enabled pinned plugin: " + plugin["id"])
    # Retire only the catalog's known former plugin IDs, after replacements work.
    config = codex_rpc(cli, "config/read", {"includeLayers": False}, env)["config"] if agent == "codex" else None
    for plugin in catalog["plugins"]:
        legacy = plugin["legacy_id"]
        if agent == "claude" and rows.get(legacy, {}).get("enabled"):
            call([cli, "plugin", "disable", legacy, "--scope", "user"], env)
        elif agent == "codex" and config.get("plugins", {}).get(legacy, {}).get("enabled"):
            set_codex_enabled(cli, legacy, False, env)


def export_skills(catalog):
    packages.verify_release(catalog)
    links = [(packages.release_path(catalog), packages.store_root() / "marketplace", None)]
    for plugin in catalog["plugins"]:
        package = packages.package_path(catalog, plugin)
        if plugin.get("root_link"):
            links.append((package, Path.home() / plugin["root_link"], plugin))
        for skill in plugin["skills"]:
            for directory in (".agents", ".claude"):
                links.append((package / "skills" / skill, Path.home() / directory / "skills" / skill, plugin))
    # Preflight all destinations. Allow only our releases and the previous
    # dotfiles-managed Codex cache links during this explicit migration.
    for source, destination, plugin in links:
        if destination.exists() and not destination.is_symlink():
            raise ValueError("Refusing to replace local content: " + str(destination))
        if destination.is_symlink():
            allowed = [packages.store_root() / "releases"]
            if plugin:
                name, marketplace = plugin["legacy_id"].split("@")
                allowed.append(Path.home() / ".codex/plugins/cache" / marketplace / name)
            if not any(root.resolve() in destination.resolve().parents for root in allowed):
                raise ValueError("Refusing to replace an unrelated symlink: " + str(destination))
        call([str(ROOT / "scripts/link-file"), "--dry-run", str(source), str(destination)])
    for source, destination, _ in links:
        call([str(ROOT / "scripts/link-file"), str(source), str(destination)])
    print("[INFO] Shared skills now resolve to pinned agent-neutral packages.", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("prepare", "dependencies", "claude", "codex", "export", "check", "doctor"))
    parser.add_argument("--codex-home", type=Path, default=Path.home() / ".codex")
    parser.add_argument("--json", action="store_true", help="Machine-readable doctor report")
    args = parser.parse_args()
    catalog = read_catalog()
    if args.action == "check":
        settings = json.loads((ROOT / "agents/claude-code/settings.json").read_text())
        expected = {p["id"] for p in catalog["plugins"] if p["claude"]}
        actual = {name for name, enabled in settings["enabledPlugins"].items() if enabled}
        managed = expected | {p["legacy_id"] for p in catalog["plugins"]}
        if expected != actual & managed:
            raise ValueError("Claude enabledPlugins and the shared plugin catalog differ: " + str(expected ^ (actual & managed)))
        if actual - managed:
            print("[INFO] Additional machine-local plugins are unmanaged: " + ", ".join(sorted(actual - managed)))
        print("Shared plugin catalog is valid")
    elif args.action == "dependencies":
        binary("node")
        # pnpm 10 also supports existing Node 20 installations; pnpm 11
        # requires Node >=22.13. Reuse newer working commands when present.
        wanted = {"pnpm": "10.34.6", "pyright-langserver": "1.1.414"}
        for tool, version in wanted.items():
            try:
                existing = binary(tool)
            except ValueError:
                existing = None
            if existing:
                print("[SKIP] " + tool + " already installed: " + existing)
                continue
            prefix = packages.store_root() / "tools"
            package = "pyright" if tool == "pyright-langserver" else tool
            call([binary("npm"), "install", "--prefix", str(prefix), "--no-audit", "--no-fund",
                  "--ignore-scripts", package + "@" + version])
            for name in (("pyright", "pyright-langserver") if package == "pyright" else ("pnpm", "pnpx")):
                call([str(ROOT / "scripts/link-file"), str(prefix / "node_modules/.bin" / name), str(Path.home() / ".local/bin" / name)])
    elif args.action == "prepare":
        packages.prepare(catalog)
    elif args.action == "export":
        export_skills(catalog)
    elif args.action == "doctor":
        if not doctor(catalog, ROOT, args.json):
            sys.exit(1)
    else:
        reconcile(args.action, catalog, args.codex_home)


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        print("Plugin command failed (exit " + str(error.returncode) + ")", file=sys.stderr)
        sys.exit(error.returncode if error.returncode > 0 else 1)
    except (ValueError, KeyError, OSError, subprocess.TimeoutExpired) as error:
        print("Plugin setup failed: " + str(error), file=sys.stderr)
        sys.exit(1)
