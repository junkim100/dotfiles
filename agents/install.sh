#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$DOTFILES_DIR/scripts/lib/install.sh"
install_init "Codex, agent instructions, and shared skills" 4 "$@"

CODEX_INSTALLER_URL="https://chatgpt.com/codex/install.sh"
CODEX_BIN_DIR="$HOME/.local/bin"

install_codex() {
  make_temp_dir
  download "$CODEX_INSTALLER_URL" "$INSTALL_TEMP_DIR/codex.sh"
  # The platform shell configs already add ~/.local/bin. Providing it here also
  # prevents the upstream installer from appending to our managed shell files.
  PATH="$CODEX_BIN_DIR:$PATH" CODEX_INSTALL_DIR="$CODEX_BIN_DIR" CODEX_NON_INTERACTIVE=1 sh "$INSTALL_TEMP_DIR/codex.sh"
  "$CODEX_BIN_DIR/codex" --version
}

step "Codex CLI"
codex_path=$(command -v codex || true)
if [[ -z $codex_path && -f $CODEX_BIN_DIR/codex && -x $CODEX_BIN_DIR/codex ]]; then
  codex_path="$CODEX_BIN_DIR/codex"
fi

if [[ -n $codex_path ]]; then
  skip "Codex already installed: $codex_path"
elif $DRY_RUN; then
  info "Would download $CODEX_INSTALLER_URL and install Codex CLI into $CODEX_BIN_DIR (non-interactive)."
else
  [[ ! -d $CODEX_BIN_DIR/codex ]] || die "$CODEX_BIN_DIR/codex is a directory; move it aside first."
  info "Installing Codex CLI into $CODEX_BIN_DIR"
  install_codex
fi

if [[ -z $codex_path || $codex_path == "$CODEX_BIN_DIR/codex" ]]; then
  case ":$PATH:" in
    *":$CODEX_BIN_DIR:"*) ;;
    *) info 'Add ~/.local/bin to your shell PATH: export PATH="$HOME/.local/bin:$PATH"' ;;
  esac
fi

# Codex, Pi, and OpenCode discover this shared directory directly, including
# when an agent is installed later. No agent-specific links are needed here.
step "Agent instructions"
link_file "$SCRIPT_DIR/AGENTS.md" "$HOME/.codex/AGENTS.md"
# Orca points CODEX_HOME at a managed home, so its Codex workers read a different
# global AGENTS.md than a plain terminal does. Link both when Orca is installed.
ORCA_CODEX_HOME_DIR="$HOME/Library/Application Support/orca/codex-runtime-home/home"
if [[ -d $ORCA_CODEX_HOME_DIR ]]; then
  link_file "$SCRIPT_DIR/AGENTS.md" "$ORCA_CODEX_HOME_DIR/AGENTS.md"
else
  skip "Orca managed Codex home not present: $ORCA_CODEX_HOME_DIR"
fi

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

if [[ -z ${TYPESAFE_API_KEY:-} && ! -s $HOME/.config/typesafe/api_key ]]; then
  warn "No TypeSafe API key; jev-delegation fails closed to FLAT. Write one to ~/.config/typesafe/api_key or set TYPESAFE_API_KEY."
fi

step "Shared skills"
for skill in "$SCRIPT_DIR"/skills/*/; do
  link_file "${skill%/}" "$HOME/.agents/skills/$(basename "$skill")"
done
finish
