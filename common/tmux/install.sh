#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DOTFILES_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
LINK_FILE="$DOTFILES_DIR/scripts/link-file"
PLUGIN_DIR="$HOME/.config/tmux/plugins"
DRY_RUN=false

usage() {
  cat <<'USAGE'
Usage: common/tmux/install.sh [--dry-run]

Link the shared tmux configuration and install TPM, tmux-resurrect, and
tmux-continuum. Called by the macOS and Ubuntu installers.

Options:
  --dry-run  Print intended changes without modifying the machine.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

DRY_RUN_FLAG=""
[ "$DRY_RUN" = true ] && DRY_RUN_FLAG="--dry-run"

install_plugin() {
  repository=$1
  destination=$2

  if [ -e "$destination" ] && [ ! -d "$destination/.git" ]; then
    echo "Cannot install tmux plugin: $destination exists but is not a Git checkout." >&2
    exit 1
  fi

  if [ ! -d "$destination/.git" ]; then
    if [ "$DRY_RUN" = true ]; then
      printf '  + git clone --depth 1 %s %s\n' "$repository" "$destination"
    else
      git clone --depth 1 "$repository" "$destination"
    fi
  fi
}

"$LINK_FILE" $DRY_RUN_FLAG "$SCRIPT_DIR/tmux.conf" "$HOME/.tmux.conf"
if [ "$DRY_RUN" = true ]; then
  printf '  + mkdir -p %s\n' "$PLUGIN_DIR"
else
  mkdir -p "$PLUGIN_DIR"
fi

install_plugin https://github.com/tmux-plugins/tpm "$PLUGIN_DIR/tpm"
install_plugin https://github.com/tmux-plugins/tmux-resurrect "$PLUGIN_DIR/tmux-resurrect"
install_plugin https://github.com/tmux-plugins/tmux-continuum "$PLUGIN_DIR/tmux-continuum"

if [ "$DRY_RUN" = true ]; then
  echo "tmux configuration and persistence plugins: dry run complete."
  exit 0
fi

if command -v tmux >/dev/null 2>&1 && tmux list-sessions >/dev/null 2>&1; then
  tmux source-file "$HOME/.tmux.conf"
fi

echo "tmux configuration and persistence plugins installed."
