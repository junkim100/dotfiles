#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LINK_FILE="$DOTFILES_DIR/scripts/link-file"
DRY_RUN=false

usage() {
  cat <<'USAGE'
Usage: ubuntu/install.sh [--dry-run]

Install the Ubuntu configuration: the tracked symlinks, apt packages, Conda,
tmux, and LazyVim.

Options:
  --dry-run  Print intended changes without modifying the machine.
USAGE
}

while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

DRY_RUN_FLAG=""
$DRY_RUN && DRY_RUN_FLAG="--dry-run"

run() {
  if $DRY_RUN; then
    printf '  + %s\n' "$*"
  else
    "$@"
  fi
}

# link-file reports a missing source and exits non-zero even under --dry-run,
# so a dry run doubles as a check that every tracked source still exists.
link_file() {
  "$LINK_FILE" $DRY_RUN_FLAG "$@"
}

link_file "$DOTFILES_DIR" "$HOME/.config/dotfiles/repo"

# `|| true` because clear exits non-zero with no TERM, which under errexit would
# abort the install when it is piped or run from a provisioning script.
$DRY_RUN || clear || true

# Layer platform Git configuration over the shared defaults.
link_file "$DOTFILES_DIR/common/git/config" "$HOME/.config/git/common"
link_file "$SCRIPT_DIR/git/config" "$HOME/.gitconfig"

# Create symbolic links for .bashrc and .vimrc
link_file "$SCRIPT_DIR/.bashrc" "$HOME/.bashrc"
link_file "$SCRIPT_DIR/.vimrc" "$HOME/.vimrc"

# bat config
run mkdir -p "$HOME/.config/bat"
link_file "$DOTFILES_DIR/common/bat/config" "$HOME/.config/bat/config"

# Ranger config
run mkdir -p "$HOME/.config/ranger"
link_file "$DOTFILES_DIR/common/ranger/rc.conf" "$HOME/.config/ranger/rc.conf"

# urlview, for the tmux URL picker on prefix + u
link_file "$DOTFILES_DIR/common/urlview/config" "$HOME/.urlview"

# Install Conda only when neither PATH nor the managed installation contains it.
if ! command -v conda &> /dev/null && [ ! -x "$HOME/miniconda3/bin/conda" ]; then
    echo "Conda is not installed. Running setup_conda.sh..."
    run bash "$SCRIPT_DIR/setup_conda.sh"
fi

# Install apt packages
run bash "$SCRIPT_DIR/install_packages.sh"

bash "$DOTFILES_DIR/common/tmux/install.sh" $DRY_RUN_FLAG

# Install the pinned Neovim binary and restore the exact LazyVim plugin revisions after system dependencies are available.
run git -C "$DOTFILES_DIR" submodule update --init --recursive lazyvim
run bash "$DOTFILES_DIR/lazyvim/install.sh"
