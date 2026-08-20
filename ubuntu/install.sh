DOTFILES_DIR="$HOME/dotfiles"
SCRIPT_DIR="$DOTFILES_DIR/ubuntu"

chmod -R +x "$SCRIPT_DIR"

clear

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
ln -sf "$DOTFILES_DIR/bat-config" ~/.config/bat/config

# Ranger config
mkdir -p ~/.config/ranger
ln -sf "$SCRIPT_DIR/ranger/rc.conf" ~/.config/ranger/rc.conf

# Check if conda is installed and run setup_conda.sh if it's not
if ! command -v conda &> /dev/null; then
    echo "Conda is not installed. Running setup_conda.sh..."
    bash "$SCRIPT_DIR/setup_conda.sh"
fi

# Install apt packages
bash "$SCRIPT_DIR/install_packages.sh"

# Neovim (LazyVim). Installs neovim into ~/.local with no sudo, since apt's
# version is too old, then symlinks the config and restores pinned plugins.
# Runs last so anything install_packages.sh provides is already in place.
DOTFILES_DIR="$DOTFILES_DIR" bash "$SCRIPT_DIR/setup_nvim.sh"
