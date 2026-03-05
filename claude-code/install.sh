#!/bin/sh
set -eu

# Claude Code config
ln -sf ~/dotfiles/claude-code/CLAUDE.md ~/.claude/CLAUDE.md
ln -sf ~/dotfiles/claude-code/settings.json ~/.claude/settings.json

# Install claude-code if missing
if ! command -v claude > /dev/null 2>&1; then
  npm install -g @anthropic-ai/claude-code
fi
