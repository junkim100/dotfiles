# List of packages to check and install
packages=(
  neofetch
  fzf
  bat
  ranger
  btop
)

# Function to check if a package is installed
is_installed() {
  dpkg -l "$1" &> /dev/null
}

# Update package list
sudo apt-get update

# Loop through the packages and install if not installed
for package in "${packages[@]}"; do
  if ! is_installed "$package"; then
    echo "Installing $package..."
    sudo apt-get install -y "$package"
  else
    echo "$package is already installed."
  fi
done

# Install fzf from source if necessary
if ! command -v fzf &> /dev/null; then
  echo "Installing fzf from source..."
  git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
  ~/.fzf/install
fi

# Rename batcat to bat
mv /usr/bin/batcat /usr/bin/bat

pip3 install --upgrade nvitop
