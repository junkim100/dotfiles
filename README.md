# Dotfiles

Personal dotfiles and configuration scripts for macOS, Ubuntu, LazyVim, Claude Code, and OMP.

## Setup

```bash
git clone https://github.com/junkim100/dotfiles.git ~/dotfiles
```

**macOS:**
```bash
bash ~/dotfiles/macOS/install.sh
```

**Ubuntu:**
```bash
bash ~/dotfiles/ubuntu/install.sh
```

**LazyVim:**
```bash
bash ~/dotfiles/lazyvim/install.sh
```

The dedicated installer links `lazyvim/` to `~/.config/nvim`, installs the pinned Neovim release, and restores exact plugin commits from `lazy-lock.json`.

**Claude Code:**
```bash
bash ~/dotfiles/claude-code/install.sh
```

**OMP:**
```bash
bash ~/dotfiles/omp/install.sh
```

The OMP installer installs the CLI and links the shared `AGENTS.md`. OMP settings and themes remain local under `~/.omp/agent`.
