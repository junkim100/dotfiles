#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DOTFILES_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
LINK_FILE="$DOTFILES_DIR/scripts/link-file"

"$LINK_FILE" "$DOTFILES_DIR" "$HOME/.config/dotfiles/repo"
 
# Install Homebrew if missing
if ! command -v brew > /dev/null 2>&1; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi
 
# Install everything from Brewfile
brew bundle install --file="$SCRIPT_DIR/Brewfile"
 
# Layer platform Git configuration over the shared defaults.
"$LINK_FILE" "$DOTFILES_DIR/common/git/config" "$HOME/.config/git/common"
"$LINK_FILE" "$SCRIPT_DIR/git/config" "$HOME/.gitconfig"
"$LINK_FILE" "$SCRIPT_DIR/.zshrc" "$HOME/.zshrc"
"$LINK_FILE" "$SCRIPT_DIR/.vimrc" "$HOME/.vimrc"
"$LINK_FILE" "$DOTFILES_DIR/common/tmux/tmux.conf" "$HOME/.tmux.conf"
 
# Ghostty
mkdir -p ~/.config/ghostty/themes
"$LINK_FILE" "$SCRIPT_DIR/ghostty-config" "$HOME/.config/ghostty/config"
"$LINK_FILE" "$SCRIPT_DIR/ghostty-theme-glassy-nord" "$HOME/.config/ghostty/themes/glassy-nord"
"$LINK_FILE" "$DOTFILES_DIR/common/ghostty/themes/everforest-dark.txt" "$HOME/.config/ghostty/themes/everforest-dark.txt"
# macOS also reads (and "Open Config"/Cmd+, edits) the Application Support path
mkdir -p ~/Library/Application\ Support/com.mitchellh.ghostty
"$LINK_FILE" "$SCRIPT_DIR/ghostty-config" "$HOME/Library/Application Support/com.mitchellh.ghostty/config"

# Install the pinned Neovim binary and restore the exact LazyVim plugin revisions.
git -C "$DOTFILES_DIR" submodule update --init --recursive lazyvim
bash "$DOTFILES_DIR/lazyvim/install.sh"

# Suppress the "Last login: ..." banner login(1) prints for every new login shell,
# which ghostty starts for every window and tab. The file only has to exist.
touch ~/.hushlogin

# bat
mkdir -p ~/.config/bat
"$LINK_FILE" "$DOTFILES_DIR/common/bat/config" "$HOME/.config/bat/config"

# Ranger
mkdir -p ~/.config/ranger
"$LINK_FILE" "$DOTFILES_DIR/common/ranger/rc.conf" "$HOME/.config/ranger/rc.conf"

# Zed
mkdir -p ~/.config/zed/themes
"$LINK_FILE" "$SCRIPT_DIR/zed-settings.json" "$HOME/.config/zed/settings.json"
"$LINK_FILE" "$SCRIPT_DIR/zed-keymap.json" "$HOME/.config/zed/keymap.json"
"$LINK_FILE" "$SCRIPT_DIR/zed-theme-glassy-nord.json" "$HOME/.config/zed/themes/glassy_nord.json"
