#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LINK_FILE="$DOTFILES_DIR/scripts/link-file"
dry_run=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      dry_run=true
      ;;
    *)
      echo "Usage: agents/install.sh [--dry-run]" >&2
      exit 2
      ;;
  esac
  shift
done

CODEX_INSTALLER_URL="https://chatgpt.com/codex/install.sh"
CODEX_BIN_DIR="$HOME/.local/bin"

install_codex() (
  # Download completely before executing, and clean up even if installation fails.
  installer=$(mktemp)
  trap 'rm -f "$installer"' EXIT
  curl -fsSL --connect-timeout 10 --max-time 120 "$CODEX_INSTALLER_URL" -o "$installer"
  # The platform shell configs already add ~/.local/bin. Providing it here also
  # prevents the upstream installer from appending to our managed shell files.
  PATH="$CODEX_BIN_DIR:$PATH" CODEX_INSTALL_DIR="$CODEX_BIN_DIR" CODEX_NON_INTERACTIVE=1 sh "$installer"
  "$CODEX_BIN_DIR/codex" --version
)

codex_path=$(command -v codex || true)
if [[ -z $codex_path && -x $CODEX_BIN_DIR/codex ]]; then
  codex_path="$CODEX_BIN_DIR/codex"
fi

if [[ -n $codex_path ]]; then
  echo "Codex already installed: $codex_path"
elif $dry_run; then
  echo "  + download $CODEX_INSTALLER_URL and install Codex CLI into $CODEX_BIN_DIR (non-interactive)"
else
  echo "Installing Codex CLI into $CODEX_BIN_DIR"
  install_codex
fi

if [[ -z $codex_path || $codex_path == "$CODEX_BIN_DIR/codex" ]]; then
  case ":$PATH:" in
    *":$CODEX_BIN_DIR:"*) ;;
    *) echo 'Add ~/.local/bin to your shell PATH: export PATH="$HOME/.local/bin:$PATH"' ;;
  esac
fi

# Codex, Pi, and OpenCode discover this shared directory directly, including
# when an agent is installed later. No agent-specific links are needed here.
for skill in "$SCRIPT_DIR"/skills/*/; do
  if $dry_run; then
    "$LINK_FILE" --dry-run "${skill%/}" "$HOME/.agents/skills/$(basename "$skill")"
  else
    "$LINK_FILE" "${skill%/}" "$HOME/.agents/skills/$(basename "$skill")"
  fi
done
