#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$DOTFILES_DIR/scripts/lib/install.sh"
install_init "Claude Code" 6 "$@"

step "Dependencies"
if command -v jq >/dev/null 2>&1; then
  skip "jq already installed"
elif $DRY_RUN; then
  info "Would install jq using Homebrew or apt (root or passwordless sudo required for apt)."
elif command -v brew >/dev/null 2>&1; then
  run brew install jq
elif command -v apt-get >/dev/null 2>&1; then
  if [[ $(id -u) -eq 0 ]]; then
    run apt-get update
    run apt-get install -y jq
  elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    run sudo -n apt-get update
    run sudo -n apt-get install -y jq
  else
    die "jq is required for the status line and plugin checks. Install jq or configure passwordless sudo, then rerun."
  fi
else
  die "jq is required. Install it with your package manager, then rerun."
fi

step "Claude Code CLI"
claude_bin=$(command -v claude || true)
if [[ -z $claude_bin && -f $HOME/.local/bin/claude && -x $HOME/.local/bin/claude ]]; then
  claude_bin="$HOME/.local/bin/claude"
fi
if [[ -n $claude_bin ]]; then
  skip "Claude Code already installed: $claude_bin"
else
  claude_bin="$HOME/.local/bin/claude"
  if $DRY_RUN; then
    info "Would download https://claude.ai/install.sh and install Claude Code (latest)."
  else
    [[ ! -d $claude_bin ]] || die "$claude_bin is a directory; move it aside first."
    make_temp_dir
    download https://claude.ai/install.sh "$INSTALL_TEMP_DIR/claude.sh"
    run bash "$INSTALL_TEMP_DIR/claude.sh" latest
    "$claude_bin" --version
  fi
fi

step "Configuration"
link_file "$SCRIPT_DIR/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
link_file "$SCRIPT_DIR/settings.json" "$HOME/.claude/settings.json"
link_file "$SCRIPT_DIR/statusline-command.sh" "$HOME/.claude/statusline-command.sh"

step "Shared skills and aliases"
for skill in "$DOTFILES_DIR"/agents/skills/*/; do
  link_file "${skill%/}" "$HOME/.claude/skills/$(basename "$skill")"
done
for skill in "$SCRIPT_DIR"/skills/*/; do
  [[ -d "$DOTFILES_DIR/agents/skills/$(basename "$skill")" ]] && continue
  link_file "$(cd "$skill" && pwd -P)" "$HOME/.claude/skills/$(basename "$skill")"
done

step "Plugin marketplaces"
marketplace_names=(understand-anything gavel)
marketplace_sources=(Lum1104/Understand-Anything junkim100/gavel)
if ! $DRY_RUN; then
  marketplaces=$("$claude_bin" plugin marketplace list --json)
  jq -e 'type == "array"' <<< "$marketplaces" >/dev/null || die "Claude returned an unexpected marketplace list; update Claude Code and retry."
fi
for i in 0 1; do
  name=${marketplace_names[$i]}
  source=${marketplace_sources[$i]}
  if $DRY_RUN; then
    info "Would add marketplace $source if $name is missing."
  elif jq -e --arg name "$name" 'any(.[]; .name == $name)' <<< "$marketplaces" >/dev/null; then
    jq -e --arg name "$name" --arg repo "$source" 'any(.[]; .name == $name and .repo == $repo)' <<< "$marketplaces" >/dev/null \
      || die "Marketplace $name already uses a different source. Check 'claude plugin marketplace list' before changing it."
    skip "Marketplace $name already configured"
  else
    run "$claude_bin" plugin marketplace add "$source"
  fi
done

step "Plugins"
if ! $DRY_RUN; then
  plugins=$("$claude_bin" plugin list --json)
  jq -e 'type == "array"' <<< "$plugins" >/dev/null || die "Claude returned an unexpected plugin list; update Claude Code and retry."
fi
for plugin in understand-anything@understand-anything gavel@gavel; do
  if $DRY_RUN; then
    info "Would install user plugin $plugin if missing."
  elif jq -e --arg id "$plugin" 'any(.[]; .id == $id and .scope == "user")' <<< "$plugins" >/dev/null; then
    skip "$plugin already installed"
  else
    run "$claude_bin" plugin install "$plugin" --scope user
  fi
done
finish
