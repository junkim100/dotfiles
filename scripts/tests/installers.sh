#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
fail() { echo "installer check failed: $*" >&2; exit 1; }

# Exercise Codex installation with isolated tools and a fake download, never the
# network or a real package installation, even on a machine without Codex.
agent_bin="$TEMP_DIR/agent-bin"
agent_home="$TEMP_DIR/agent-home"
mkdir -p "$agent_bin" "$agent_home"
for tool in bash sh dirname basename mkdir readlink ln rm mktemp cat chmod; do
  ln -s "$(command -v "$tool")" "$agent_bin/$tool"
done

# A failed command inside a function must stop immediately, preserve its exit
# status, identify the stage, and clean its private download directory.
status=0
bash -c '
  set -Eeuo pipefail
  DOTFILES_DIR=$1
  . "$DOTFILES_DIR/scripts/lib/install.sh"
  install_init "Failure probe" 2
  step "Download probe"
  make_temp_dir
  printf "%s" "$INSTALL_TEMP_DIR" > "$2"
  run sh -c "exit 7"
  step "Must not run"
  finish
' _ "$DOTFILES_DIR" "$TEMP_DIR/cleanup-path" > "$TEMP_DIR/failure.log" 2>&1 || status=$?
[[ $status -eq 7 ]] || fail "shared runner swallowed a failing command"
grep -q '\[FAIL\].*Download probe.*exit 7' "$TEMP_DIR/failure.log" || fail "failure lacks stage and exit status"
! grep -q 'Must not run\|100%' "$TEMP_DIR/failure.log" || fail "failed installer reported success"
[[ ! -e $(cat "$TEMP_DIR/cleanup-path") ]] || fail "failed installer leaked its temporary directory"

# These commands must never execute in a preview, including nested installers.
preview_bin="$TEMP_DIR/preview-bin"
mkdir -p "$preview_bin"
for tool in curl wget brew apt-get sudo git claude gh conda nvitop uv pipx tmux tic; do
  cat > "$preview_bin/$tool" <<'FORBIDDEN'
#!/bin/sh
printf 'unexpected command\n' >> "$HOME/unexpected-command"
exit 97
FORBIDDEN
  chmod +x "$preview_bin/$tool"
done
installers=(macOS/install.sh ubuntu/install.sh agents/install.sh claude-code/install.sh common/tmux/install.sh ubuntu/install_packages.sh ubuntu/setup_conda.sh profiles/backend-ai/install.sh)
for installer in "${installers[@]}"; do
  preview_home=$(mktemp -d "$TEMP_DIR/preview-XXXXXX")
  HOME="$preview_home" PATH="$preview_bin:$PATH" NO_COLOR=1 bash "$DOTFILES_DIR/$installer" --dry-run > "$TEMP_DIR/preview.log" 2>&1 \
    || { cat "$TEMP_DIR/preview.log"; fail "$installer failed a guarded dry run"; }
  [[ -z $(find "$preview_home" -mindepth 1) ]] || fail "$installer executed a command or wrote files in a preview"
  grep -q '100%.*preview complete' "$TEMP_DIR/preview.log" || fail "$installer did not finish its preview"
  if grep -q $'\033' "$TEMP_DIR/preview.log"; then fail "$installer emitted ANSI colors into plain logs"; fi
  HOME="$preview_home" bash "$DOTFILES_DIR/$installer" --help >/dev/null || fail "$installer --help failed"
  if HOME="$preview_home" bash "$DOTFILES_DIR/$installer" --dry-run --unknown >/dev/null 2>&1; then
    fail "$installer ignored an unknown argument"
  fi
  [[ -z $(find "$preview_home" -mindepth 1) ]] || fail "$installer changed files while parsing arguments"
done

# Never replace a real cache directory or overwrite a partial Conda install.
conflict_home="$TEMP_DIR/conflicts"
mkdir -p "$conflict_home/.cache" "$conflict_home/miniconda3"
printf 'preserve me\n' > "$conflict_home/.cache/keep"
if HOME="$conflict_home" bash "$DOTFILES_DIR/profiles/backend-ai/install.sh" --dry-run > "$TEMP_DIR/conflict.log" 2>&1; then
  fail "Backend.AI would silently replace a real cache directory"
fi
[[ $(cat "$conflict_home/.cache/keep") == 'preserve me' ]] || fail "Backend.AI changed existing cache contents"
if HOME="$conflict_home" DOTFILES_CONDA_PREFIX="$conflict_home/miniconda3" bash "$DOTFILES_DIR/ubuntu/setup_conda.sh" --dry-run > "$TEMP_DIR/conflict.log" 2>&1; then
  fail "Conda would overwrite a partial installation"
fi
cat > "$agent_bin/curl" <<'CURL'
#!/usr/bin/env bash
set -euo pipefail
printf 'download\n' >> "$HOME/downloads"
cat > "${!#}" <<'INSTALLER'
#!/bin/sh
set -eu
printf 'installed\n' >> "$HOME/installer-ran"
[ "$CODEX_NON_INTERACTIVE" = 1 ]
[ "$CODEX_INSTALL_DIR" = "$HOME/.local/bin" ]
case ":$PATH:" in
  *":$CODEX_INSTALL_DIR:"*) ;;
  *) exit 1 ;;
esac
[ "${MOCK_INSTALL_EXIT:-0}" = 0 ] || exit "$MOCK_INSTALL_EXIT"
mkdir -p "$CODEX_INSTALL_DIR"
printf '#!/bin/sh\nprintf "codex-cli test\\n"\n' > "$CODEX_INSTALL_DIR/codex"
chmod +x "$CODEX_INSTALL_DIR/codex"
INSTALLER
exit "${MOCK_CURL_EXIT:-0}"
CURL
chmod +x "$agent_bin/curl"

HOME="$agent_home" PATH="$agent_bin" bash "$DOTFILES_DIR/agents/install.sh" --dry-run > "$TEMP_DIR/agent.log" 2>&1 \
  || { cat "$TEMP_DIR/agent.log"; fail "agent dry-run failed without Codex"; }
[[ -z $(find "$agent_home" -mindepth 1) ]] || fail "agent dry-run downloaded or changed files"
grep -q 'install Codex CLI' "$TEMP_DIR/agent.log" || fail "agent dry-run did not preview Codex installation"
if HOME="$agent_home" PATH="$agent_bin" bash "$DOTFILES_DIR/agents/install.sh" --dry-run --unknown > "$TEMP_DIR/agent.log" 2>&1; then
  fail "agent installer accepted an unknown extra argument"
fi

mkdir -p "$agent_home/.agents/skills/local-skill"
printf 'local skill\n' > "$agent_home/.agents/skills/local-skill/SKILL.md"
for attempt in 1 2; do
  HOME="$agent_home" PATH="$agent_bin" bash "$DOTFILES_DIR/agents/install.sh" > "$TEMP_DIR/agent.log" 2>&1 \
    || { cat "$TEMP_DIR/agent.log"; fail "agent installation attempt $attempt failed"; }
done
[[ -x $agent_home/.local/bin/codex ]] || fail "Codex was not installed"
[[ $(cat "$agent_home/downloads") == download ]] || fail "agent installer downloaded again on rerun"
[[ $(cat "$agent_home/installer-ran") == installed ]] || fail "agent installer reinstalled Codex on rerun"
[[ $(cat "$agent_home/.agents/skills/local-skill/SKILL.md") == 'local skill' ]] || fail "agent installer changed a local skill"
for skill in "$DOTFILES_DIR"/agents/skills/*/; do
  [[ $(readlink "$agent_home/.agents/skills/$(basename "$skill")") == "${skill%/}" ]] \
    || fail "agent installer did not link $skill"
done

existing_home="$TEMP_DIR/agent-existing"
mkdir -p "$existing_home"
HOME="$existing_home" PATH="$agent_home/.local/bin:$agent_bin" bash "$DOTFILES_DIR/agents/install.sh" > "$TEMP_DIR/agent.log" 2>&1 \
  || { cat "$TEMP_DIR/agent.log"; fail "agent installation failed with Codex on PATH"; }
[[ ! -e $existing_home/downloads && ! -e $existing_home/.local ]] || fail "agent installer replaced an existing Codex"

for failure in download install; do
  failed_home="$TEMP_DIR/agent-failed-$failure"
  mkdir -p "$failed_home"
  curl_exit=0
  install_exit=0
  if [[ $failure == download ]]; then curl_exit=22; else install_exit=42; fi
  if HOME="$failed_home" PATH="$agent_bin" MOCK_CURL_EXIT="$curl_exit" MOCK_INSTALL_EXIT="$install_exit" \
    bash "$DOTFILES_DIR/agents/install.sh" > "$TEMP_DIR/agent.log" 2>&1; then
    fail "agent installer ignored a Codex $failure failure"
  fi
  [[ ! -e $failed_home/.local/bin/codex ]] || fail "Codex was installed after a $failure failure"
  if [[ $failure == download ]]; then
    [[ ! -e $failed_home/installer-ran ]] || fail "agent installer executed an incomplete download"
  fi
done

# Package reruns must avoid apt entirely when satisfied, and fail immediately
# when apt fails. No host package manager is reachable from this PATH.
package_bin="$TEMP_DIR/package-bin"
package_home="$TEMP_DIR/package-home"
mkdir -p "$package_bin" "$package_home"
cat > "$package_bin/uname" <<'UNAME'
#!/bin/sh
case "$1" in -s) echo Linux ;; -m) echo x86_64 ;; esac
UNAME
cat > "$package_bin/dpkg-query" <<'DPKG'
#!/bin/sh
if [ "${TEST_MISSING_PACKAGE:-0}" = 1 ]; then exit 1; fi
printf 'install ok installed'
DPKG
cat > "$package_bin/id" <<'ID'
#!/bin/sh
echo "${TEST_USER_ID:-0}"
ID
cat > "$package_bin/apt-get" <<'APT'
#!/bin/sh
printf '%s\n' "$*" >> "$HOME/apt-calls"
exit "${TEST_APT_EXIT:-0}"
APT
for tool in bat nvitop; do
  printf '#!/bin/sh\nexit 0\n' > "$package_bin/$tool"
done
chmod +x "$package_bin"/*
HOME="$package_home" PATH="$package_bin:$agent_bin" bash "$DOTFILES_DIR/ubuntu/install_packages.sh" > "$TEMP_DIR/packages.log" 2>&1 \
  || { cat "$TEMP_DIR/packages.log"; fail "already-installed package check failed"; }
[[ ! -e $package_home/apt-calls ]] || fail "package rerun invoked apt unnecessarily"
status=0
HOME="$package_home" PATH="$package_bin:$agent_bin" TEST_MISSING_PACKAGE=1 TEST_APT_EXIT=42 \
  bash "$DOTFILES_DIR/ubuntu/install_packages.sh" > "$TEMP_DIR/packages.log" 2>&1 || status=$?
[[ $status -eq 42 ]] || fail "package installer swallowed apt failure"
[[ $(cat "$package_home/apt-calls") == update ]] || fail "package installer continued after failed apt update"
grep -q '\[FAIL\].*System packages' "$TEMP_DIR/packages.log" || fail "package failure lacks context"

unprivileged_home="$TEMP_DIR/unprivileged-home"
mkdir -p "$unprivileged_home"
HOME="$unprivileged_home" PATH="$package_bin:$agent_bin" TEST_MISSING_PACKAGE=1 TEST_USER_ID=1000 \
  bash "$DOTFILES_DIR/ubuntu/install_packages.sh" > "$TEMP_DIR/packages.log" 2>&1 \
  || { cat "$TEMP_DIR/packages.log"; fail "missing sudo prevented optional package handling"; }
[[ ! -e $unprivileged_home/apt-calls ]] || fail "unprivileged installer attempted apt without sudo"
grep -q '\[WARN\].*No passwordless sudo' "$TEMP_DIR/packages.log" || fail "unprivileged installer silently skipped missing packages"

conda_home="$TEMP_DIR/conda-home"
mkdir -p "$conda_home/miniconda3/bin"
cat > "$conda_home/miniconda3/bin/conda" <<'CONDA'
#!/bin/sh
[ "$*" = 'config --set auto_activate_base false' ] || exit 91
CONDA
chmod +x "$conda_home/miniconda3/bin/conda"
HOME="$conda_home" PATH="$package_bin:$agent_bin" bash "$DOTFILES_DIR/ubuntu/setup_conda.sh" > "$TEMP_DIR/conda.log" 2>&1 \
  || { cat "$TEMP_DIR/conda.log"; fail "existing managed Conda was not reused"; }
[[ ! -e $conda_home/downloads ]] || fail "existing Conda was downloaded again"

# Use the real JSON parser with a fake Claude CLI, so duplicate marketplace and
# plugin detection is tested against the actual command output format.
if command -v jq >/dev/null 2>&1; then
  claude_bin="$TEMP_DIR/claude-bin"
  claude_home="$TEMP_DIR/claude-home"
  mkdir -p "$claude_bin" "$claude_home"
  ln -s "$(command -v jq)" "$claude_bin/jq"
  cat > "$claude_bin/claude" <<'CLAUDE'
#!/bin/sh
case "$*" in
  'plugin marketplace list --json')
    cat <<'JSON'
[{"name":"autoresearch","repo":"uditgoenka/autoresearch"},{"name":"understand-anything","repo":"Lum1104/Understand-Anything"},{"name":"gavel","repo":"junkim100/gavel"}]
JSON
    ;;
  'plugin list --json')
    if [ "${TEST_MISSING_PLUGINS:-0}" = 1 ]; then echo '[]'; else
      cat <<'JSON'
[{"id":"autoresearch@autoresearch","scope":"user"},{"id":"understand-anything@understand-anything","scope":"user"},{"id":"gavel@gavel","scope":"user"}]
JSON
    fi
    ;;
  *)
    printf '%s\n' "$*" >> "$HOME/claude-mutations"
    exit "${TEST_PLUGIN_EXIT:-91}"
    ;;
esac
CLAUDE
  chmod +x "$claude_bin/claude"
  for attempt in 1 2; do
    HOME="$claude_home" PATH="$claude_bin:$agent_bin" bash "$DOTFILES_DIR/claude-code/install.sh" > "$TEMP_DIR/claude.log" 2>&1 \
      || { cat "$TEMP_DIR/claude.log"; fail "Claude rerun failed on existing plugins"; }
  done
  [[ ! -e $claude_home/claude-mutations && ! -e $claude_home/downloads ]] || fail "Claude installer reinstalled existing tools or plugins"
  [[ $(readlink "$claude_home/.claude/skills/pr") == "$DOTFILES_DIR/agents/skills/pr-review" ]] || fail "Claude compatibility alias is incorrect"
  status=0
  HOME="$claude_home" PATH="$claude_bin:$agent_bin" TEST_MISSING_PLUGINS=1 TEST_PLUGIN_EXIT=42 \
    bash "$DOTFILES_DIR/claude-code/install.sh" > "$TEMP_DIR/claude.log" 2>&1 || status=$?
  [[ $status -eq 42 ]] || fail "Claude installer ignored a plugin failure"
  grep -q '\[FAIL\].*Plugins' "$TEMP_DIR/claude.log" || fail "Claude plugin failure lacks context"
else
  echo 'installer checks: jq unavailable; skipping Claude JSON integration checks'
fi

echo 'installer checks passed'
