# Dotfiles Agent Rules

## Scope

This repository manages reproducible personal configuration for macOS, Ubuntu, and machine profiles. Prefer explicit symlinks and idempotent installers over generated configuration or hidden migration logic.

## Ownership

- `macOS/` owns macOS-specific configuration and installation.
- `ubuntu/` owns Ubuntu-specific configuration and installation.
- `common/` owns canonical configuration used by two or more platforms. Platform paths may remain as compatibility symlinks when deployed home-directory links still target them.
- `profiles/` owns machine-role overlays that reuse a platform configuration, including the Backend.AI Ubuntu profile.
- `claude-code/` owns Claude Code configuration and installation.
- `agents/` owns canonical agent skills and their installation into `~/.agents/skills`, which Codex discovers directly. The Claude Code installer links shared skills from here into `~/.claude/skills`.
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
- Edit the tracked source rather than the live file under `~/.config` when a managed symlink exists.
- Do not run the full macOS or Ubuntu installer merely for validation because those scripts install packages and alter live configuration. Validate them with `--dry-run`, which prints every action and changes nothing.

## Changes

- Keep platform-specific paths self-contained under their platform directory.
- When multiple platforms intentionally use identical configuration, keep one canonical file under `common/` and point installers and compatibility symlinks to it.
- When Claude Code and Codex intentionally share a skill, keep one canonical skill under `agents/skills/`, link it into `~/.agents/skills` for Codex, and link the same source into `~/.claude/skills` instead of maintaining copies.
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
- An installer wired into `check_dry_run` must parse `--dry-run` and reject unknown options, otherwise the check runs it for real.
