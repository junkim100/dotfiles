#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$DOTFILES_DIR/scripts/lib/install.sh"
install_init "Codex and shared agent skills" 2 "$@"

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
step "Shared skills"
for skill in "$SCRIPT_DIR"/skills/*/; do
  link_file "${skill%/}" "$HOME/.agents/skills/$(basename "$skill")"
done
finish
