# Dotfiles Agent Rules

## Scope

This repository manages reproducible personal configuration for macOS and Ubuntu. Prefer explicit symlinks and idempotent installers over generated configuration or hidden migration logic.

## Ownership

- `macOS/` owns macOS-specific configuration and installation.
- `ubuntu/` owns Ubuntu-specific configuration and installation.
- Bat and Ranger intentionally have platform-specific copies under both platform directories. Do not move them back to shared top-level paths.
- `claude-code/` owns Claude Code configuration and installation.
- `lazyvim/` is a Git submodule backed by `junkim100/lazyvim`.
- OMP settings, themes, credentials, state, and instructions intentionally remain local under `~/.omp/agent` and must not be added to this repository.

## Safety

- Never commit credentials, tokens, cookies, machine-generated state, caches, application lock files, or private environment files.
- Preserve unrelated tracked modifications and untracked files. Never stage them as part of another task.
- Do not use broad staging commands such as `git add -A` from the repository root when unrelated work exists. Stage explicit paths.
- Do not commit or push unless the user explicitly requests it.
- Never overwrite a real configuration directory with a symlink without first preserving it as a timestamped backup.
- Edit the tracked source rather than the live file under `~/.config` when a managed symlink exists.
- Do not run the full macOS or Ubuntu installer merely for validation because those scripts install packages and alter live configuration.

## Changes

- Keep platform-specific paths self-contained under their platform directory.
- When macOS and Ubuntu intentionally use identical configuration, update both copies and verify they remain byte-identical.
- Update every installer callsite and README path when moving configuration.
- Remove obsolete files, paths, symlinks, and documentation after a clean migration.
- Treat `lazyvim/` as a separate repository. Commit and push changes in `junkim100/lazyvim` first, then update and commit the submodule pointer in this repository.
- Never make LazyVim edits only in the parent repository because the parent records only the submodule commit.
- Keep prose to one logical line per paragraph, list item, or heading.
- Do not use em dashes or en dashes in prose.

## Verification

- Run `bash -n` on every changed shell script.
- Run `git diff --cached --check` before committing.
- Use `realpath` to verify changed live symlink targets.
- Use `cmp` when platform copies are expected to be identical.
- Validate Bat changes with `bat --config-file <path> --diagnostic`.
- Check LazyVim integration with `git submodule status --recursive`.
- For LazyVim changes, run its dedicated installer and confirm Neovim starts with the expected configuration.
- Verify that no tracked installer or README still references a removed path.
