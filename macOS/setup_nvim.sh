#!/usr/bin/env bash
# Installs just the neovim setup on macOS, without running the rest of install.sh.
#
#   bash ~/dotfiles/macOS/setup_nvim.sh
#
# install.sh calls this too, so there is one implementation rather than two.
# The Ubuntu equivalent is ubuntu/setup_nvim.sh, which has more work to do: apt's
# neovim is too old, so it fetches release tarballs into ~/.local. Here Homebrew
# handles that, and the shared part is the symlink plus the two bootstraps.

set -eu

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"

have() { command -v "$1" > /dev/null 2>&1; }

# ------------------------------------------------------------------ tools ----
# ripgrep is not optional: snacks hardcodes `rg` for its grep source with no
# fallback, so <leader>/ does nothing without it. fd is softer -- file finding
# prefers it and degrades to rg, then find.
if have brew; then
  for pkg in neovim lazygit ripgrep fd; do
    if brew list --formula "$pkg" > /dev/null 2>&1; then
      echo "$pkg already installed"
    else
      echo "Installing $pkg..."
      brew install "$pkg"
    fi
  done
else
  echo "Homebrew not found. Install it first, or install neovim, lazygit,"
  echo "ripgrep, and fd by hand."
fi

if ! have nvim; then
  echo "nvim is still not on PATH; cannot continue."
  exit 1
fi

# ---------------------------------------------------------------- symlink ----
# Not `ln -sfn`: against an existing REAL directory that creates the link INSIDE
# it and returns 0, so the install looks fine while the config was never linked.
mkdir -p "$HOME/.config"
dest="$HOME/.config/nvim"
if [ -L "$dest" ]; then
  ln -sfn "$DOTFILES_DIR/nvim" "$dest"
elif [ -e "$dest" ]; then
  backup="${dest}.backup.$(date +%Y%m%d%H%M%S)"
  echo "$dest exists and is not a symlink; moving it to $backup"
  mv "$dest" "$backup"
  ln -s "$DOTFILES_DIR/nvim" "$dest"
else
  ln -s "$DOTFILES_DIR/nvim" "$dest"
fi
echo "config: $dest -> $DOTFILES_DIR/nvim"

# -------------------------------------------------------------- bootstrap ----
# `restore` rather than `sync`: it installs the exact commits in lazy-lock.json,
# where sync would take latest and quietly defeat the point of committing it.
echo "Restoring plugins from lazy-lock.json..."
nvim --headless "+Lazy! restore" +qa 2> /dev/null || true

# Language servers. Without this mason installs them lazily on first file open,
# so the first real session sits there with no LSP while things download.
echo "Installing language servers..."
nvim --headless -c "luafile $DOTFILES_DIR/nvim/bootstrap-mason.lua" 2>&1 | tail -4 || true

echo
echo "Done. $(nvim --version | head -1)"
