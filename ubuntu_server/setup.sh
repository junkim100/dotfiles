cp /data/junkim100/dotfiles/ubuntu_server/.bashrc $HOME
cp /data/junkim100/dotfiles/ubuntu_common/.vimrc $HOME

bash /data/junkim100/dotfiles/ubuntu_common/setup_tmux.sh

cp /data/junkim100/dotfiles/ubuntu_server/runtitle /usr/bin/

# Check if conda is installed and run setup_conda.sh if it's not
if ! command -v conda &> /dev/null
then
    echo "Conda is already installed."
else
    echo "Conda is not installed. Running setup_conda.sh..."
    bash /data/junkim100/dotfiles/ubuntu_server/setup_conda.sh
fi

# Install apt packages
bash /data/junkim100/dotfiles/ubuntu_common/install_packages.sh
