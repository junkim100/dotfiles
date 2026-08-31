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

The Omarchy installer is intended for a fresh Omarchy installation. It restores the selected applications, removes unwanted stock applications and web apps, links the tracked Hyprland and application configuration, and reapplies the current defaults and theme. Existing configuration files are backed up once with a `.pre-omarchy-dotfiles` suffix.

Omarchy reuses the repository's Linux Bat and Ranger configuration from `ubuntu/bat/` and `ubuntu/ranger/`; there are no stale references to the removed root-level config paths. See [`omarchy/README.md`](omarchy/README.md) for the complete restored state and external authentication requirements.

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
