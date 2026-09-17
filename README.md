# Dotfiles

Personal dotfiles and configuration scripts for macOS, Ubuntu, LazyVim, Claude Code, and Codex.

## Setup

```bash
git clone --recurse-submodules https://github.com/junkim100/dotfiles.git "$HOME/dotfiles"
DOTFILES_DIR="$HOME/dotfiles"
```

Installers derive the repository root from their own location, so the checkout may live anywhere.

The repository is also a Homebrew tap. `Casks/` carries casks that Homebrew itself does not offer, currently the GlobalProtect VPN client, and `macOS/Brewfile` taps the repository by URL so `brew bundle` installs them like any other cask.

The macOS and Ubuntu installers accept `--dry-run`, which prints every action and changes nothing. Use it to preview a fresh install, or to check an installer edit without running it against your own machine.

**macOS:**
```bash
bash "$DOTFILES_DIR/macOS/install.sh"
```

**Ubuntu:**
```bash
bash "$DOTFILES_DIR/ubuntu/install.sh"
```

**Backend.AI profile on Ubuntu:**
```bash
bash "$DOTFILES_DIR/profiles/backend-ai/install.sh"
```

Configuration shared by two or more platforms lives under `common/`. This currently includes tmux, Bat, Ranger, Git defaults, and the Everforest Ghostty theme. Platform Git files include the shared defaults and remain available for platform-specific overrides. Compatibility symlinks at old paths keep existing installations working.

The shared tmux installer links the canonical configuration and installs TPM, tmux-resurrect, and tmux-continuum. Sessions save every 15 minutes, restore when tmux starts, and start automatically after login on supported macOS and Linux systems.

**LazyVim:**
```bash
git -C "$DOTFILES_DIR" submodule update --init --recursive lazyvim
bash "$DOTFILES_DIR/lazyvim/install.sh"
```

The configuration lives in [`junkim100/lazyvim`](https://github.com/junkim100/lazyvim) and is pinned here as a Git submodule. Its installer links the checkout to `~/.config/nvim`, installs the pinned Neovim release, and restores exact plugin commits from `lazy-lock.json`.

**Shared agent skills (Codex, Pi, OpenCode, and Claude Code):**
```bash
bash "$DOTFILES_DIR/agents/install.sh"
```

All repository-managed skills live under `agents/skills/`, currently `interview`, `pr-review`, and `quiz`. The agent installer links each skill into `~/.agents/skills`, which Codex, [Pi](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/skills.md#locations), and [OpenCode](https://opencode.ai/docs/skills/#place-files) discover directly, leaving room for machine-local skills in the same directory. This also works when an agent is installed later; the script does not need to detect or install agent applications. Use `--dry-run` to preview the links. Claude Code receives its links through the installer below.

**Claude Code:**
```bash
bash "$DOTFILES_DIR/claude-code/install.sh"
```

`claude-code/` owns Claude Code settings, instructions, the status line, and installation. Its installer links the same canonical skills from `agents/skills/` into `~/.claude/skills`, preserving machine-local skills. `claude-code/skills/` contains only compatibility symlinks, including the `pr` alias for `pr-review`; existing home-directory links through those paths keep working.

## Verification

Run the location-independent repository check before pushing configuration changes:

```bash
"$DOTFILES_DIR/scripts/check"
```

It verifies the shared-configuration symlinks, shell syntax, and tmux settings, and runs the macOS and Ubuntu installers with `--dry-run` against a temporary home. Because `scripts/link-file` rejects a missing source even in a dry run, that last step also proves every file the installers link from still exists.

GitHub Actions runs the same check on every push and pull request, defined in `.github/workflows/check.yml`.
