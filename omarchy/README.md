# Omarchy Setup

## Goal

Run this installer on a **fresh Omarchy installation** to reproduce the applications, application removals, keybindings, and user configuration from the current Omarchy machine.

This directory intentionally manages user-facing setup only. It does not modify Omarchy source code or attempt to reproduce hardware-independent operating-system internals.

## Install

Clone the dotfiles repository on the fresh Omarchy machine, then run:

```bash
git clone --recurse-submodules https://github.com/junkim100/dotfiles.git ~/dotfiles
bash ~/dotfiles/omarchy/install.sh
```

Preview every intended operation without changing the machine:

```bash
bash ~/dotfiles/omarchy/install.sh --dry-run
```

The tracked monitor configuration is specific to the MacBook display and is skipped by default. Restore it only on compatible hardware:

```bash
bash ~/dotfiles/omarchy/install.sh --include-hardware
```

## Restored state

The installer:

- Installs Ghostty, Zen Browser, Tailscale, Voxtype, and Widevine.
- Sets Ghostty as the default terminal and Zen as the default browser.
- Restores the Everforest theme and JetBrainsMono Nerd Font.
- Removes the stock packages and web apps listed under `packages/`.
- Links the tracked Hyprland, Omarchy, Ghostty, Fcitx, Git, Mise, Voxtype, SSH, and desktop-launcher configuration into `$HOME`.
- Reuses the shared Linux Bat and Ranger configuration from `../ubuntu/bat/config` and `../ubuntu/ranger/rc.conf`.
- Runs `mise install` to restore the tools declared in the tracked Mise configuration, including OMP.
- Initializes a new Zen profile when needed so the Omarchy theme hook can generate Zen CSS.

Existing destination files are backed up once with a `.pre-omarchy-dotfiles` suffix before repository symlinks replace them. The installer is safe to rerun.

The Bat and Ranger files deliberately remain owned by the Ubuntu/Linux folder instead of being duplicated under `omarchy/home`. Changes to those shared files therefore apply to both Ubuntu and Omarchy installers.

## Files

```text
omarchy/
├── install.sh                 # Fresh-install entry point
├── config-files.txt           # Hardware-independent files linked into $HOME
├── hardware-files.txt         # Optional hardware-specific files
├── packages/
│   ├── install.txt            # Additional native packages
│   ├── remove.txt             # Unwanted packages
│   └── remove-webapps.txt     # Unwanted Omarchy web apps
└── home/                      # Tracked files mirroring paths under $HOME
```

## State intentionally not stored

The repository does not contain:

- SSH private keys
- Tailscale authentication
- Browser cookies, history, sessions, or profiles
- Generated Zen CSS
- Application caches or databases

Restore `~/.ssh/id_ed25519` through a secure channel. Tailscale may require interactive authentication during the first installation.
