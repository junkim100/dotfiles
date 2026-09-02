#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LINK_FILE="$DOTFILES_DIR/scripts/link-file"

"$LINK_FILE" "$DOTFILES_DIR" "$HOME/.config/dotfiles/repo"

# `|| true` because clear exits non-zero with no TERM, which under errexit would
# abort the install when it is piped or run from a provisioning script.
clear || true

# Layer platform Git configuration over the shared defaults.
"$LINK_FILE" "$DOTFILES_DIR/common/git/config" "$HOME/.config/git/common"
"$LINK_FILE" "$SCRIPT_DIR/git/config" "$HOME/.gitconfig"

# Create symbolic links for .bashrc and .vimrc
"$LINK_FILE" "$SCRIPT_DIR/.bashrc" "$HOME/.bashrc"
"$LINK_FILE" "$SCRIPT_DIR/.vimrc" "$HOME/.vimrc"

# bat config
mkdir -p ~/.config/bat
"$LINK_FILE" "$DOTFILES_DIR/common/bat/config" "$HOME/.config/bat/config"

# Ranger config
mkdir -p ~/.config/ranger
"$LINK_FILE" "$DOTFILES_DIR/common/ranger/rc.conf" "$HOME/.config/ranger/rc.conf"

# Install Conda only when neither PATH nor the managed installation contains it.
if ! command -v conda &> /dev/null && [ ! -x "$HOME/miniconda3/bin/conda" ]; then
    echo "Conda is not installed. Running setup_conda.sh..."
    bash "$SCRIPT_DIR/setup_conda.sh"
fi

# Install apt packages
bash "$SCRIPT_DIR/install_packages.sh"

bash "$DOTFILES_DIR/common/tmux/install.sh"

# Install the pinned Neovim binary and restore the exact LazyVim plugin revisions after system dependencies are available.
git -C "$DOTFILES_DIR" submodule update --init --recursive lazyvim
bash "$DOTFILES_DIR/lazyvim/install.sh"
