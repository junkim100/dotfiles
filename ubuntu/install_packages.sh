#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$DOTFILES_DIR/scripts/lib/install.sh"
install_init "Ubuntu packages" 3 "$@"

step "System packages"
require_os Linux
packages=(tmux bat jq ranger btop curl unzip python3-venv urlview)
missing=()
for package in "${packages[@]}"; do
  if [[ $(dpkg-query -W -f='${Status}' "$package" 2>/dev/null || true) == 'install ok installed' ]] \
    || command -v "$package" >/dev/null 2>&1 \
    || { [[ $package == bat ]] && command -v batcat >/dev/null 2>&1; }; then
    skip "$package already installed"
  else
    missing+=("$package")
  fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
  if $DRY_RUN; then
    info "Would install missing packages if root or passwordless sudo is available: ${missing[*]}"
    run apt-get update
    run apt-get install -y "${missing[@]}"
  else
    require_commands apt-get dpkg-query
    apt_command=(apt-get)
    can_install=true
    if [[ $(id -u) -ne 0 ]]; then
      if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
        apt_command=(sudo -n apt-get)
      else
        can_install=false
        warn "No passwordless sudo; missing packages were skipped: ${missing[*]}. Ask an administrator to install them, then rerun."
      fi
    fi
    if $can_install; then
      run "${apt_command[@]}" update
      run "${apt_command[@]}" install -y "${missing[@]}"
    fi
  fi
fi

step "bat command alias"
# Keep apt-owned /usr/bin/batcat intact; expose the conventional name locally.
if command -v bat >/dev/null 2>&1; then
  skip "bat already available"
elif command -v batcat >/dev/null 2>&1; then
  link_file "$(command -v batcat)" "$HOME/.local/bin/bat"
elif $DRY_RUN; then
  info "Would link batcat to ~/.local/bin/bat after package installation."
else
  warn "batcat is unavailable; skipping the bat alias."
fi

step "nvitop"
# Never install nvitop through apt: its NVIDIA dependencies can break host drivers.
if command -v nvitop >/dev/null 2>&1; then
  skip "nvitop already installed"
elif [[ -x $HOME/.local/share/dotfiles/nvitop/bin/nvitop ]]; then
  skip "nvitop environment already installed"
  link_file "$HOME/.local/share/dotfiles/nvitop/bin/nvitop" "$HOME/.local/bin/nvitop"
elif command -v uv >/dev/null 2>&1; then
  run uv tool install nvitop
elif command -v pipx >/dev/null 2>&1; then
  run pipx install nvitop
else
  nvitop_env="$HOME/.local/share/dotfiles/nvitop"
  if ! $DRY_RUN; then require_commands python3; fi
  run python3 -m venv "$nvitop_env"
  run "$nvitop_env/bin/python" -m pip install nvitop
  if $DRY_RUN; then
    info "Would link $nvitop_env/bin/nvitop to ~/.local/bin/nvitop."
  else
    link_file "$nvitop_env/bin/nvitop" "$HOME/.local/bin/nvitop"
  fi
fi
finish
