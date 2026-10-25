#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$DOTFILES_DIR/scripts/lib/install.sh"
install_init "Claude Code" 4 "$@"

# Only retire the link installed by this repository. Preserve independently
# authored instructions and refuse to silently discard them during migration.
legacy_instructions="$HOME/.claude/CLAUDE.md"
remove_legacy_instructions=false
if [[ -L $legacy_instructions && $(readlink "$legacy_instructions") == "$DOTFILES_DIR/claude-code/CLAUDE.md" ]]; then
  remove_legacy_instructions=true
elif [[ -e $legacy_instructions || -L $legacy_instructions ]]; then
  die "$legacy_instructions is not the old dotfiles link. Move its instructions into agents/AGENTS.md or ~/.claude/rules, then remove it and rerun."
fi

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

if $DRY_RUN; then
  info "Requires Claude Code 2.1.285 or later for native AGENTS.md configuration."
else
  version_output=$("$claude_bin" --version)
  version=${version_output%% *}
  if [[ $version =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    major=${BASH_REMATCH[1]}
    minor=${BASH_REMATCH[2]}
    patch=${BASH_REMATCH[3]}
    ((major > 2 || (major == 2 && (minor > 1 || (minor == 1 && patch >= 285))))) \
      || die "Claude Code $version is too old. Run 'claude update' and rerun; 2.1.285 or later is required."
  else
    die "Cannot determine Claude Code version from: $version_output"
  fi
fi

step "Configuration"
link_file "$DOTFILES_DIR/agents/AGENTS.md" "$HOME/.claude/rules/agents.md"
link_file "$SCRIPT_DIR/settings.json" "$HOME/.claude/settings.json"
link_file "$SCRIPT_DIR/statusline-command.sh" "$HOME/.claude/statusline-command.sh"
if $remove_legacy_instructions; then
  run rm -- "$legacy_instructions"
fi

step "Shared skills"
for skill in "$DOTFILES_DIR"/agents/skills/*/; do
  link_file "${skill%/}" "$HOME/.claude/skills/$(basename "$skill")"
done
# The old `pr` alias duplicated pr-review; remove it when it still points at the shared skill.
retired_alias="$HOME/.claude/skills/pr"
if [[ -L $retired_alias && $(readlink "$retired_alias") == "$DOTFILES_DIR/agents/skills/pr-review" ]]; then
  run rm -- "$retired_alias"
fi

info "Run agents/install.sh for the shared plugin catalog, or agents/plugins/install.sh when both CLIs are installed."
finish
