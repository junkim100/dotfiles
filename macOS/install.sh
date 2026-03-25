#!/bin/sh
set -eu
 
ln -sf ~/dotfiles/macOS/.zshrc ~/.zshrc
ln -sf ~/dotfiles/macOS/.vimrc ~/.vimrc
ln -sf ~/dotfiles/macOS/.tmux.conf ~/.tmux.conf
 
# Ghostty
mkdir -p ~/.config/ghostty
ln -sf ~/dotfiles/macOS/ghostty-config ~/.config/ghostty/config
 
# Install TPM if missing
if [ ! -f "$HOME/.tmux/plugins/tpm/tpm" ]; then
  mkdir -p "$HOME/.tmux/plugins"
  git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
fi
 
# Start tmux once so it reads ~/.tmux.conf (initializes TPM env)
tmux start-server
tmux new-session -d -s __bootstrap "exit"
sleep 1
 
# Install plugins listed in ~/.tmux.conf
"$HOME/.tmux/plugins/tpm/bin/install_plugins"
 
tmux kill-server
