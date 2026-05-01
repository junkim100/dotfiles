##### Basics #####
export SHELL="$(command -v zsh)"
export LANG="en_US.UTF-8"
export TERM=xterm-256color

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
# zsh-autosuggestions (Homebrew install instructions use brew prefix sourcing). [web:56]
source "$(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh"

# zsh-syntax-highlighting should be sourced at the end of ~/.zshrc. [web:72]
source "$(brew --prefix zsh-syntax-highlighting)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"

##### Oh My Posh (last line) #####
# Oh My Posh: add init as the last line to ~/.zshrc. [web:17]
eval "$(oh-my-posh init zsh --config https://raw.githubusercontent.com/junkim100/dotfiles/refs/heads/main/macOS/.ohmyposh-nord-theme.json)"


# OpenClaw Completion
# source "/Users/junkim/.openclaw/completions/openclaw.zsh"
