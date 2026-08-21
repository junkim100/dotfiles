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

##### Conda (kept, silenced) #####
if [[ -n "$CONDA_PREFIX" ]] && [[ ! -d "$CONDA_PREFIX" ]]; then
  unset CONDA_PREFIX CONDA_DEFAULT_ENV
fi

__conda_setup="$("$HOME/miniconda3/bin/conda" 'shell.zsh' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
  eval "$__conda_setup" >/dev/null 2>&1
else
  if [ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]; then
    . "$HOME/miniconda3/etc/profile.d/conda.sh" >/dev/null 2>&1
  else
    export PATH="$HOME/miniconda3/bin:$PATH"
  fi
fi
unset __conda_setup

##### Homebrew Zsh plugins #####
# Guarded: sourcing a missing file makes zsh print an error on every single shell,
# which is what happens on a machine where brew bundle has not run yet.
BREW_PREFIX="${HOMEBREW_PREFIX:-$(brew --prefix)}"

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
# Pulls ~/dotfiles in the background when a shell starts, since these files get
# edited from several machines. Deliberately timid, because this runs on every new
# terminal and tmux pane:
#
#   - throttled to once an hour (DOTFILES_PULL_INTERVAL, in seconds, to change it),
#     with the timestamp written before the fetch so twenty panes opening at once
#     do not all hit the network
#   - skipped entirely if the repo has uncommitted work, so a pull can never fight
#     with something you are in the middle of
#   - --ff-only, so it can fast-forward but never merge or rebase behind your back
#   - GIT_TERMINAL_PROMPT=0, so a credential prompt fails instead of hanging a shell
#   - backgrounded and silenced, so a slow or missing network never delays the prompt
#
# It updates the files on disk, not the shell you are sitting in: this rc file has
# already been read by the time the pull lands, so changes take effect next shell.
_dotfiles_autopull() {
  # DOTFILES_DIR so the backend.ai box, which keeps the repo off $HOME, can point at it
  local repo="${DOTFILES_DIR:-$HOME/dotfiles}"
  local stamp="$HOME/.cache/dotfiles-pull"
  local interval="${DOTFILES_PULL_INTERVAL:-3600}"
  [ -d "$repo/.git" ] || return 0

  local now last
  now=$(date +%s)
  last=0
  [ -f "$stamp" ] && last=$(cat "$stamp" 2>/dev/null || echo 0)
  [ $((now - last)) -lt "$interval" ] && return 0
  mkdir -p "$(dirname "$stamp")"
  printf '%s' "$now" > "$stamp"

  git -C "$repo" diff --quiet --ignore-submodules 2>/dev/null || return 0
  git -C "$repo" diff --cached --quiet --ignore-submodules 2>/dev/null || return 0
  GIT_TERMINAL_PROMPT=0 git -C "$repo" pull --ff-only --quiet > /dev/null 2>&1
}
( _dotfiles_autopull & ) 2>/dev/null

##### Oh My Posh (last line) #####
# Oh My Posh: add init as the last line to ~/.zshrc. [web:17]
#
# The config is read from the checkout, not from raw.githubusercontent.com. Fetching it
# over the network meant every shell used whatever was on main rather than the commit
# this machine has, so editing the theme locally did nothing until it was pushed, and a
# shell with no network paid 0.3s waiting for it.
eval "$(oh-my-posh init zsh --config "$HOME/dotfiles/macOS/.ohmyposh-nord-theme.json")"
