#!/bin/bash
set -e

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p ~/.claude/commands

# Claude Code config
ln -sf "$DOTFILES_DIR/CLAUDE.md" ~/.claude/CLAUDE.md
ln -sf "$DOTFILES_DIR/settings.json" ~/.claude/settings.json
ln -sf "$DOTFILES_DIR/statusline-command.sh" ~/.claude/statusline-command.sh

if [ -d "$DOTFILES_DIR/commands" ]; then
  for cmd in "$DOTFILES_DIR/commands"/*.md; do
    [ -f "$cmd" ] && ln -sf "$cmd" ~/.claude/commands/
  done
fi

# Install or update claude-code via native installer (auto-updates in background)
curl -fsSL https://claude.ai/install.sh | bash
