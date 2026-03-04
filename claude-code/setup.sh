#!/bin/bash
set -e

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p ~/.claude/commands

ln -sf "$DOTFILES_DIR/settings.json" ~/.claude/settings.json
ln -sf "$DOTFILES_DIR/CLAUDE.md" ~/.claude/CLAUDE.md
ln -sf "$DOTFILES_DIR/dot-claude.json" ~/.claude.json

if [ -d "$DOTFILES_DIR/commands" ]; then
 for cmd in "$DOTFILES_DIR/commands"/*.md; do
 [ -f "$cmd" ] && ln -sf "$cmd" ~/.claude/commands/
 done
fi

echo "✅ Claude Code config linked!"
