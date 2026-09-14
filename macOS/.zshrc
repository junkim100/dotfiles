##### Basics #####
export SHELL="$(command -v zsh)"
export LANG="en_US.UTF-8"

# History (simple, sane defaults)
HISTFILE="$HOME/.zsh_history"
HISTSIZE=10000
SAVEHIST=10000
setopt HIST_IGNORE_DUPS HIST_REDUCE_BLANKS SHARE_HISTORY

# Completion
autoload -Uz compinit
compinit

##### Keybindings #####
bindkey -e

#Command Backspace
bindkey '^U' backward-kill-line

# Option + Left/Right
bindkey '\e\e[D' backward-word
bindkey '\e\e[C' forward-word

# Command + Left/Right (Home/End style)
bindkey '^[[H' beginning-of-line
bindkey '^[[F' end-of-line

##### Aliases #####
alias ll='ls -lA'
alias claudeyolo='clear && claude --dangerously-skip-permissions'

##### NVM #####
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" >/dev/null 2>&1
[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion" >/dev/null 2>&1

##### Local env script (optional) #####
[[ -f "$HOME/.local/bin/env" ]] && . "$HOME/.local/bin/env" >/dev/null 2>&1

##### Homebrew Zsh plugins #####
# Guarded: sourcing a missing file makes zsh print an error on every single shell,
# which is what happens on a machine where brew bundle has not run yet.
# brew itself can be missing too, and calling it unconditionally prints a command-not-found on
# every shell. HOMEBREW_PREFIX is already exported by the shellenv line in .zprofile.
BREW_PREFIX="${HOMEBREW_PREFIX:-}"
if [[ -z "$BREW_PREFIX" ]] && command -v brew > /dev/null 2>&1; then
  BREW_PREFIX="$(brew --prefix)"
fi

# zsh-autosuggestions (Homebrew install instructions use brew prefix sourcing). [web:56]
[[ -r "$BREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] \
  && source "$BREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh"

# zsh-syntax-highlighting should be sourced at the end of ~/.zshrc. [web:72]
[[ -r "$BREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]] \
  && source "$BREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
unset BREW_PREFIX

##### Editor #####
# Without this, `git commit` with no -m, `git rebase -i`, and anything else that opens
# $EDITOR gets plain vim rather than the neovim setup this repo configures.
if command -v nvim > /dev/null 2>&1; then
  export EDITOR="nvim"
  export VISUAL="nvim"
fi

export PATH="$HOME/.local/bin:$PATH"

##### dotfiles auto-update #####
# Locate the checkout, then hand off to the shared implementation in common/shell/.
for _d in "${DOTFILES_DIR:-}" "$HOME/.config/dotfiles/repo" "$HOME/dotfiles"; do
  [ -n "$_d" ] && [ -r "$_d/common/shell/autopull.sh" ] && { . "$_d/common/shell/autopull.sh"; break; }
done
unset _d

##### Oh My Posh (last line) #####
# Oh My Posh: add init as the last line to ~/.zshrc. [web:17]
#
# The config is read from the checkout, not from raw.githubusercontent.com. Fetching it
# over the network meant every shell used whatever was on main rather than the commit
# this machine has, so editing the theme locally did nothing until it was pushed, and a
# shell with no network paid 0.3s waiting for it.
# Guarded for the same reason as the plugins above: on a fresh machine this runs before
# brew bundle has installed oh-my-posh, and an unguarded call errors on every shell.
if command -v oh-my-posh > /dev/null 2>&1; then
  eval "$(oh-my-posh init zsh --config "$DOTFILES_DIR/macOS/.ohmyposh-nord-theme.json")"
fi
