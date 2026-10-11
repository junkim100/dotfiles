#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$DOTFILES_DIR/scripts/lib/install.sh"
install_init "Shared agents, Codex, and Claude Code" 5 "$@"

step "Shared skills"
for skill in "$SCRIPT_DIR"/skills/*/; do
  link_file "${skill%/}" "$HOME/.agents/skills/$(basename "$skill")"
done

step "Delegation gate"
JEV_SRC="$SCRIPT_DIR/jev-delegation"
JEV_SHARE="$HOME/.local/share/jev-delegation"
JEV_VENV="$JEV_SHARE/venv"
link_file "$JEV_SRC/jev-delegation" "$HOME/.local/bin/jev-delegation"
link_file "$JEV_SRC/ORCHESTRATION-GATE.md" "$JEV_SHARE/ORCHESTRATION-GATE.md"
link_file "$JEV_SRC/DISPATCH-SNIPPET.txt" "$JEV_SHARE/DISPATCH-SNIPPET.txt"

# Without this venv the gate still runs, but every call fails closed to FLAT.
if [[ -x $JEV_VENV/bin/python ]]; then
  skip "Delegation gate venv already present: $JEV_VENV"
elif $DRY_RUN; then
  info "Would create $JEV_VENV from $JEV_SRC/requirements.txt"
elif command -v python3 >/dev/null 2>&1; then
  info "Creating delegation gate venv at $JEV_VENV"
  python3 -m venv "$JEV_VENV"
  "$JEV_VENV/bin/python" -m pip install --quiet --upgrade pip
  "$JEV_VENV/bin/python" -m pip install --quiet -r "$JEV_SRC/requirements.txt"
else
  warn "python3 not found; jev-delegation fails closed to FLAT until $JEV_VENV exists."
fi

link_file "$JEV_SRC/jev-observe" "$HOME/.local/bin/jev-observe"

if [[ -z ${TYPESAFE_API_KEY:-} && ! -s $HOME/.config/typesafe/api_key ]]; then
  warn "No TypeSafe API key; jev-delegation fails closed to FLAT. Write one to ~/.config/typesafe/api_key or set TYPESAFE_API_KEY."
fi

step "Codex"
run_installer "$SCRIPT_DIR/codex/install.sh"

step "Claude Code"
run_installer "$SCRIPT_DIR/claude-code/install.sh"

step "Shared plugins"
run_installer "$SCRIPT_DIR/plugins/install.sh"
finish
