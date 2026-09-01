# Dotfiles

Personal dotfiles and configuration scripts for macOS, Ubuntu, Omarchy, LazyVim, and Claude Code.

## Setup

```bash
git clone --recurse-submodules https://github.com/junkim100/dotfiles.git ~/dotfiles
```

**macOS:**
```bash
bash ~/dotfiles/macOS/install.sh
```

**Ubuntu:**
```bash
bash ~/dotfiles/ubuntu/install.sh
```

**Omarchy:**
```bash
bash ~/dotfiles/omarchy/install.sh
```

The Omarchy installer is intended for a fresh Omarchy installation. It restores the selected applications, removes unwanted stock applications and web apps, replaces existing configuration files with links to the tracked configuration, and reapplies the current defaults and theme.

Configuration shared by two or more platforms lives under `common/`. This currently includes tmux, Bat, Ranger, and the Everforest Ghostty theme. Compatibility symlinks at the old platform paths keep existing installations working.

The MacBook-specific monitor layout is intentionally skipped on other hardware. Include it explicitly when restoring the same display setup:

```bash
bash ~/dotfiles/omarchy/install.sh --include-hardware
```

Preview the complete operation without changing the machine:

```bash
bash ~/dotfiles/omarchy/install.sh --dry-run
```

The shared SSH private key and authenticated application state are not stored in Git and must be restored separately through a secure channel.

**LazyVim:**
```bash
git -C ~/dotfiles submodule update --init --recursive lazyvim
bash ~/dotfiles/lazyvim/install.sh
```

The configuration lives in [`junkim100/lazyvim`](https://github.com/junkim100/lazyvim) and is pinned here as a Git submodule. Its installer links the checkout to `~/.config/nvim`, installs the pinned Neovim release, and restores exact plugin commits from `lazy-lock.json`.

**Claude Code:**
```bash
bash ~/dotfiles/claude-code/install.sh
```
