"""Pinned upstream packages in a neutral store, independent of agent caches."""

import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import tarfile
import tempfile
import urllib.request


def digest(catalog):
    return hashlib.sha256(json.dumps(catalog, sort_keys=True).encode()).hexdigest()[:16]


def store_root():
    return Path.home() / ".local/share/agent-plugins"


def release_path(catalog):
    return store_root() / "releases" / digest(catalog)


def plugin_version(catalog, plugin):
    return plugin["version"] + "+dotfiles." + digest(catalog)


def package_path(catalog, plugin):
    return release_path(catalog) / "plugins" / plugin["id"].split("@")[0]


def file_hash(path):
    hasher = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            hasher.update(block)
    return hasher.hexdigest()


def download(source, destination):
    url = "https://codeload.github.com/" + source["repo"] + "/tar.gz/" + source["revision"]
    print("[FETCH] " + source["repo"] + " at " + source["revision"], flush=True)
    with urllib.request.urlopen(url, timeout=120) as response, destination.open("wb") as stream:
        shutil.copyfileobj(response, stream)
    if file_hash(destination) != source["sha256"]:
        raise ValueError("Archive checksum mismatch for " + source["repo"])


def unpack_package(archive, subdirectory, destination):
    # Only regular files and directories from the selected upstream subtree are
    # accepted. No archive symlinks, hard links, or traversal can escape it.
    count = 0
    with tarfile.open(archive) as bundle:
        members = bundle.getmembers()
        top = PurePosixPath(members[0].name).parts[0]
        prefix = PurePosixPath(top) / subdirectory
        for member in members:
            path = PurePosixPath(member.name)
            if path.is_absolute() or ".." in path.parts:
                raise ValueError("Unsafe archive path: " + member.name)
            try:
                relative = path.relative_to(prefix)
            except ValueError:
                continue
            target = destination.joinpath(*relative.parts)
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
            elif member.isfile():
                target.parent.mkdir(parents=True, exist_ok=True)
                with bundle.extractfile(member) as src, target.open("wb") as dst:
                    shutil.copyfileobj(src, dst)
                target.chmod(member.mode & 0o777)
                count += 1
            else:
                raise ValueError("Unsupported archive entry: " + member.name)
    if not count:
        raise ValueError("Upstream package directory is empty: " + subdirectory)


def finish_release(catalog, directory):
    entries = []
    for plugin in catalog["plugins"]:
        name = plugin["id"].split("@")[0]
        package = directory / "plugins" / name
        # Upstream's bundled viewer has no dependencies but is missing from
        # its workspace lockfile. pnpm 11 adds it even with --frozen-lockfile.
        # Normalize declared empty importers before recording source hashes.
        if plugin.get("pnpm_empty_importers"):
            lockfile = package / "pnpm-lock.yaml"
            lock = lockfile.read_text()
            if "\nimporters:\n" not in lock or "\npackages:\n" not in lock:
                raise ValueError("Unrecognized pnpm lockfile: " + name)
            for importer in plugin["pnpm_empty_importers"]:
                if "\n  " + importer + ":" not in lock:
                    lock = lock.replace("\npackages:\n", "  " + importer + ": {}\n\npackages:\n", 1)
            lockfile.write_text(lock)
        manifest_path = package / ".claude-plugin/plugin.json"
        manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {"name": name}
        manifest["version"] = plugin_version(catalog, plugin)
        if plugin.get("lspServers"):
            manifest["lspServers"] = plugin["lspServers"]
        manifest_path.parent.mkdir(parents=True, exist_ok=True)
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
        # Native manifests take precedence over Claude's compatibility manifest.
        # Keep every manifest on the same source-derived cache version.
        for relative in ("plugin.json", ".codex-plugin/plugin.json"):
            path = package / relative
            if path.is_file():
                native = json.loads(path.read_text())
                native["version"] = manifest["version"]
                path.write_text(json.dumps(native, indent=2) + "\n")
        for skill in plugin["skills"]:
            if not (package / "skills" / skill / "SKILL.md").is_file():
                raise ValueError("Upstream skill is missing: " + name + "/" + skill)
        if plugin.get("mcp") and not (package / ".mcp.json").is_file():
            raise ValueError("Upstream MCP configuration is missing: " + name)
        entries.append({"name": name, "source": "./plugins/" + name,
                        "version": manifest["version"], "description": manifest.get("description", name)})
    marketplace = directory / ".claude-plugin/marketplace.json"
    marketplace.parent.mkdir(parents=True, exist_ok=True)
    marketplace.write_text(json.dumps({"name": catalog["marketplace"], "owner": {"name": "dotfiles"},
                                      "plugins": entries}, indent=2) + "\n")
    files = {str(p.relative_to(directory)): file_hash(p) for p in directory.rglob("*") if p.is_file()}
    (directory / "receipt.json").write_text(json.dumps({"catalog": catalog, "files": files}, indent=2) + "\n")


def verify_release(catalog):
    directory = release_path(catalog)
    receipt = json.loads((directory / "receipt.json").read_text())
    if receipt["catalog"] != catalog:
        raise ValueError("Shared package receipt does not match the catalog")
    for relative, expected in receipt["files"].items():
        path = directory / relative
        if not path.is_file() or file_hash(path) != expected:
            raise ValueError("Shared package file is missing or modified: " + str(path))
    return receipt


def prepare(catalog):
    destination = release_path(catalog)
    if destination.exists():
        verify_release(catalog)
        print("[SKIP] Verified pinned shared packages: " + str(destination), flush=True)
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".prepare-", dir=str(destination.parent)) as scratch:
        scratch = Path(scratch)
        output = scratch / "release"
        archives = {}
        for key, source in catalog["sources"].items():
            archive = store_root() / "archives" / (source["sha256"] + ".tgz")
            if archive.is_file():
                if file_hash(archive) != source["sha256"]:
                    raise ValueError("Cached archive checksum mismatch: " + str(archive))
            else:
                archive.parent.mkdir(parents=True, exist_ok=True)
                fetched = scratch / (key + ".tgz")
                download(source, fetched)
                os.replace(fetched, archive)
            archives[key] = archive
        for plugin in catalog["plugins"]:
            name = plugin["id"].split("@")[0]
            unpack_package(archives[plugin["source"]], plugin["path"], output / "plugins" / name)
        finish_release(catalog, output)
        # Publish only complete releases. A failed download or validation leaves
        # the previous release and every live skill link untouched.
        os.rename(output, destination)
    verify_release(catalog)
    print("[OK] Prepared pinned shared packages: " + str(destination), flush=True)
