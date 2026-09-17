#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LINK_FILE="$DOTFILES_DIR/scripts/link-file"
dry_run=false

case "${1:-}" in
  --dry-run)
    dry_run=true
    ;;
  "") ;;
  *)
    echo "Usage: agents/install.sh [--dry-run]" >&2
    exit 2
    ;;
esac

for skill in "$SCRIPT_DIR"/skills/*/; do
  if $dry_run; then
    "$LINK_FILE" --dry-run "${skill%/}" "$HOME/.agents/skills/$(basename "$skill")"
  else
    "$LINK_FILE" "${skill%/}" "$HOME/.agents/skills/$(basename "$skill")"
  fi
done
