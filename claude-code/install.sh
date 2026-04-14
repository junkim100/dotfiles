#!/bin/sh
set -eu

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

# Install nvm if missing
if [ ! -f "$HOME/.nvm/nvm.sh" ]; then
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
fi

# Load nvm
export NVM_DIR="$HOME/.nvm"
. "$NVM_DIR/nvm.sh"

# Always install/use LTS node via nvm (avoid system node)
nvm install --lts
nvm use --lts

# Install claude-code if missing
if ! command -v claude > /dev/null 2>&1; then
  npm install -g @anthropic-ai/claude-code
fi
