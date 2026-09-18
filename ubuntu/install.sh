#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$DOTFILES_DIR/scripts/lib/install.sh"
install_init "Ubuntu setup" 6 "$@"

step "Platform and dependencies"
require_os Linux
if ! $DRY_RUN; then require_commands apt-get git; fi

step "Shell and tool configuration"
link_file "$DOTFILES_DIR" "$HOME/.config/dotfiles/repo"

# Layer platform Git configuration over the shared defaults.
link_file "$DOTFILES_DIR/common/git/config" "$HOME/.config/git/common"
link_file "$SCRIPT_DIR/git/config" "$HOME/.gitconfig"

# Create symbolic links for .bashrc and .vimrc
link_file "$SCRIPT_DIR/.bashrc" "$HOME/.bashrc"
link_file "$SCRIPT_DIR/.vimrc" "$HOME/.vimrc"

# bat config
run mkdir -p "$HOME/.config/bat"
link_file "$DOTFILES_DIR/common/bat/config" "$HOME/.config/bat/config"

# Ranger config
run mkdir -p "$HOME/.config/ranger"
link_file "$DOTFILES_DIR/common/ranger/rc.conf" "$HOME/.config/ranger/rc.conf"

# urlview, for the tmux URL picker on prefix + u
link_file "$DOTFILES_DIR/common/urlview/config" "$HOME/.urlview"

step "System packages"
run_installer "$SCRIPT_DIR/install_packages.sh"

step "Conda"
run_installer "$SCRIPT_DIR/setup_conda.sh"

step "tmux"
run_installer "$DOTFILES_DIR/common/tmux/install.sh"

# Install the pinned Neovim binary and restore the exact LazyVim plugin revisions after system dependencies are available.
step "LazyVim"
run git -C "$DOTFILES_DIR" submodule update --init --recursive lazyvim
run bash "$DOTFILES_DIR/lazyvim/install.sh"
finish
