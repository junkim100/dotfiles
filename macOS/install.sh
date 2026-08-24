#!/bin/sh
set -eu
 
# Install Homebrew if missing
if ! command -v brew > /dev/null 2>&1; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi
 
# Install everything from Brewfile
brew bundle install --file=~/dotfiles/macOS/Brewfile
# OMP config and CLI. macOS installs OMP with Homebrew.
bash ~/dotfiles/omp/install.sh
 
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

# Neovim (LazyVim). lazy-lock.json is committed, so `Lazy! restore` installs the
# same plugin commits here as on the Ubuntu boxes.
mkdir -p ~/.config
# Not `ln -sfn`: against an existing REAL directory that creates the link INSIDE
# it and returns 0, so the install looks fine while the config was never linked.
if [ -L ~/.config/nvim ]; then
  ln -sfn ~/dotfiles/nvim ~/.config/nvim
elif [ -e ~/.config/nvim ]; then
  nvim_backup=~/.config/nvim.backup.$(date +%Y%m%d%H%M%S)
  echo "$HOME/.config/nvim exists and is not a symlink; moving it to $nvim_backup"
  mv ~/.config/nvim "$nvim_backup"
  ln -s ~/dotfiles/nvim ~/.config/nvim
else
  ln -s ~/dotfiles/nvim ~/.config/nvim
fi
if command -v nvim > /dev/null 2>&1; then
  nvim --headless "+Lazy! restore" +qa 2>/dev/null || true
  # Language servers, so the first session opens complete rather than downloading.
  nvim --headless -c "luafile $HOME/dotfiles/nvim/bootstrap-mason.lua" 2>&1 | tail -4 || true
else
  echo "WARNING: nvim not on PATH after brew bundle; skipped plugin and server install."
fi

# Suppress the "Last login: ..." banner login(1) prints for every new login shell,
# which ghostty starts for every window and tab. The file only has to exist.
touch ~/.hushlogin

# bat
mkdir -p ~/.config/bat
ln -sf ~/dotfiles/bat-config ~/.config/bat/config

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
