#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$DOTFILES_DIR/scripts/lib/install.sh"
install_init "Backend.AI Ubuntu profile" 7 "$@"
MINICONDA_DIR="$HOME/miniconda3"
CACHE_DIR="$HOME/data00/private/junkim/.cache"

step "Platform and cache location"
require_os Linux
# Do not silently copy and delete a real cache directory, especially after a
# partial copy or when the destination already contains files with the same name.
if [[ -d $HOME/.cache && ! -L $HOME/.cache ]]; then
  die "$HOME/.cache is a real directory. Relocate its contents to $CACHE_DIR yourself before installing this profile."
fi
run mkdir -p "$CACHE_DIR"
if $DRY_RUN && [[ ! -d $CACHE_DIR ]]; then
  info "Would link $HOME/.cache to $CACHE_DIR after creating the cache directory."
else
  link_file "$CACHE_DIR" "$HOME/.cache"
fi

step "Profile configuration"
link_file "$DOTFILES_DIR" "$HOME/.config/dotfiles/repo"
link_file "$SCRIPT_DIR/.bashrc" "$HOME/.bashrc"
link_file "$DOTFILES_DIR/ubuntu/.vimrc" "$HOME/.vimrc"
link_file "$DOTFILES_DIR/common/git/config" "$HOME/.config/git/common"
link_file "$DOTFILES_DIR/ubuntu/git/config" "$HOME/.gitconfig"
link_file "$DOTFILES_DIR/common/ranger/rc.conf" "$HOME/.config/ranger/rc.conf"

step "Claude Code"
run_installer "$DOTFILES_DIR/claude-code/install.sh"

step "Conda"
DOTFILES_CONDA_PREFIX="$MINICONDA_DIR" run_installer "$DOTFILES_DIR/ubuntu/setup_conda.sh"
conda_bin="$MINICONDA_DIR/bin/conda"

step "tmux"
if command -v tmux >/dev/null 2>&1; then
  skip "tmux already available: $(command -v tmux)"
elif [[ -f $HOME/.local/bin/tmux && -x $HOME/.local/bin/tmux ]]; then
  skip "tmux already installed at ~/.local/bin/tmux"
elif [[ -x $MINICONDA_DIR/bin/tmux ]]; then
  skip "Conda tmux already installed"
  link_file "$MINICONDA_DIR/bin/tmux" "$HOME/.local/bin/tmux"
else
  # Use only conda-forge here; do not silently accept third-party channel terms.
  run "$conda_bin" install -y --override-channels -c conda-forge 'tmux=3.5a' ncurses
  if $DRY_RUN; then
    info "Would link $MINICONDA_DIR/bin/tmux to ~/.local/bin/tmux."
  else
    link_file "$MINICONDA_DIR/bin/tmux" "$HOME/.local/bin/tmux"
  fi
fi
PATH="$HOME/.local/bin:$PATH" run_installer "$DOTFILES_DIR/common/tmux/install.sh"

step "GitHub CLI"
if command -v gh >/dev/null 2>&1 && { $DRY_RUN || gh --version >/dev/null 2>&1; }; then
  skip "GitHub CLI already installed"
elif [[ -x $HOME/.local/bin/gh ]] && { $DRY_RUN || "$HOME/.local/bin/gh" --version >/dev/null 2>&1; }; then
  skip "GitHub CLI already installed at ~/.local/bin/gh"
else
  GH_VERSION="2.88.1"
  case "$(uname -m)" in
    x86_64) gh_arch=amd64 ;;
    aarch64|arm64) gh_arch=arm64 ;;
    *) die "Unsupported GitHub CLI architecture: $(uname -m)" ;;
  esac
  gh_archive="gh_${GH_VERSION}_linux_${gh_arch}"
  url="https://github.com/cli/cli/releases/download/v${GH_VERSION}/${gh_archive}.tar.gz"
  if $DRY_RUN; then
    info "Would download $url and install gh into ~/.local/bin."
  else
    require_commands tar install
    make_temp_dir
    download "$url" "$INSTALL_TEMP_DIR/gh.tar.gz"
    run tar -xzf "$INSTALL_TEMP_DIR/gh.tar.gz" -C "$INSTALL_TEMP_DIR"
    run mkdir -p "$HOME/.local/bin"
    run install -m 755 "$INSTALL_TEMP_DIR/$gh_archive/bin/gh" "$HOME/.local/bin/gh"
    "$HOME/.local/bin/gh" --version
  fi
fi

step "Ghostty terminfo"
if command -v infocmp >/dev/null 2>&1 && infocmp xterm-ghostty >/dev/null 2>&1; then
  skip "xterm-ghostty terminfo already installed"
elif $DRY_RUN; then
  info "Would compile xterm-ghostty terminfo with tic."
else
  require_commands tic
  make_temp_dir
  cat > "$INSTALL_TEMP_DIR/ghostty.terminfo" <<'TERMINFO'
xterm-ghostty|ghostty terminal emulator,
    use=xterm-256color,
TERMINFO
  run tic -x "$INSTALL_TEMP_DIR/ghostty.terminfo"
fi
finish
info "Run 'source ~/.bashrc' to apply shell changes."
