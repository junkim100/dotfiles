# List of packages to check and install
packages=(
  tmux
  bat
  jq
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

# Rename batcat to bat (Ubuntu ships it as batcat)
if [ -f /usr/bin/batcat ] && [ ! -f /usr/bin/bat ]; then
  sudo mv /usr/bin/batcat /usr/bin/bat
fi

pip3 install --upgrade nvitop
