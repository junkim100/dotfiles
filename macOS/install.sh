#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$DOTFILES_DIR/scripts/lib/install.sh"
install_init "macOS setup" 8 "$@"

step "Platform checks"
require_os Darwin

# This setup only supports Apple silicon. Homebrew picks its prefix from the architecture of the shell
# that runs its installer, and a shell under Rosetta reports x86_64, so an Intel Homebrew lands in
# /usr/local and every cask is then rejected as "macOS 27 on Intel" once Apple dropped Intel support.
# Refuse early rather than let that half-install happen. A dry run only reports the checks, because
# scripts/check runs it on a Linux CI host to prove every linked source exists.
if [ "$DRY_RUN" = true ]; then
  info "Requires an arm64 shell with no Intel Homebrew under /usr/local."
elif [ "$(uname -m)" != "arm64" ]; then
  cat >&2 <<MSG
This dotfiles setup only supports Apple silicon, but this shell reports $(uname -m).
If this Mac has an Apple silicon chip, the shell is running under Rosetta: run 'arch -arm64 zsh'
and try again, and untick "Open using Rosetta" on the terminal app so later shells are native too.
MSG
  exit 1
# An Intel Homebrew left over from a Rosetta terminal or Migration Assistant would shadow the native
# one and reintroduce the same failure, so refuse to continue until it is gone.
elif [ -e /usr/local/bin/brew ] || [ -d /usr/local/Homebrew ]; then
  cat >&2 <<'MSG'
An Intel Homebrew is installed under /usr/local. Remove it before running this script:
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)" -- --path=/usr/local
MSG
  exit 1
fi

# Install Homebrew if missing. Check the Apple silicon prefix directly rather than PATH so a stray
# brew elsewhere cannot make the script skip the native install.
step "Homebrew"
if [ ! -x /opt/homebrew/bin/brew ]; then
  if [ "$DRY_RUN" = true ]; then
    info "Would install Homebrew at /opt/homebrew."
  else
    make_temp_dir
    download https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh "$INSTALL_TEMP_DIR/homebrew.sh"
    run /bin/bash "$INSTALL_TEMP_DIR/homebrew.sh"
  fi
else
  skip "Homebrew already installed at /opt/homebrew"
fi

# The Homebrew installer only prints its shellenv line under "Next steps" and never runs it, so brew
# is still off PATH in this process right after installing. Load the prefix so brew bundle can run.
# The deployed .zprofile does the same thing for every later login shell.
if ! $DRY_RUN; then
  brew_env=$(/opt/homebrew/bin/brew shellenv)
  eval "$brew_env"
fi

step "Homebrew packages"
# Homebrew refuses to load casks from a third-party tap until that tap is trusted, and brew tap itself
# syntax-checks every cask in the tap under every OS and architecture, so tapping an untrusted tap fails
# with "Invalid cask (...)" for each cask and then "Cannot tap ...: invalid syntax in tap!". Trust is a
# record in ~/.homebrew/trust.json that does not need the tap to exist, so grant it first, then tap.
# A user/repo trust entry only matches a tap on its default GitHub remote (user/homebrew-repo). This
# repository is junkim100/dotfiles, a custom remote, so it must be trusted by URL or the entry never
# matches. Both commands are no-ops when repeated.
DOTFILES_TAP_URL="https://github.com/junkim100/dotfiles.git"
if [ "$DRY_RUN" = true ] || brew trust --help > /dev/null 2>&1; then
  run brew trust --tap stablyai/orca "$DOTFILES_TAP_URL"
fi
run brew tap stablyai/orca
run brew tap junkim100/dotfiles "$DOTFILES_TAP_URL"

# Avoid package upgrades as a side effect of rerunning configuration setup.
if ! $DRY_RUN && brew bundle check --no-upgrade --file="$SCRIPT_DIR/Brewfile" >/dev/null 2>&1; then
  skip "All Brewfile packages are already installed"
else
  run brew bundle install --no-upgrade --file="$SCRIPT_DIR/Brewfile"
fi

# Layer platform Git configuration over the shared defaults.
step "Shell and Git configuration"
link_file "$DOTFILES_DIR" "$HOME/.config/dotfiles/repo"
link_file "$DOTFILES_DIR/common/git/config" "$HOME/.config/git/common"
link_file "$SCRIPT_DIR/git/config" "$HOME/.gitconfig"
link_file "$SCRIPT_DIR/.zprofile" "$HOME/.zprofile"
link_file "$SCRIPT_DIR/.zshrc" "$HOME/.zshrc"
link_file "$SCRIPT_DIR/.vimrc" "$HOME/.vimrc"
step "tmux"
run_installer "$DOTFILES_DIR/common/tmux/install.sh"

# Ghostty
step "Ghostty"
run mkdir -p "$HOME/.config/ghostty/themes"
link_file "$SCRIPT_DIR/ghostty-config" "$HOME/.config/ghostty/config"
link_file "$SCRIPT_DIR/ghostty-theme-glassy-nord" "$HOME/.config/ghostty/themes/glassy-nord"
link_file "$DOTFILES_DIR/common/ghostty/themes/everforest-dark.txt" "$HOME/.config/ghostty/themes/everforest-dark.txt"
# macOS also reads (and "Open Config"/Cmd+, edits) the Application Support path
run mkdir -p "$HOME/Library/Application Support/com.mitchellh.ghostty"
link_file "$SCRIPT_DIR/ghostty-config" "$HOME/Library/Application Support/com.mitchellh.ghostty/config"

# Install the pinned Neovim binary and restore the exact LazyVim plugin revisions.
step "LazyVim"
run git -C "$DOTFILES_DIR" submodule update --init --recursive lazyvim
run bash "$DOTFILES_DIR/lazyvim/install.sh"

# Suppress the "Last login: ..." banner login(1) prints for every new login shell,
# which ghostty starts for every window and tab. The file only has to exist.
step "Terminal utilities"
run touch "$HOME/.hushlogin"

# bat
run mkdir -p "$HOME/.config/bat"
link_file "$DOTFILES_DIR/common/bat/config" "$HOME/.config/bat/config"

# Ranger
run mkdir -p "$HOME/.config/ranger"
link_file "$DOTFILES_DIR/common/ranger/rc.conf" "$HOME/.config/ranger/rc.conf"

# urlview, for the tmux URL picker on prefix + u
link_file "$DOTFILES_DIR/common/urlview/config" "$HOME/.urlview"
finish
