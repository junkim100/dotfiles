#!/usr/bin/env bash
# bash, not sh: this script uses `&>`. Without a shell and errexit, a failed symlink
# or a failed setup_conda.sh let the install carry on and report success.
set -eu

DOTFILES_DIR="$HOME/dotfiles"
SCRIPT_DIR="$DOTFILES_DIR/ubuntu"

chmod -R +x "$SCRIPT_DIR"

# `|| true` because clear exits non-zero with no TERM, which under errexit would
# abort the install when it is piped or run from a provisioning script.
clear || true

# Symlink .gitconfig
ln -sf "$DOTFILES_DIR/.gitconfig" "$HOME/.gitconfig"

# Create symbolic links for .bashrc and .vimrc
if ln -sf "$SCRIPT_DIR/.bashrc" "$HOME/.bashrc"; then
    echo "Successfully linked .bashrc"
else
    echo "Failed to link .bashrc"
fi

if ln -sf "$SCRIPT_DIR/.vimrc" "$HOME/.vimrc"; then
    echo "Successfully linked .vimrc"
else
    echo "Failed to link .vimrc"
fi

bash "$SCRIPT_DIR/setup_tmux.sh"

# bat config
mkdir -p ~/.config/bat
ln -sf "$DOTFILES_DIR/ubuntu/bat/config" ~/.config/bat/config

# Ranger config
mkdir -p ~/.config/ranger
ln -sf "$DOTFILES_DIR/ubuntu/ranger/rc.conf" ~/.config/ranger/rc.conf

# Check if conda is installed and run setup_conda.sh if it's not
if ! command -v conda &> /dev/null; then
    echo "Conda is not installed. Running setup_conda.sh..."
    bash "$SCRIPT_DIR/setup_conda.sh"
fi

# Install apt packages
bash "$SCRIPT_DIR/install_packages.sh"

# Install the pinned Neovim binary and restore the exact LazyVim plugin revisions after system dependencies are available.
git -C "$DOTFILES_DIR" submodule update --init --recursive lazyvim
bash "$DOTFILES_DIR/lazyvim/install.sh"
