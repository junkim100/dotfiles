#!/usr/bin/env bash
set -euo pipefail

OMP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.omp/agent}"

case "$(uname -s)" in
  Darwin)
    if ! command -v brew > /dev/null 2>&1; then
      echo "Homebrew is required to install OMP on macOS." >&2
      exit 1
    fi
    brew install can1357/tap/omp
    ;;
  Linux)
    if ! command -v curl > /dev/null 2>&1; then
      echo "curl is required to install Bun." >&2
      exit 1
    fi
    if ! command -v unzip > /dev/null 2>&1; then
      echo "unzip is required to install Bun." >&2
      exit 1
    fi

    export BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"
    export PATH="$BUN_INSTALL/bin:$PATH"
    if ! command -v bun > /dev/null 2>&1; then
      curl -fsSL https://bun.com/install | bash
    fi
    bun install -g @oh-my-pi/pi-coding-agent
    ;;
  *)
    echo "Unsupported operating system: $(uname -s)" >&2
    exit 1
    ;;
esac

mkdir -p "$AGENT_DIR"
ln -sf "$OMP_DIR/config.yml" "$AGENT_DIR/config.yml"
ln -sf "$OMP_DIR/AGENTS.md" "$AGENT_DIR/AGENTS.md"
