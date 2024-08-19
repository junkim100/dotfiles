#!/bin/bash

# Define the source and destination paths for the configuration files
TMUX_CONF_SOURCE="/data/junkim100/dotfiles/ubuntu_common/.tmux.conf"
TMUX_CONF_DEST="$HOME/.tmux.conf"

# Function to copy the tmux configuration file to the home directory
copy_tmux_conf() {
  echo "Copying tmux configuration file to the home directory..."
  cp $TMUX_CONF_SOURCE $TMUX_CONF_DEST
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
  tmux new-session -d -s temp_tpm_install 'sleep 2; tmux kill-session -t temp_tpm_install'
  tmux new-session -d -s temp_tpm_install 'sleep 2; tmux run-shell ~/.tmux/plugins/tpm/scripts/install_plugins.sh; tmux kill-session -t temp_tpm_install'
}

# Execute the functions
copy_tmux_conf
clone_tpm
install_plugins

echo "tmux setup complete. You can now start tmux."

