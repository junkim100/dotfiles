# Dotfiles Agent Rules

## Scope

This repository manages reproducible personal configuration for macOS, Ubuntu, and machine profiles. Prefer explicit symlinks and idempotent installers over generated configuration or hidden migration logic.

`AGENTS.md` is the canonical source of repository instructions and is read directly by current Claude Code and Codex. Do not create `CLAUDE.md` files or compatibility links. Personal instructions belong in `agents/AGENTS.md`; Claude Code loads that source through `~/.claude/rules/agents.md`.

## Ownership

- `macOS/` owns macOS-specific configuration and installation.
- `ubuntu/` owns Ubuntu-specific configuration and installation.
- `common/` owns canonical configuration used by two or more platforms. Platform paths may remain as compatibility symlinks when deployed home-directory links still target them.
- `profiles/` owns machine-role overlays that reuse a platform configuration, including the Backend.AI Ubuntu profile.
- `agents/` owns shared personal instructions, custom agent skills, the third-party plugin catalog, and agent installation. `agents/install.sh` installs the shared pieces, runs the Codex and Claude Code installers, then reconciles `agents/plugins/catalog.json` for both clients.
- `agents/claude-code/` owns Claude Code settings, the status line, and its installer. `agents/codex/` owns Codex CLI installation and its integration. Keep application-specific settings and installation here; keep shared instructions and skills at the top of `agents/`.
- `scripts/lib/install.sh` owns shared Bash installer argument handling, progress, diagnostics, downloads, and cleanup. `scripts/link-file` owns managed symlinks, and `scripts/tests/` owns isolated installer regression tests.
- `Casks/` makes the repository a Homebrew tap. It holds casks that Homebrew itself does not offer, and `macOS/Brewfile` taps the repository by URL so `brew bundle` can install them.
- `lazyvim/` is a Git submodule backed by `junkim100/lazyvim`.
- OMP settings, themes, credentials, and runtime state intentionally remain local under `~/.omp/agent` and must not be added to this repository.

## Safety

- Never commit credentials, tokens, cookies, machine-generated state, caches, application lock files, or private environment files.
- Preserve unrelated tracked modifications and untracked files. Never stage them as part of another task.
- Do not use broad staging commands such as `git add -A` from the repository root when unrelated work exists. Stage explicit paths.
- Do not commit or push unless the user explicitly requests it.
- Never replace a real configuration directory with a file symlink; fail instead.
- All installers must derive the repository root from their own path and use `scripts/link-file` for managed symlinks.
- Parent-repository installers must source `scripts/lib/install.sh`, call `install_init` before taking action, and support `--dry-run` and `--help`. Use `run_installer` to propagate previews to nested installers; preview external installers with `run` when they do not support dry runs.
- Required commands must fail visibly with their exit status. Do not suppress installation failures with `|| true`; optional skips must explain what is missing. Reuse existing tools by default and keep upgrades explicit.
- Edit the tracked source rather than the live file under `~/.config` when a managed symlink exists.
- Do not run the full macOS or Ubuntu installer merely for validation because those scripts install packages and alter live configuration. Validate them with `--dry-run`, which prints every action and changes nothing.

## Changes

- Keep platform-specific paths self-contained under their platform directory.
- When multiple platforms intentionally use identical configuration, keep one canonical file under `common/` and point installers and compatibility symlinks to it.
- Keep every custom authored skill under `agents/skills/` and link it into `~/.agents/skills` for Codex, Pi, and OpenCode. Claude Code must use symlinks in `~/.claude/skills` that resolve to those same canonical skill directories. Create these links directly from the canonical directories. Do not add application-specific skill copies or intermediate compatibility directories.
- Manage third-party plugins through `agents/plugins/catalog.json`, never a Claude-only installation list. Declare support for both Claude and Codex and document unsupported runtime features. Pin complete upstream packages by commit and archive checksum in the neutral store under `~/.local/share/agent-plugins`. Export portable skills into both discovery paths from that store, never from a client cache. Keep packages, build output, native caches, credentials, and machine-specific marketplace paths out of Git. Add adapters for future agents' MCP, hooks, and language-server features before claiming compatibility; a skill symlink alone does not install those features.
- Custom skills synced from claude.ai must also have canonical sources under `agents/skills/`, including their references and scripts. Import authored files without sync manifests or cache state. Disable duplicate synced commands by their `anthropic-skills:<name>` keys in Claude Code's `skillOverrides`; leave third-party synced skills and the application-managed cache alone.
- Update every installer callsite and README path when moving configuration.
- Keep profile installers under `profiles/<name>/`; profiles must reuse platform and common configuration instead of duplicating it.
- Remove obsolete files, paths, symlinks, and documentation after a clean migration.
- Treat `lazyvim/` as a separate repository. Commit and push changes in `junkim100/lazyvim` first, then update and commit the submodule pointer in this repository.
- Never make LazyVim edits only in the parent repository because the parent records only the submodule commit.
- Keep prose to one logical line per paragraph, list item, or heading.
- Do not use em dashes or en dashes in prose.

## Verification

- Run `scripts/check` after repository configuration or installer changes. GitHub Actions runs it on every push and pull request.
- Run `bash -n` on every changed shell script. Fragments meant to be sourced carry no shebang, so add them to the explicit syntax checks in `scripts/check`.
- Run `git diff --cached --check` before committing.
- Use `realpath` to verify changed live symlink targets.
- Use `cmp` when platform copies are expected to be identical.
- Validate Bat changes with `bat --config-file <path> --diagnostic`.
- Verify shared platform aliases resolve to their canonical files under `common/`.
- Check LazyVim integration with `git submodule status --recursive`.
- For LazyVim changes, run its dedicated installer and confirm Neovim starts with the expected configuration.
- Verify that no tracked installer or README still references a removed path. `scripts/check` enforces this for every path an installer links from.
- An installer wired into `check_dry_run` must use the shared argument parser and reject unknown options, otherwise the check could run it for real. Add each parent-repository installer to both the dry-run checks and the guarded preview tests.
