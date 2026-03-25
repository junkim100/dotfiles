#!/bin/sh
set -eu
 
mkdir -p ~/.claude
 
# Claude Code config
ln -sf ~/dotfiles/claude-code/CLAUDE.md ~/.claude/CLAUDE.md
ln -sf ~/dotfiles/claude-code/settings.json ~/.claude/settings.json
ln -sf ~/dotfiles/claude-code/commands ~/.claude/commands
ln -sf ~/dotfiles/claude-code/statusline-command.sh ~/.claude/statusline-command.sh
 
# Install nvm if missing
if [ ! -f "$HOME/.nvm/nvm.sh" ]; then
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
fi
 
# Load nvm
. "$HOME/.nvm/nvm.sh"
 
# Install node if missing
if ! command -v node > /dev/null 2>&1; then
  nvm install --lts
fi
 
# Install claude-code if missing
if ! command -v claude > /dev/null 2>&1; then
  npm install -g @anthropic-ai/claude-code
fi
