#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TMUX_CONF_SOURCE="$DOTFILES_DIR/common/tmux/tmux.conf"
TMUX_CONF_DEST="$HOME/.tmux.conf"

echo "Linking shared tmux configuration..."
ln -sfn "$TMUX_CONF_SOURCE" "$TMUX_CONF_DEST"

echo "tmux setup complete. You can now start tmux."

