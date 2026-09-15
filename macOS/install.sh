#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DOTFILES_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
LINK_FILE="$DOTFILES_DIR/scripts/link-file"
DRY_RUN=false

usage() {
  cat <<'USAGE'
Usage: macOS/install.sh [--dry-run]

Install the macOS configuration: Homebrew and the Brewfile, the tracked
symlinks, tmux, and LazyVim.

Options:
  --dry-run  Print intended changes without modifying the machine.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

DRY_RUN_FLAG=""
[ "$DRY_RUN" = true ] && DRY_RUN_FLAG="--dry-run"

run() {
  if [ "$DRY_RUN" = true ]; then
    printf '  + %s\n' "$*"
  else
    "$@"
  fi
}

# link-file reports a missing source and exits non-zero even under --dry-run,
# so a dry run doubles as a check that every tracked source still exists.
link_file() {
  "$LINK_FILE" $DRY_RUN_FLAG "$@"
}

link_file "$DOTFILES_DIR" "$HOME/.config/dotfiles/repo"

# Install Homebrew if missing
if ! command -v brew > /dev/null 2>&1; then
  if [ "$DRY_RUN" = true ]; then
    echo "  + install Homebrew"
  else
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
fi

# The Homebrew installer only prints its shellenv line under "Next steps" and never runs it, so brew
# is still off PATH in this process right after installing. Load the prefix so brew bundle can run.
# The deployed .zprofile does the same thing for every later login shell.
if ! command -v brew > /dev/null 2>&1; then
  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [ -x "$candidate" ]; then
      eval "$("$candidate" shellenv)"
      break
    fi
  done
fi

# Homebrew refuses to load casks from a third-party tap until that tap is trusted, and it only accepts
# trust for a tap that already exists, so tap and trust before brew bundle. Left to brew bundle alone,
# the tap would be added and its casks refused in the same pass. Both commands are no-ops when repeated.
run brew tap stablyai/orca
run brew tap junkim100/dotfiles https://github.com/junkim100/dotfiles.git
if [ "$DRY_RUN" = true ] || brew trust --help > /dev/null 2>&1; then
  run brew trust --tap stablyai/orca junkim100/dotfiles
fi

# Install everything from Brewfile
run brew bundle install --file="$SCRIPT_DIR/Brewfile"

# Layer platform Git configuration over the shared defaults.
link_file "$DOTFILES_DIR/common/git/config" "$HOME/.config/git/common"
link_file "$SCRIPT_DIR/git/config" "$HOME/.gitconfig"
link_file "$SCRIPT_DIR/.zprofile" "$HOME/.zprofile"
link_file "$SCRIPT_DIR/.zshrc" "$HOME/.zshrc"
link_file "$SCRIPT_DIR/.vimrc" "$HOME/.vimrc"
sh "$DOTFILES_DIR/common/tmux/install.sh" $DRY_RUN_FLAG

# Ghostty
run mkdir -p "$HOME/.config/ghostty/themes"
link_file "$SCRIPT_DIR/ghostty-config" "$HOME/.config/ghostty/config"
link_file "$SCRIPT_DIR/ghostty-theme-glassy-nord" "$HOME/.config/ghostty/themes/glassy-nord"
link_file "$DOTFILES_DIR/common/ghostty/themes/everforest-dark.txt" "$HOME/.config/ghostty/themes/everforest-dark.txt"
# macOS also reads (and "Open Config"/Cmd+, edits) the Application Support path
run mkdir -p "$HOME/Library/Application Support/com.mitchellh.ghostty"
link_file "$SCRIPT_DIR/ghostty-config" "$HOME/Library/Application Support/com.mitchellh.ghostty/config"

# Install the pinned Neovim binary and restore the exact LazyVim plugin revisions.
run git -C "$DOTFILES_DIR" submodule update --init --recursive lazyvim
run bash "$DOTFILES_DIR/lazyvim/install.sh"

# Suppress the "Last login: ..." banner login(1) prints for every new login shell,
# which ghostty starts for every window and tab. The file only has to exist.
run touch "$HOME/.hushlogin"

# bat
run mkdir -p "$HOME/.config/bat"
link_file "$DOTFILES_DIR/common/bat/config" "$HOME/.config/bat/config"

# Ranger
run mkdir -p "$HOME/.config/ranger"
link_file "$DOTFILES_DIR/common/ranger/rc.conf" "$HOME/.config/ranger/rc.conf"

# urlview, for the tmux URL picker on prefix + u
link_file "$DOTFILES_DIR/common/urlview/config" "$HOME/.urlview"
