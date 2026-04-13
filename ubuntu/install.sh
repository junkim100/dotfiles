DOTFILES_DIR="$HOME/dotfiles"
SCRIPT_DIR="$DOTFILES_DIR/ubuntu"

chmod -R +x "$SCRIPT_DIR"

clear

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

# Symlink slurm_notifier.sh
if ln -sf "$SCRIPT_DIR/slurm_notifier.sh" "$HOME/slurm_notifier.sh"; then
    echo "Successfully linked slurm_notifier.sh"
else
    echo "Failed to link slurm_notifier.sh"
fi

bash "$SCRIPT_DIR/setup_tmux.sh"

# Check if conda is installed and run setup_conda.sh if it's not
if ! command -v conda &> /dev/null; then
    echo "Conda is not installed. Running setup_conda.sh..."
    bash "$SCRIPT_DIR/setup_conda.sh"
fi

# Install apt packages
bash "$SCRIPT_DIR/install_packages.sh"
