#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LINK_FILE="$DOTFILES_DIR/scripts/link-file"

mkdir -p ~/.claude

# jq is required by statusline-command.sh (model name / token segments)
if ! command -v jq > /dev/null; then
  if command -v apt-get > /dev/null && { [ "$(id -u)" -eq 0 ] || sudo -n true 2>/dev/null; }; then
    [ "$(id -u)" -eq 0 ] && jq_sudo="" || jq_sudo="sudo"
    $jq_sudo apt-get install -y jq
  elif command -v brew > /dev/null; then
    brew install jq
  else
    echo "WARNING: jq not found and no known package manager; statusline will be incomplete" >&2
  fi
fi

# Claude Code config
"$LINK_FILE" "$SCRIPT_DIR/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
"$LINK_FILE" "$SCRIPT_DIR/settings.json" "$HOME/.claude/settings.json"
"$LINK_FILE" "$SCRIPT_DIR/statusline-command.sh" "$HOME/.claude/statusline-command.sh"

# Symlink individual skills (not the whole dir) so machine-local skills in
# ~/.claude/skills are left in place.
mkdir -p ~/.claude/skills
for skill in "$SCRIPT_DIR"/skills/*/; do
  "$LINK_FILE" "${skill%/}" "$HOME/.claude/skills/$(basename "$skill")"
done

# Install or update claude-code via native installer (auto-updates in background)
curl -fsSL https://claude.ai/install.sh | bash -s -- latest

# Add third-party marketplaces (built-in ones don't need this)
"$HOME/.local/bin/claude" plugin marketplace add uditgoenka/autoresearch
"$HOME/.local/bin/claude" plugin marketplace add Lum1104/Understand-Anything
"$HOME/.local/bin/claude" plugin marketplace add junkim100/gavel

# Install plugins, then update. `install` is a no-op once any version is present, so an explicit
# `update` is required for re-runs to pick up new plugin versions (e.g. a bumped gavel). Update is
# best-effort (|| true) so "already latest" doesn't abort the script under `set -e`.
PLUGINS=(
  autoresearch@autoresearch
  understand-anything@understand-anything
  gavel@gavel
)
for plugin in "${PLUGINS[@]}"; do
  "$HOME/.local/bin/claude" plugin install "$plugin"
  "$HOME/.local/bin/claude" plugin update "$plugin" || true
done
