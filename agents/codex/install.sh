#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$DOTFILES_DIR/scripts/lib/install.sh"
install_init "Codex CLI and integration" 3 "$@"

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

step "Agent instructions"
codex_homes=("$HOME/.codex")
if [[ -n ${CODEX_HOME:-} && $CODEX_HOME != "$HOME/.codex" ]]; then
  codex_homes+=("$CODEX_HOME")
fi
ORCA_CODEX_HOME_DIR="$HOME/Library/Application Support/orca/codex-runtime-home/home"
if [[ -d $ORCA_CODEX_HOME_DIR && $ORCA_CODEX_HOME_DIR != "${CODEX_HOME:-}" ]]; then
  codex_homes+=("$ORCA_CODEX_HOME_DIR")
fi
for codex_home in "${codex_homes[@]}"; do
  link_file "$DOTFILES_DIR/agents/AGENTS.md" "$codex_home/AGENTS.md"
done

# Codex and Orca own their hooks.json files, so merge only the observer entry.
step "Dispatch observer"
if $DRY_RUN; then
  info "Would register jev-observe in each Codex hooks.json"
elif command -v python3 >/dev/null 2>&1; then
  for codex_home in "${codex_homes[@]}"; do
    python3 "$DOTFILES_DIR/agents/jev-delegation/register-codex-hook.py" "$codex_home/hooks.json"
  done
else
  warn "python3 not found; Codex will not record dispatches until jev-observe is registered."
fi
finish
