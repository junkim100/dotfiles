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

**Neovim (LazyVim):**

The shared LazyVim configuration lives in `nvim/` and is linked to `~/.config/nvim` by both platform installers. It stays separate from platform-specific files, like `claude-code/` and `omp/`.

**Claude Code:**
```bash
bash ~/dotfiles/claude-code/install.sh
```

**OMP:**
```bash
bash ~/dotfiles/omp/install.sh
```

The OMP installer uses Homebrew on macOS and Bun on Linux, then links the tracked configuration and custom themes from `omp/`.
