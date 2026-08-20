#!/usr/bin/env bash
# Installs the same neovim setup the Mac runs, on a box where you may not have root.
#
# Everything lands in ~/.local, so no sudo is required. apt is not used at all:
# Ubuntu ships neovim 0.6 on 22.04 and 0.9.5 on 24.04, and this config needs 0.10+
# for the built-in OSC 52 clipboard and current LSP APIs.
#
# The version is pinned so every machine runs the same neovim, matching the way
# lazy-lock.json pins every plugin. Override it for a one-off:
#   NVIM_VERSION=v0.11.0 bash setup_nvim.sh

set -eu

NVIM_VERSION="${NVIM_VERSION:-v0.12.4}"
LAZYGIT_VERSION="${LAZYGIT_VERSION:-0.64.1}"
RIPGREP_VERSION="${RIPGREP_VERSION:-15.2.0}"
FD_VERSION="${FD_VERSION:-10.4.2}"
PREFIX="$HOME/.local"
BIN="$PREFIX/bin"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"

mkdir -p "$BIN" "$PREFIX/share"

case "$(uname -m)" in
  x86_64)          NVIM_ARCH="x86_64"; LG_ARCH="x86_64"; RUST_ARCH="x86_64-unknown-linux-musl" ;;
  aarch64|arm64)   NVIM_ARCH="arm64";  LG_ARCH="arm64";  RUST_ARCH="aarch64-unknown-linux-musl" ;;
  *) echo "Unsupported architecture: $(uname -m)"; exit 1 ;;
esac

have() { command -v "$1" > /dev/null 2>&1; }

# ---------------------------------------------------------------- neovim ----
if have nvim && nvim --version | head -1 | grep -q "${NVIM_VERSION#v}"; then
  echo "neovim ${NVIM_VERSION} already installed"
else
  echo "Installing neovim ${NVIM_VERSION} (${NVIM_ARCH}) into ${PREFIX}..."
  tarball="nvim-linux-${NVIM_ARCH}.tar.gz"
  url="https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/${tarball}"
  tmp="$(mktemp -d)"
  if curl -fsSL "$url" -o "$tmp/$tarball"; then
    tar xzf "$tmp/$tarball" -C "$tmp"
    # The tarball unpacks to nvim-linux-<arch>/{bin,lib,share}; merge into ~/.local
    cp -R "$tmp/nvim-linux-${NVIM_ARCH}/." "$PREFIX/"
    echo "  neovim -> $BIN/nvim"
  else
    echo "  FAILED to download $url"
    echo "  Check the version exists, or set NVIM_VERSION to one that does."
    exit 1
  fi
  rm -rf "$tmp"
fi

# --------------------------------------------------------------- lazygit ----
# <space>gg opens this. Not in apt on older Ubuntu, so take the release binary.
if have lazygit; then
  echo "lazygit already installed"
else
  echo "Installing lazygit ${LAZYGIT_VERSION}..."
  url="https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_Linux_${LG_ARCH}.tar.gz"
  tmp="$(mktemp -d)"
  if curl -fsSL "$url" -o "$tmp/lazygit.tar.gz"; then
    tar xzf "$tmp/lazygit.tar.gz" -C "$tmp" lazygit
    install -m 755 "$tmp/lazygit" "$BIN/lazygit"
    echo "  lazygit -> $BIN/lazygit"
  else
    echo "  WARNING: lazygit download failed; <space>gg will not work"
  fi
  rm -rf "$tmp"
fi

# ------------------------------------------------------- ripgrep and fd ----
# ripgrep is not optional. snacks hardcodes `rg` for its grep source with no
# fallback, so without it <space>/ (grep the project) does not work at all.
# fd is a real but softer dependency: file finding prefers it and degrades to
# rg, then to find, each slower than the last on a tree the size of solar-system.
#
# Neither is in ubuntu/install_packages.sh, and on a box without sudo apt is not
# an option anyway, so take the static musl builds. They have no runtime deps.
install_rust_tool() {
  tool="$1"; version="$2"; url="$3"; dirname="$4"
  if have "$tool"; then
    echo "$tool already available"
    return 0
  fi
  echo "Installing $tool ${version}..."
  tmp="$(mktemp -d)"
  if curl -fsSL "$url" -o "$tmp/$tool.tar.gz"; then
    tar xzf "$tmp/$tool.tar.gz" -C "$tmp"
    if [ -f "$tmp/$dirname/$tool" ]; then
      install -m 755 "$tmp/$dirname/$tool" "$BIN/$tool"
      echo "  $tool -> $BIN/$tool"
    else
      echo "  WARNING: $tool not found inside the tarball"
    fi
  else
    echo "  WARNING: $tool download failed ($url)"
  fi
  rm -rf "$tmp"
}

# Ubuntu names its fd package binary fdfind, the same way it names bat batcat.
# Prefer linking the packaged one over downloading a second copy.
if ! have fd && have fdfind; then
  ln -sf "$(command -v fdfind)" "$BIN/fd"
  echo "  linked fdfind -> $BIN/fd"
fi

install_rust_tool rg "$RIPGREP_VERSION" \
  "https://github.com/BurntSushi/ripgrep/releases/download/${RIPGREP_VERSION}/ripgrep-${RIPGREP_VERSION}-${RUST_ARCH}.tar.gz" \
  "ripgrep-${RIPGREP_VERSION}-${RUST_ARCH}"

install_rust_tool fd "$FD_VERSION" \
  "https://github.com/sharkdp/fd/releases/download/v${FD_VERSION}/fd-v${FD_VERSION}-${RUST_ARCH}.tar.gz" \
  "fd-v${FD_VERSION}-${RUST_ARCH}"

if ! have rg && [ ! -x "$BIN/rg" ]; then
  echo "  WARNING: no ripgrep. <space>/ (grep project) will not work."
fi

# ------------------------------------------------------------- symlink ------
mkdir -p "$HOME/.config"
ln -sfn "$DOTFILES_DIR/nvim" "$HOME/.config/nvim"
echo "config: ~/.config/nvim -> $DOTFILES_DIR/nvim"

# -------------------------------------------------- dependency warnings ------
# These are not fatal: nvim starts either way. They decide how much of the
# config actually functions, so say so plainly rather than failing later.
missing=""

if ! have cc && ! have gcc && ! have clang; then
  missing="${missing}\n  - No C compiler. Treesitter parsers compile from source on\n    first run, so syntax highlighting will fall back to vim regex.\n    Fix: apt-get install build-essential"
fi

if ! have node; then
  missing="${missing}\n  - No node. These language servers are npm packages and will fail\n    to install: basedpyright, yaml-language-server, json-lsp,\n    bash-language-server, dockerfile-language-server.\n    Treesitter highlighting still works; go-to-definition will not.\n    Fix: install node, or accept a treesitter-only setup on this box."
fi

if ! have git; then
  missing="${missing}\n  - No git. lazy.nvim cannot clone plugins at all."
fi

if [ -n "$missing" ]; then
  echo
  echo "Missing optional dependencies:"
  printf "%b\n" "$missing"
fi

# ------------------------------------------------------------ bootstrap ------
# lazy.nvim clones itself and every pinned plugin, then exits. Doing it here
# means the first interactive nvim opens straight into a working editor instead
# of a progress screen.
if have git; then
  echo
  echo "Bootstrapping plugins (this takes a few minutes on a fresh box)..."
  "$BIN/nvim" --headless "+Lazy! restore" +qa 2>&1 | tail -3 || true
  echo "Plugins installed from lazy-lock.json"

  # Language servers. Without this they install lazily on first file open, so the
  # first real session on this box would sit there with no LSP while it downloads.
  if have node; then
    echo "Installing language servers (up to 10 minutes on a slow link)..."
    "$BIN/nvim" --headless -c "luafile $DOTFILES_DIR/nvim/bootstrap-mason.lua" 2>&1 | tail -2 || true
  else
    echo "Skipping language servers: no node. Treesitter highlighting still works."
  fi
fi

# ----------------------------------------------------------------- PATH ------
case ":${PATH}:" in
  *":$BIN:"*) ;;
  *)
    echo
    echo "NOTE: $BIN is not on your PATH. Add this to ~/.bashrc:"
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    ;;
esac

echo
echo "Done. nvim $("$BIN/nvim" --version | head -1 | awk '{print $2}')"
