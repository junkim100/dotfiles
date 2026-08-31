#!/usr/bin/env bash
set -euo pipefail

LAZYVIM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NVIM_VERSION="v0.12.4"
LAZYGIT_VERSION="0.64.1"
RIPGREP_VERSION="15.2.0"
FD_VERSION="10.4.2"
PREFIX="${LAZYVIM_PREFIX:-$HOME/.local}"
BIN="$PREFIX/bin"
OS="$(uname -s)"
MACHINE="$(uname -m)"

have() { command -v "$1" >/dev/null 2>&1; }

case "$OS:$MACHINE" in
Darwin:arm64 | Darwin:aarch64)
	NVIM_PLATFORM="macos"
	NVIM_ARCH="arm64"
	NVIM_SHA256="51ab83afa66d663627c2ab1be43209b0f4e81360d4598b53efaa4d8195f24c89"
	;;
Darwin:x86_64)
	NVIM_PLATFORM="macos"
	NVIM_ARCH="x86_64"
	NVIM_SHA256="03fe16f8dd9f1e9eaf52d5e294913a39917b9e2faea30d7fb0fb385fbd36fe59"
	;;
Linux:arm64 | Linux:aarch64)
	NVIM_PLATFORM="linux"
	NVIM_ARCH="arm64"
	NVIM_SHA256="ceb7e88c6b681f0515d135dcdfad54f5eb4373b25ce6172197cd9a69c758063f"
	LG_ARCH="arm64"
	RUST_ARCH="aarch64-unknown-linux-musl"
	;;
Linux:x86_64)
	NVIM_PLATFORM="linux"
	NVIM_ARCH="x86_64"
	NVIM_SHA256="012bf3fcac5ade43914df3f174668bf64d05e049a4f032a388c027b1ebd78628"
	LG_ARCH="x86_64"
	RUST_ARCH="x86_64-unknown-linux-musl"
	;;
*)
	echo "Unsupported platform: $OS $MACHINE" >&2
	exit 1
	;;
esac

mkdir -p "$BIN" "$PREFIX/share"

for required in curl git tar; do
	if ! have "$required"; then
		echo "Missing required command: $required" >&2
		exit 1
	fi
done

verify_sha256() {
	local file="$1"
	local expected="$2"
	local actual

	if have sha256sum; then
		actual="$(sha256sum "$file" | cut -d ' ' -f 1)"
	elif have shasum; then
		actual="$(shasum -a 256 "$file" | cut -d ' ' -f 1)"
	else
		echo "Missing sha256sum or shasum; cannot verify the Neovim release." >&2
		return 1
	fi

	if [ "$actual" != "$expected" ]; then
		echo "Neovim archive checksum mismatch: expected $expected, got $actual" >&2
		return 1
	fi
}

link_config() {
	local src="$1"
	local dest="$2"

	if [ -L "$dest" ]; then
		ln -sfn "$src" "$dest"
	elif [ -e "$dest" ]; then
		local backup="${dest}.backup.$(date +%Y%m%d%H%M%S)"
		echo "$dest exists and is not a symlink; moving it to $backup"
		mv "$dest" "$backup"
		ln -s "$src" "$dest"
	else
		ln -s "$src" "$dest"
	fi
}

install_neovim() {
	local installed=""
	if [ -x "$BIN/nvim" ]; then
		installed="$("$BIN/nvim" --version | sed -n '1s/^NVIM //p')"
	fi

	if [ "$installed" = "$NVIM_VERSION" ]; then
		echo "Neovim $NVIM_VERSION already installed at $BIN/nvim"
		return
	fi

	local archive="nvim-${NVIM_PLATFORM}-${NVIM_ARCH}"
	local tarball="${archive}.tar.gz"
	local url="https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/${tarball}"
	local tmp
	tmp="$(mktemp -d)"

	echo "Installing Neovim $NVIM_VERSION for $NVIM_PLATFORM-$NVIM_ARCH into $PREFIX"
	if ! curl -fsSL "$url" -o "$tmp/$tarball"; then
		rm -rf "$tmp"
		echo "Failed to download $url" >&2
		exit 1
	fi
	if ! verify_sha256 "$tmp/$tarball" "$NVIM_SHA256"; then
		rm -rf "$tmp"
		exit 1
	fi
	if [ "$OS" = "Darwin" ] && have xattr; then
		xattr -c "$tmp/$tarball"
	fi
	tar xzf "$tmp/$tarball" -C "$tmp"
	cp -R "$tmp/$archive/." "$PREFIX/"
	rm -rf "$tmp"

	installed="$("$BIN/nvim" --version | sed -n '1s/^NVIM //p')"
	if [ "$installed" != "$NVIM_VERSION" ]; then
		echo "Installed Neovim version is $installed, expected $NVIM_VERSION" >&2
		exit 1
	fi
}

install_linux_tooling() {
	if have lazygit; then
		echo "lazygit already installed"
	else
		local url="https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_Linux_${LG_ARCH}.tar.gz"
		local tmp
		tmp="$(mktemp -d)"
		echo "Installing lazygit $LAZYGIT_VERSION"
		if curl -fsSL "$url" -o "$tmp/lazygit.tar.gz"; then
			tar xzf "$tmp/lazygit.tar.gz" -C "$tmp" lazygit
			install -m 755 "$tmp/lazygit" "$BIN/lazygit"
		else
			echo "WARNING: lazygit download failed; <space>gg will not work" >&2
		fi
		rm -rf "$tmp"
	fi

	install_rust_tool() {
		local tool="$1"
		local version="$2"
		local url="$3"
		local dirname="$4"
		if have "$tool"; then
			echo "$tool already installed"
			return
		fi
		local tmp
		tmp="$(mktemp -d)"
		echo "Installing $tool $version"
		if curl -fsSL "$url" -o "$tmp/$tool.tar.gz"; then
			tar xzf "$tmp/$tool.tar.gz" -C "$tmp"
			install -m 755 "$tmp/$dirname/$tool" "$BIN/$tool"
		else
			echo "WARNING: $tool download failed from $url" >&2
		fi
		rm -rf "$tmp"
	}

	if ! have fd && have fdfind; then
		ln -sf "$(command -v fdfind)" "$BIN/fd"
	fi

	install_rust_tool rg "$RIPGREP_VERSION" \
		"https://github.com/BurntSushi/ripgrep/releases/download/${RIPGREP_VERSION}/ripgrep-${RIPGREP_VERSION}-${RUST_ARCH}.tar.gz" \
		"ripgrep-${RIPGREP_VERSION}-${RUST_ARCH}"
	install_rust_tool fd "$FD_VERSION" \
		"https://github.com/sharkdp/fd/releases/download/v${FD_VERSION}/fd-v${FD_VERSION}-${RUST_ARCH}.tar.gz" \
		"fd-v${FD_VERSION}-${RUST_ARCH}"
}

install_macos_tooling() {
	if ! have brew; then
		echo "WARNING: Homebrew is missing; install lazygit, ripgrep, and fd manually." >&2
		return
	fi
	have lazygit || brew install lazygit
	have rg || brew install ripgrep
	have fd || brew install fd
}

install_neovim
if [ "$OS" = "Linux" ]; then
	install_linux_tooling
else
	install_macos_tooling
fi

mkdir -p "$HOME/.config"
link_config "$LAZYVIM_DIR" "$HOME/.config/nvim"
echo "Config: ~/.config/nvim -> $LAZYVIM_DIR"

missing=""
if ! have cc && ! have gcc && ! have clang; then
	missing="${missing}\n  - No C compiler. Treesitter parsers will fall back to Vim regex highlighting. Install Xcode Command Line Tools or build-essential."
fi
if ! have node; then
	missing="${missing}\n  - No Node.js. npm-based language servers and formatters will be skipped."
fi
if ! have python3; then
	missing="${missing}\n  - No Python 3. basedpyright will be skipped."
fi
if [ -n "$missing" ]; then
	echo
	echo "Missing optional dependencies:"
	printf "%b\n" "$missing"
fi

echo
echo "Restoring plugin commits from lazy-lock.json"
"$BIN/nvim" --headless "+Lazy! restore" +qa

echo "Installing available Mason language servers and formatters"
"$BIN/nvim" --headless -c "luafile $LAZYVIM_DIR/bootstrap-mason.lua"

echo
echo "Installed $("$BIN/nvim" --version | sed -n '1p') with the pinned LazyVim configuration."
case ":${PATH}:" in
*":$BIN:"*) ;;
*) echo "Add $BIN to PATH before other Neovim installations." ;;
esac
