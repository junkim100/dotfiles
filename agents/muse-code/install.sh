#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$DOTFILES_DIR/scripts/lib/install.sh"
install_init "Muse Code and shared integration" 4 "$@"

MUSE_INSTALLER_URL="https://dev.meta.ai/install.sh"
MUSE_BIN_DIR="$HOME/.local/bin"
MUSE_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/muse"
instructions="$MUSE_CONFIG_DIR/AGENTS.md"
if [[ -e $instructions || -L $instructions ]]; then
  if [[ ! -L $instructions || $(readlink "$instructions") != "$DOTFILES_DIR/agents/AGENTS.md" ]]; then
    die "$instructions contains unmanaged instructions. Merge them into agents/AGENTS.md and move the original aside before rerunning."
  fi
fi

step "Muse Code CLI"
muse_bin=$(command -v muse || true)
if [[ -z $muse_bin && -f $MUSE_BIN_DIR/muse && -x $MUSE_BIN_DIR/muse ]]; then
  muse_bin="$MUSE_BIN_DIR/muse"
fi
if [[ -n $muse_bin ]]; then
  skip "Muse Code already installed: $muse_bin"
elif $DRY_RUN; then
  info "Would download $MUSE_INSTALLER_URL and install Muse Code into $MUSE_BIN_DIR without modifying shell profiles."
else
  [[ ! -d $MUSE_BIN_DIR/muse ]] || die "$MUSE_BIN_DIR/muse is a directory; move it aside first."
  require_commands curl
  make_temp_dir
  download "$MUSE_INSTALLER_URL" "$INSTALL_TEMP_DIR/muse.sh"
  PATH="$MUSE_BIN_DIR:$PATH" MUSE_INSTALL_DIR="$MUSE_BIN_DIR" MUSE_NO_MODIFY_PATH=1 MUSE_LOGIN=0 bash "$INSTALL_TEMP_DIR/muse.sh"
  muse_bin="$MUSE_BIN_DIR/muse"
fi
if ! $DRY_RUN; then
  MUSE_NO_AUTO_UPDATE=1 "$muse_bin" --version
fi
case ":$PATH:" in
  *":$MUSE_BIN_DIR:"*) ;;
  *) info 'Add ~/.local/bin to your shell PATH: export PATH="$HOME/.local/bin:$PATH"' ;;
esac

step "Agent instructions"
link_file "$DOTFILES_DIR/agents/AGENTS.md" "$instructions"

step "Shared skills"
for skill in "$DOTFILES_DIR"/agents/skills/*/; do
  link_file "${skill%/}" "$HOME/.agents/skills/$(basename "$skill")"
done

step "Local settings"
if $DRY_RUN; then
  info "Would merge Contributor mode off into $MUSE_CONFIG_DIR/settings.json, preserving unrelated settings (requires python3)."
else
  require_commands python3
  python3 "$SCRIPT_DIR/configure.py" "$MUSE_CONFIG_DIR/settings.json"
fi

info "Run 'muse login' to sign in with your Meta account, then 'muse' in a project. Model access depends on your account and region."
info "Muse discovers portable plugin skills in ~/.agents/skills. Native plugin, MCP, and hook adapters are not configured by this installer."
finish
