#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DOTFILES_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
LINK_FILE="$DOTFILES_DIR/scripts/link-file"
PLUGIN_DIR="$HOME/.config/tmux/plugins"

install_plugin() {
  repository=$1
  destination=$2

  if [ -e "$destination" ] && [ ! -d "$destination/.git" ]; then
    echo "Cannot install tmux plugin: $destination exists but is not a Git checkout." >&2
    exit 1
  fi

  if [ ! -d "$destination/.git" ]; then
    git clone --depth 1 "$repository" "$destination"
  fi
}

"$LINK_FILE" "$SCRIPT_DIR/tmux.conf" "$HOME/.tmux.conf"
mkdir -p "$PLUGIN_DIR"

install_plugin https://github.com/tmux-plugins/tpm "$PLUGIN_DIR/tpm"
install_plugin https://github.com/tmux-plugins/tmux-resurrect "$PLUGIN_DIR/tmux-resurrect"
install_plugin https://github.com/tmux-plugins/tmux-continuum "$PLUGIN_DIR/tmux-continuum"

if command -v tmux >/dev/null 2>&1 && tmux list-sessions >/dev/null 2>&1; then
  tmux source-file "$HOME/.tmux.conf"
fi

echo "tmux configuration and persistence plugins installed."
