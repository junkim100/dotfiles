#!/usr/bin/env bash
# bash, not sh: uses arrays.
# List of packages to check and install
packages=(
  tmux
  bat
  jq
  ranger
  btop
  curl
  unzip
  python3-venv
  urlview
)

# Function to check if a package is installed.
# Checks PATH as well as dpkg, so binaries dropped into ~/.local/bin count.
is_installed() {
  [ "$(dpkg-query -W -f='${Status}' "$1" 2> /dev/null)" = "install ok installed" ] ||
    command -v "$1" &> /dev/null
}

# Work out whether we can escalate at all. On hosts where the sudoers entry has
# not been applied yet, skip the apt section instead of aborting the script.
SUDO=""
if [ "$(id -u)" -eq 0 ]; then
  CAN_ESCALATE=1
elif sudo -n true &> /dev/null; then
  CAN_ESCALATE=1
  SUDO="sudo"
else
  CAN_ESCALATE=0
fi

if [ "$CAN_ESCALATE" -eq 0 ]; then
  echo "No passwordless sudo on this host; skipping apt installs."
  missing=()
  for package in "${packages[@]}"; do
    is_installed "$package" || missing+=("$package")
  done
  if [ ${#missing[@]} -gt 0 ]; then
    echo "Still missing (install into ~/.local/bin by hand): ${missing[*]}"
  fi
else
  # Update package list
  $SUDO apt-get update

  # Loop through the packages and install if not installed
  for package in "${packages[@]}"; do
    if ! is_installed "$package"; then
      echo "Installing $package..."
      $SUDO apt-get install -y "$package"
    else
      echo "$package is already installed."
    fi
  done

  # Rename batcat to bat (Ubuntu ships it as batcat)
  if [ -f /usr/bin/batcat ] && [ ! -f /usr/bin/bat ]; then
    $SUDO mv /usr/bin/batcat /usr/bin/bat
  fi
fi

# nvitop is installed as a user-level Python tool, never through apt: the Ubuntu nvitop package depends on
# libnvidia-compute-<ver>, which replaces the NVML userspace library and breaks nvidia-smi on any host whose
# kernel module is a different driver version (this took down the NHN gpu099 login node twice in Sep 2026).
install_nvitop() {
  if command -v nvitop &> /dev/null; then
    echo "nvitop is already installed."
  elif command -v uv &> /dev/null; then
    echo "Installing nvitop with uv tool..."
    uv tool install nvitop
  elif command -v pipx &> /dev/null; then
    echo "Installing nvitop with pipx..."
    pipx install nvitop
  else
    echo "Installing nvitop with pip --user..."
    python3 -m pip install --user nvitop
  fi
}
install_nvitop
