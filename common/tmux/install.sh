#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$DOTFILES_DIR/scripts/lib/install.sh"
install_init "tmux configuration and plugins" 3 "$@"
PLUGIN_DIR="$HOME/.config/tmux/plugins"

install_plugin() {
  local repository=$1 destination=$2
  if [[ -d $destination/.git || -f $destination/.git ]]; then
    skip "$(basename "$destination") already installed"
  elif [[ -e $destination || -L $destination ]]; then
    die "$destination exists but is not a Git checkout. Move it aside before retrying."
  else
    run git clone --depth 1 "$repository" "$destination"
  fi
}

step "Configuration"
link_file "$SCRIPT_DIR/tmux.conf" "$HOME/.tmux.conf"

step "Persistence plugins"
if ! $DRY_RUN; then require_commands git; fi
run mkdir -p "$PLUGIN_DIR"
install_plugin https://github.com/tmux-plugins/tpm "$PLUGIN_DIR/tpm"
install_plugin https://github.com/tmux-plugins/tmux-resurrect "$PLUGIN_DIR/tmux-resurrect"
install_plugin https://github.com/tmux-plugins/tmux-continuum "$PLUGIN_DIR/tmux-continuum"

step "Reload running tmux"
if $DRY_RUN; then
  info "Would reload ~/.tmux.conf if a tmux server is running."
elif command -v tmux >/dev/null 2>&1 && tmux list-sessions >/dev/null 2>&1; then
  run tmux source-file "$HOME/.tmux.conf"
else
  skip "No running tmux server; configuration loads at next start."
fi
finish
