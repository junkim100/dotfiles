#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$DOTFILES_DIR/scripts/lib/install.sh"
install_init "Shared plugins and portable plugin skills" 5 "$@"
if ! $DRY_RUN; then require_commands python3; fi

step "Runtime dependencies"
run python3 "$SCRIPT_DIR/manage.py" dependencies

step "Pinned shared packages and links"
run python3 "$SCRIPT_DIR/manage.py" prepare
run python3 "$SCRIPT_DIR/manage.py" export

step "Claude plugins"
run python3 "$SCRIPT_DIR/manage.py" claude

step "Codex plugins"
codex_homes=("$HOME/.codex")
if [[ -n ${CODEX_HOME:-} && $CODEX_HOME != "$HOME/.codex" ]]; then
  codex_homes+=("$CODEX_HOME")
fi
orca_home="$HOME/Library/Application Support/orca/codex-runtime-home/home"
if [[ -d $orca_home && $orca_home != "${CODEX_HOME:-}" ]]; then
  codex_homes+=("$orca_home")
fi
for codex_home in "${codex_homes[@]}"; do
  run python3 "$SCRIPT_DIR/manage.py" codex --codex-home "$codex_home"
done

step "Runtime health"
run python3 "$SCRIPT_DIR/manage.py" doctor
finish
