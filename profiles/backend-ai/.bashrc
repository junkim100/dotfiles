export PATH="$HOME/.local/bin:$PATH"

PROFILE_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
export DOTFILES_DIR="$(cd "$PROFILE_DIR/../.." && pwd)"
unset PROFILE_DIR

source "$DOTFILES_DIR/ubuntu/.bashrc"

cd "$HOME/data00/private/junkim/"
