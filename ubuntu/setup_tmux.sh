#!/bin/bash

# Define the source and destination paths for the configuration files
TMUX_CONF_SOURCE="$(cd "$(dirname "$0")" && pwd)/.tmux.conf"
TMUX_CONF_DEST="$HOME/.tmux.conf"

# Function to symlink the tmux configuration file to the home directory
copy_tmux_conf() {
  echo "Linking tmux configuration file to the home directory..."
  ln -sf $TMUX_CONF_SOURCE $TMUX_CONF_DEST
}

# Function to clone TPM (tmux Plugin Manager)
clone_tpm() {
  if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
    echo "Cloning TPM..."
    git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
  else
    echo "TPM already cloned."
  fi
}

# Function to install tmux plugins
install_plugins() {
  echo "Installing tmux plugins..."
  ~/.tmux/plugins/tpm/scripts/install_plugins.sh
}

# Execute the functions
copy_tmux_conf
clone_tpm
install_plugins

echo "tmux setup complete. You can now start tmux."

