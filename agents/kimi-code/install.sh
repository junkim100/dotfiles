#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$DOTFILES_DIR/scripts/lib/install.sh"
install_init "Kimi Code CLI and shared integration" 3 "$@"

KIMI_INSTALLER_URL="https://code.kimi.ai/kimi-code/install.sh"
KIMI_NATIVE_DIR="$HOME/.kimi-code"
KIMI_LINK="$HOME/.local/bin/kimi"

step "Kimi Code CLI"
kimi_bin=$(command -v kimi || true)
if [[ -z $kimi_bin && -f $KIMI_LINK && -x $KIMI_LINK ]]; then
  kimi_bin="$KIMI_LINK"
fi
if [[ -z $kimi_bin && -f $KIMI_NATIVE_DIR/bin/kimi && -x $KIMI_NATIVE_DIR/bin/kimi ]]; then
  kimi_bin="$KIMI_NATIVE_DIR/bin/kimi"
fi

if [[ -n $kimi_bin ]]; then
  skip "Kimi already installed: $kimi_bin"
else
  [[ ! -e $KIMI_LINK && ! -L $KIMI_LINK ]] || die "$KIMI_LINK exists but is not executable; fix it before installing."
  kimi_bin="$KIMI_NATIVE_DIR/bin/kimi"
  [[ ! -e $kimi_bin && ! -L $kimi_bin ]] || die "$kimi_bin exists but is not executable; fix it before installing."
  if $DRY_RUN; then
    info "Would download $KIMI_INSTALLER_URL and install Kimi Code CLI into $KIMI_NATIVE_DIR without changing shell files."
  else
    make_temp_dir
    download "$KIMI_INSTALLER_URL" "$INSTALL_TEMP_DIR/kimi.sh"
    KIMI_INSTALL_DIR="$KIMI_NATIVE_DIR" KIMI_NO_MODIFY_PATH=1 bash "$INSTALL_TEMP_DIR/kimi.sh"
  fi
fi

if [[ $kimi_bin == "$KIMI_NATIVE_DIR/bin/kimi" ]] \
  || [[ $kimi_bin == "$KIMI_LINK" && -L $KIMI_LINK && $(readlink "$KIMI_LINK") == "$KIMI_NATIVE_DIR/bin/kimi" ]]; then
  link_file "$SCRIPT_DIR/kimi" "$KIMI_LINK"
  kimi_bin="$KIMI_LINK"
fi
run "$kimi_bin" --version
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) info 'Add ~/.local/bin to your shell PATH: export PATH="$HOME/.local/bin:$PATH"' ;;
esac

step "Agent instructions"
link_file "$DOTFILES_DIR/agents/AGENTS.md" "$HOME/.kimi-code/AGENTS.md"
if [[ -n ${KIMI_CODE_HOME:-} && $KIMI_CODE_HOME != "$HOME/.kimi-code" ]]; then
  link_file "$DOTFILES_DIR/agents/AGENTS.md" "$KIMI_CODE_HOME/AGENTS.md"
fi

step "Shared skills"
for skill in "$DOTFILES_DIR"/agents/skills/*/; do
  link_file "${skill%/}" "$HOME/.agents/skills/$(basename "$skill")"
done

info "Start kimi in your project and use /login to sign in with Kimi Code OAuth."
info "Kimi discovers ~/.agents/skills directly. Plugin MCP servers, hooks, and language servers require separate Kimi integration."
finish
