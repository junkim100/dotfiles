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
ln -sf ~/dotfiles/macOS/ghostty-theme-everforest-dark ~/.config/ghostty/themes/everforest-dark.txt
# macOS also reads (and "Open Config"/Cmd+, edits) the Application Support path
mkdir -p ~/Library/Application\ Support/com.mitchellh.ghostty
ln -sf ~/dotfiles/macOS/ghostty-config ~/Library/Application\ Support/com.mitchellh.ghostty/config

# Install the pinned Neovim binary and restore the exact LazyVim plugin revisions.
git -C ~/dotfiles submodule update --init --recursive lazyvim
bash ~/dotfiles/lazyvim/install.sh

# Suppress the "Last login: ..." banner login(1) prints for every new login shell,
# which ghostty starts for every window and tab. The file only has to exist.
touch ~/.hushlogin

# bat
mkdir -p ~/.config/bat
ln -sf ~/dotfiles/macOS/bat/config ~/.config/bat/config

# Ranger
mkdir -p ~/.config/ranger
ln -sf ~/dotfiles/macOS/ranger/rc.conf ~/.config/ranger/rc.conf

# Zed
mkdir -p ~/.config/zed/themes
ln -sf ~/dotfiles/macOS/zed-settings.json ~/.config/zed/settings.json
ln -sf ~/dotfiles/macOS/zed-keymap.json ~/.config/zed/keymap.json
ln -sf ~/dotfiles/macOS/zed-theme-glassy-nord.json ~/.config/zed/themes/glassy_nord.json
