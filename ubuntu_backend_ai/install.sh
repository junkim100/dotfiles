#!/usr/bin/env bash
set -euo pipefail

MINICONDA_DIR="$HOME/miniconda3"
DOTFILES_DIR="$HOME/data00/private/junkim/dotfiles"
CACHE_DIR="$HOME/data00/private/junkim/.cache"

# 0. Symlink ~/.cache to data00 (avoid filling up small home partition)
mkdir -p "$CACHE_DIR"
if [ -L "$HOME/.cache" ]; then
  # Already a symlink — update if pointing elsewhere
  if [ "$(readlink "$HOME/.cache")" != "$CACHE_DIR" ]; then
    ln -sfn "$CACHE_DIR" "$HOME/.cache"
  fi
elif [ -d "$HOME/.cache" ]; then
  # Existing directory — move contents then replace with symlink
  cp -a "$HOME/.cache/." "$CACHE_DIR/" 2>/dev/null || true
  rm -rf "$HOME/.cache"
  ln -s "$CACHE_DIR" "$HOME/.cache"
else
  ln -s "$CACHE_DIR" "$HOME/.cache"
fi

# 1. Symlink dotfiles
ln -sf "$DOTFILES_DIR/ubuntu_backend_ai/.bashrc" ~/.bashrc
ln -sf "$DOTFILES_DIR/ubuntu/.vimrc" ~/.vimrc
ln -sf "$DOTFILES_DIR/ubuntu/.tmux.conf" ~/.tmux.conf
ln -sf "$DOTFILES_DIR/.gitconfig" ~/.gitconfig
mkdir -p ~/.config/ranger
ln -sf "$DOTFILES_DIR/ubuntu/ranger/rc.conf" ~/.config/ranger/rc.conf
bash "$DOTFILES_DIR/claude-code/install.sh"

# 2. Install miniconda if missing
if [ ! -d "$MINICONDA_DIR" ]; then
  wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh
  bash /tmp/miniconda.sh -b -p "$MINICONDA_DIR"
  rm /tmp/miniconda.sh
fi

source "$MINICONDA_DIR/bin/activate"

# 3. Conda config
conda config --set auto_activate_base false
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main 2>/dev/null || true
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r 2>/dev/null || true

# 4. Install packages (skip if already present)
command -v tmux &>/dev/null || conda install -y -c conda-forge 'tmux=3.5a' ncurses
# Symlink tmux into ~/.local/bin so it's available without activating conda base
mkdir -p ~/.local/bin
ln -sf "$MINICONDA_DIR/bin/tmux" ~/.local/bin/tmux

# Install TPM (tmux plugin manager) and plugins
if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
  git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
fi
~/.tmux/plugins/tpm/scripts/install_plugins.sh

# 5. Install GitHub CLI (gh)
if ! command -v gh &>/dev/null || [[ "$(gh --version 2>&1)" != *"gh version"* ]]; then
  GH_VERSION="2.88.1"
  wget -q "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" -O /tmp/gh.tar.gz
  tar -xzf /tmp/gh.tar.gz -C /tmp
  mkdir -p ~/.local/bin
  cp "/tmp/gh_${GH_VERSION}_linux_amd64/bin/gh" ~/.local/bin/
  rm -rf /tmp/gh.tar.gz "/tmp/gh_${GH_VERSION}_linux_amd64"
fi

# 6. Install xterm-ghostty terminfo (for SSH from Ghostty terminal)
if ! infocmp xterm-ghostty &>/dev/null 2>&1; then
  tmp=$(mktemp)
  cat > "$tmp" <<'TERMINFO'
xterm-ghostty|ghostty terminal emulator,
    use=xterm-256color,
TERMINFO
  tic -x "$tmp"
  rm -f "$tmp"
fi

echo "Setup complete. Run 'source ~/.bashrc' to apply."
