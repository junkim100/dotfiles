#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMUX_CONF_SOURCE="$SCRIPT_DIR/.tmux.conf"
TMUX_CONF_DEST="$HOME/.tmux.conf"

echo "Linking shared tmux configuration..."
ln -sfn "$TMUX_CONF_SOURCE" "$TMUX_CONF_DEST"

echo "tmux setup complete. You can now start tmux."

