# Dotfiles

Personal dotfiles and configuration scripts for macOS, Ubuntu, LazyVim, and Claude Code.

## Setup

```bash
git clone --recurse-submodules https://github.com/junkim100/dotfiles.git "$HOME/dotfiles"
DOTFILES_DIR="$HOME/dotfiles"
```

Installers derive the repository root from their own location, so the checkout may live anywhere.

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

**Claude Code:**
```bash
bash "$DOTFILES_DIR/claude-code/install.sh"
```

## Verification

Run the location-independent repository check before pushing configuration changes:

```bash
"$DOTFILES_DIR/scripts/check"
```
