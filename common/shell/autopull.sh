# Shared by ubuntu/.bashrc and macOS/.zshrc. POSIX sh, so it works in both.
# Sourced through the short bootstrap block in each rc file.

if [ -z "${DOTFILES_DIR:-}" ]; then
  if [ -d "$HOME/.config/dotfiles/repo/.git" ]; then
    export DOTFILES_DIR="$HOME/.config/dotfiles/repo"
  else
    export DOTFILES_DIR="$HOME/dotfiles"
  fi
fi

# Pulls the installed dotfiles checkout in the background when a shell starts, so a machine picks up changes made from any of the others. Deliberately timid, because this runs on every new terminal and tmux pane:
#
#   - throttled to once an hour (DOTFILES_PULL_INTERVAL, in seconds, to change it), with the timestamp written before the fetch so twenty panes opening at once do not all hit the network
#   - skipped entirely if the repo has uncommitted work, so a pull can never fight with something you are in the middle of
#   - --ff-only, so it can fast-forward but never merge or rebase behind your back
#   - GIT_TERMINAL_PROMPT=0, so a credential prompt fails instead of hanging a shell
#   - backgrounded and silenced, so a slow or missing network never delays the prompt
#
# It updates the files on disk, not the shell you are sitting in: the rc file has already been read by the time the pull lands, so changes take effect next shell.
_dotfiles_autopull() {
  local repo="$DOTFILES_DIR"
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
