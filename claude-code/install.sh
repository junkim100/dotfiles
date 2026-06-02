#!/bin/bash
set -e

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p ~/.claude

# Claude Code config
ln -sf "$DOTFILES_DIR/CLAUDE.md" ~/.claude/CLAUDE.md
ln -sf "$DOTFILES_DIR/settings.json" ~/.claude/settings.json
ln -sf "$DOTFILES_DIR/statusline-command.sh" ~/.claude/statusline-command.sh

# Symlink the whole commands dir. -n avoids descending into an existing
# symlinked dir (which would create self-referencing links inside the repo).
ln -sfn "$DOTFILES_DIR/commands" ~/.claude/commands

# Install or update claude-code via native installer (auto-updates in background)
curl -fsSL https://claude.ai/install.sh | bash -s -- latest

# Add third-party marketplaces (built-in ones don't need this)
"$HOME/.local/bin/claude" plugin marketplace add uditgoenka/autoresearch
"$HOME/.local/bin/claude" plugin marketplace add openai/codex-plugin-cc
"$HOME/.local/bin/claude" plugin marketplace add Lum1104/Understand-Anything

# Install plugins
"$HOME/.local/bin/claude" plugin install pr-review-toolkit@claude-plugins-official
"$HOME/.local/bin/claude" plugin install autoresearch@autoresearch
"$HOME/.local/bin/claude" plugin install codex@openai-codex
"$HOME/.local/bin/claude" plugin install understand-anything@understand-anything
