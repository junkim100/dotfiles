#!/bin/sh
set -eu
 
# Install Homebrew if missing
if ! command -v brew > /dev/null 2>&1; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi
 
# Install everything from Brewfile
brew bundle install --file=~/dotfiles/macOS/Brewfile
 
# Symlink dotfiles
ln -sf ~/dotfiles/.gitconfig ~/.gitconfig
ln -sf ~/dotfiles/macOS/.zshrc ~/.zshrc
ln -sf ~/dotfiles/macOS/.vimrc ~/.vimrc
ln -sf ~/dotfiles/macOS/.tmux.conf ~/.tmux.conf
 
# Ghostty
mkdir -p ~/.config/ghostty/themes
ln -sf ~/dotfiles/macOS/ghostty-config ~/.config/ghostty/config
ln -sf ~/dotfiles/macOS/ghostty-theme-glassy-nord ~/.config/ghostty/themes/glassy-nord
# macOS also reads (and "Open Config"/Cmd+, edits) the Application Support path
mkdir -p ~/Library/Application\ Support/com.mitchellh.ghostty
ln -sf ~/dotfiles/macOS/ghostty-config ~/Library/Application\ Support/com.mitchellh.ghostty/config

# Zed
mkdir -p ~/.config/zed/themes
ln -sf ~/dotfiles/macOS/zed-settings.json ~/.config/zed/settings.json
ln -sf ~/dotfiles/macOS/zed-keymap.json ~/.config/zed/keymap.json
ln -sf ~/dotfiles/macOS/zed-theme-glassy-nord.json ~/.config/zed/themes/glassy_nord.json
 
# Install TPM if missing
if [ ! -f "$HOME/.tmux/plugins/tpm/tpm" ]; then
  mkdir -p "$HOME/.tmux/plugins"
  git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
fi
 
# Install plugins listed in ~/.tmux.conf
"$HOME/.tmux/plugins/tpm/scripts/install_plugins.sh"
