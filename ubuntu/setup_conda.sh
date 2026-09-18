#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$DOTFILES_DIR/scripts/lib/install.sh"
install_init "Miniconda" 2 "$@"

step "Locate or install Conda"
require_os Linux
prefix="${DOTFILES_CONDA_PREFIX:-$HOME/miniconda3}"
conda_bin="$prefix/bin/conda"
if [[ -f $conda_bin && -x $conda_bin ]]; then
  skip "Conda already installed: $conda_bin"
elif [[ -z ${DOTFILES_CONDA_PREFIX:-} ]] && command -v conda >/dev/null 2>&1; then
  conda_bin=$(command -v conda)
  skip "Conda already installed: $conda_bin"
else
  [[ ! -e $prefix && ! -L $prefix ]] || die "$prefix exists without a working Conda. Move it aside or repair it before retrying."
  case "$(uname -m)" in
    x86_64) conda_arch=x86_64 ;;
    aarch64|arm64) conda_arch=aarch64 ;;
    *) die "Unsupported Miniconda architecture: $(uname -m)" ;;
  esac
  url="https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-$conda_arch.sh"
  if $DRY_RUN; then
    info "Would download $url and install into $prefix in batch mode."
  else
    make_temp_dir
    download "$url" "$INSTALL_TEMP_DIR/miniconda.sh"
    run bash "$INSTALL_TEMP_DIR/miniconda.sh" -b -p "$prefix"
    "$conda_bin" --version
  fi
fi

step "Conda configuration"
run "$conda_bin" config --set auto_activate_base false
finish
