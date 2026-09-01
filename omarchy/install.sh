#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DRY_RUN=false
INCLUDE_HARDWARE=false

usage() {
  cat <<'USAGE'
Usage: bash ~/dotfiles/omarchy/install.sh [--dry-run] [--include-hardware]

Reproduce this machine's applications, removals, keybindings, and user config
on a fresh Omarchy install. Existing config files are replaced by repository
symlinks without creating backup copies.

Options:
  --dry-run           Print intended changes without modifying the machine.
  --include-hardware  Also install the MacBook-specific monitor layout.
USAGE
}

while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=true ;;
    --include-hardware) INCLUDE_HARDWARE=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if ! command -v omarchy >/dev/null 2>&1; then
  echo "This installer must run from an Omarchy installation." >&2
  exit 1
fi

run() {
  if $DRY_RUN; then
    printf '  +'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

read_manifest() {
  local file="$1"
  local target_name="$2"
  local line
  local -n target="$target_name"

  target=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    target+=("$line")
  done < "$file"
}

link_file() {
  local source="$1"
  local target="$2"

  if [[ ! -f "$source" ]]; then
    echo "Missing tracked config: $source" >&2
    exit 1
  fi

  if [[ -L "$target" && "$(readlink "$target")" == "$source" ]]; then
    echo "  = $target"
    return
  fi

  if $DRY_RUN; then
    printf '  + link %s -> %s\n' "$target" "$source"
    return
  fi

  mkdir -p "$(dirname "$target")"
  if [[ -e "$target" || -L "$target" ]]; then
    rm -f "$target"
  fi
  ln -s "$source" "$target"
  echo "  linked $target"
}

install_optional_apps() {
  echo "Installing optional applications..."

  if ! command -v ghostty >/dev/null 2>&1; then
    run omarchy install terminal ghostty
  fi

  if ! omarchy pkg present zen-browser-bin >/dev/null 2>&1; then
    run omarchy install browser zen
  fi

  if ! omarchy pkg present tailscale >/dev/null 2>&1; then
    run omarchy install service tailscale
  fi

  if ! command -v voxtype >/dev/null 2>&1; then
    run omarchy voxtype install
  fi
}

install_packages() {
  local packages=()
  read_manifest "$SCRIPT_DIR/packages/install.txt" packages
  if ((${#packages[@]})); then
    echo "Installing extra packages..."
    run omarchy pkg add "${packages[@]}"
  fi
}

remove_packages() {
  local packages=()
  read_manifest "$SCRIPT_DIR/packages/remove.txt" packages
  if ((${#packages[@]})); then
    echo "Removing unwanted packages..."
    run omarchy pkg drop "${packages[@]}"
  fi

  if [[ -d /opt/1Password ]] || omarchy pkg present 1password >/dev/null 2>&1 || omarchy pkg present 1password-cli >/dev/null 2>&1; then
    run omarchy remove service 1password
  fi
}

remove_webapps() {
  local apps=()
  local app
  read_manifest "$SCRIPT_DIR/packages/remove-webapps.txt" apps
  echo "Removing unwanted web apps..."
  for app in "${apps[@]}"; do
    run env OMARCHY_REMOVE_NOTIFY=false omarchy webapp remove "$app"
  done
}

install_configs() {
  local files=()
  local path
  read_manifest "$SCRIPT_DIR/config-files.txt" files

  echo "Linking tracked configuration..."
  for path in "${files[@]}"; do
    link_file "$SCRIPT_DIR/home/$path" "$HOME/$path"
  done

  if $INCLUDE_HARDWARE; then
    read_manifest "$SCRIPT_DIR/hardware-files.txt" files
    for path in "${files[@]}"; do
      link_file "$SCRIPT_DIR/home/$path" "$HOME/$path"
    done
  else
    echo "  - skipped MacBook-specific monitor config (use --include-hardware)"
  fi

  if [[ -f "$DOTFILES_DIR/common/bat/config" ]]; then
    link_file "$DOTFILES_DIR/common/bat/config" "$HOME/.config/bat/config"
  fi
  if [[ -f "$DOTFILES_DIR/common/ranger/rc.conf" ]]; then
    link_file "$DOTFILES_DIR/common/ranger/rc.conf" "$HOME/.config/ranger/rc.conf"
  fi
}

initialize_zen_profile() {
  [[ -f "$HOME/.config/zen/profiles.ini" ]] && return
  command -v zen-browser >/dev/null 2>&1 || return

  echo "Initializing the Zen profile so the Omarchy theme hook can configure it..."
  if $DRY_RUN; then
    echo "  + zen-browser --headless --screenshot <temporary-file> about:blank"
    return
  fi

  local screenshot
  screenshot="$(mktemp --suffix=.png)"
  if ! timeout 30s zen-browser --headless --screenshot "$screenshot" about:blank >/dev/null 2>&1; then
    echo "Zen profile initialization did not finish; launch Zen once and rerun this installer." >&2
  fi
  rm -f "$screenshot"
}

apply_defaults() {
  echo "Applying Omarchy defaults..."
  run omarchy default terminal ghostty
  run omarchy default browser zen
  run omarchy font set "JetBrainsMono Nerd Font"

  initialize_zen_profile
  run omarchy theme set everforest

  if command -v mise >/dev/null 2>&1; then
    run mise install
  fi

  if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    run hyprctl reload
    if ! $DRY_RUN; then
      hyprctl configerrors
    fi
  fi
}

warn_about_external_state() {
  if [[ ! -f "$HOME/.ssh/id_ed25519" ]]; then
    cat >&2 <<'WARNING'

SSH config was installed, but ~/.ssh/id_ed25519 is absent.
Restore the shared private key through a secure channel; it is intentionally
not stored in Git.
WARNING
  fi

  if command -v tailscale >/dev/null 2>&1 && ! tailscale status >/dev/null 2>&1; then
    cat >&2 <<'WARNING'

Tailscale is installed but not authenticated. Run: sudo tailscale up --accept-routes
WARNING
  fi
}

install_optional_apps
install_packages
remove_packages
remove_webapps
install_configs
apply_defaults
warn_about_external_state

echo "Omarchy dotfiles installation complete."
