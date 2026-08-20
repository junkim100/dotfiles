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

# Everything below downloads and unpacks, so check the tools that does with
# before using them. Failing here names the missing tool; failing later just
# reports a download error and sends you looking at the URL.
for required in curl tar; do
  if ! have "$required"; then
    echo "Missing $required, which this script needs to fetch anything."
    echo "  apt-get install $required"
    exit 1
  fi
done

# Symlink a path, refusing to nest inside an existing real directory.
#
# `ln -sfn src dir` on an existing REAL directory does not replace it: it creates
# src INSIDE it and returns 0. The install then reports success while the config
# was never linked, and nvim quietly loads whatever was already there.
link_config() {
  src="$1"; dest="$2"
  if [ -L "$dest" ]; then
    ln -sfn "$src" "$dest"
  elif [ -e "$dest" ]; then
    backup="${dest}.backup.$(date +%Y%m%d%H%M%S)"
    echo "  $dest already exists and is not a symlink; moving it to $backup"
    mv "$dest" "$backup"
    ln -s "$src" "$dest"
  else
    ln -s "$src" "$dest"
  fi
}

# ---------------------------------------------------------------- neovim ----
# NVIM_BIN is whichever nvim we end up using. Assuming "$BIN/nvim" is wrong when
# a matching nvim is already installed somewhere else on PATH: the download is
# skipped, then every later "$BIN/nvim" call hits a nonexistent file, plugins and
# servers never install, and the script still prints "Done" and exits 0.
NVIM_BIN=""
if have nvim && nvim --version | head -1 | grep -qF "${NVIM_VERSION#v}"; then
  echo "neovim ${NVIM_VERSION} already installed at $(command -v nvim)"
  NVIM_BIN="$(command -v nvim)"
else
  echo "Installing neovim ${NVIM_VERSION} (${NVIM_ARCH}) into ${PREFIX}..."
  tarball="nvim-linux-${NVIM_ARCH}.tar.gz"
  url="https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/${tarball}"
  tmp="$(mktemp -d)"
  if curl -fsSL "$url" -o "$tmp/$tarball"; then
    tar xzf "$tmp/$tarball" -C "$tmp"
    # The tarball unpacks to nvim-linux-<arch>/{bin,lib,share}; merge into ~/.local
    cp -R "$tmp/nvim-linux-${NVIM_ARCH}/." "$PREFIX/"
    NVIM_BIN="$BIN/nvim"
    echo "  neovim -> $NVIM_BIN"
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
link_config "$DOTFILES_DIR/nvim" "$HOME/.config/nvim"
echo "config: ~/.config/nvim -> $DOTFILES_DIR/nvim"

# -------------------------------------------------- dependency warnings ------
# These are not fatal: nvim starts either way. They decide how much of the
# config actually functions, so say so plainly rather than failing later.
missing=""

if ! have cc && ! have gcc && ! have clang; then
  missing="${missing}\n  - No C compiler. Treesitter parsers compile from source on\n    first run, so syntax highlighting will fall back to vim regex.\n    Fix: apt-get install build-essential"
fi

if ! have node; then
  missing="${missing}\n  - No node. The npm-based servers will be skipped: yaml-language-server,\n    json-lsp, bash-language-server, dockerfile-language-server,\n    markdownlint-cli2, markdown-toc. Python still gets full LSP, since\n    basedpyright is a pypi package and ruff is a standalone binary."
fi

if ! have python3; then
  missing="${missing}\n  - No python3. basedpyright is a pypi package, so go-to-definition in\n    Python will not work. This is the one that actually matters here."
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
  "$NVIM_BIN" --headless "+Lazy! restore" +qa 2>&1 | tail -3 || true
  echo "Plugins installed from lazy-lock.json"

  # Language servers. Without this they install lazily on first file open, so the
  # first real session on this box would sit there with no LSP while it downloads.
  #
  # No node check here on purpose: only some of these are npm packages, and
  # bootstrap-mason.lua decides per package from the registry. Gating the whole
  # run on node skipped the six standalone binaries and basedpyright (which is
  # pypi) along with the npm ones.
  echo "Installing language servers (up to 10 minutes on a slow link)..."
  "$NVIM_BIN" --headless -c "luafile $DOTFILES_DIR/nvim/bootstrap-mason.lua" 2>&1 | tail -4 || true
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
echo "Done. $("$NVIM_BIN" --version | head -1)"
