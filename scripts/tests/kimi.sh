#!/usr/bin/env bash
set -euo pipefail

unset KIMI_CODE_HOME KIMI_INSTALL_DIR KIMI_VERSION
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
fail() { echo "Kimi installer check failed: $*" >&2; exit 1; }

# Only fixture tools are reachable; these tests cannot install packages or make network requests.
test_bin="$TEMP_DIR/bin"
mkdir -p "$test_bin"
for tool in bash dirname basename mkdir readlink ln rm mktemp cat chmod; do
  ln -s "$(command -v "$tool")" "$test_bin/$tool"
done
cat > "$test_bin/curl" <<'CURL'
#!/usr/bin/env bash
set -euo pipefail
printf 'download\n' >> "$HOME/downloads"
cat > "${!#}" <<'INSTALLER'
#!/usr/bin/env bash
set -euo pipefail
printf 'installed\n' >> "$HOME/installer-ran"
[[ $KIMI_NO_MODIFY_PATH == 1 ]]
[[ $KIMI_INSTALL_DIR == "$HOME/.kimi-code" ]]
[[ ${MOCK_INSTALL_EXIT:-0} == 0 ]] || exit "$MOCK_INSTALL_EXIT"
mkdir -p "$KIMI_INSTALL_DIR/bin"
cat > "$KIMI_INSTALL_DIR/bin/kimi" <<'CLI'
#!/bin/sh
case "$1" in
  --version) printf 'Kimi Code CLI test\n' ;;
  --print-system-ca) printf '%s\n' "${NODE_USE_SYSTEM_CA:-unset}" ;;
  --fail) exit 42 ;;
  *) exit 91 ;;
esac
CLI
chmod +x "$KIMI_INSTALL_DIR/bin/kimi"
INSTALLER
exit "${MOCK_CURL_EXIT:-0}"
CURL
chmod +x "$test_bin/curl"

test_home="$TEMP_DIR/home"
mkdir -p "$test_home"
HOME="$test_home" PATH="$test_bin" bash "$DOTFILES_DIR/agents/kimi-code/install.sh" --dry-run > "$TEMP_DIR/run.log" 2>&1 \
  || { cat "$TEMP_DIR/run.log"; fail "fresh dry run failed"; }
[[ -z $(find "$test_home" -mindepth 1) ]] || fail "dry run changed files or downloaded anything"

for attempt in 1 2; do
  HOME="$test_home" PATH="$test_bin" bash "$DOTFILES_DIR/agents/kimi-code/install.sh" > "$TEMP_DIR/run.log" 2>&1 \
    || { cat "$TEMP_DIR/run.log"; fail "installation attempt $attempt failed"; }
done
[[ -x $test_home/.local/bin/kimi ]] || fail "Kimi is not available through ~/.local/bin"
[[ $(readlink "$test_home/.local/bin/kimi") == "$DOTFILES_DIR/agents/kimi-code/kimi" ]] || fail "executable link does not use the managed launcher"
[[ $(HOME="$test_home" NODE_USE_SYSTEM_CA= "$test_home/.local/bin/kimi" --print-system-ca) == 1 ]] || fail "launcher did not enable system certificates"
[[ $(HOME="$test_home" NODE_USE_SYSTEM_CA=0 "$test_home/.local/bin/kimi" --print-system-ca) == 0 ]] || fail "launcher replaced an explicit certificate setting"
status=0
HOME="$test_home" "$test_home/.local/bin/kimi" --fail || status=$?
[[ $status -eq 42 ]] || fail "launcher lost the native command's exit status"
[[ $(cat "$test_home/downloads") == download ]] || fail "rerun downloaded Kimi again"
[[ $(cat "$test_home/installer-ran") == installed ]] || fail "rerun reinstalled Kimi"
[[ $(readlink "$test_home/.kimi-code/AGENTS.md") == "$DOTFILES_DIR/agents/AGENTS.md" ]] || fail "global instructions are not canonical"
for skill in "$DOTFILES_DIR"/agents/skills/*/; do
  [[ $(readlink "$test_home/.agents/skills/$(basename "$skill")") == "${skill%/}" ]] || fail "shared skill does not resolve to its canonical source"
done

# Existing installations and custom data roots must work without changing credentials or local skills.
existing_home="$TEMP_DIR/existing"
custom_home="$existing_home/custom-kimi"
mkdir -p "$custom_home" "$existing_home/.agents/skills/local-skill"
printf 'local config\n' > "$custom_home/config.toml"
printf 'local skill\n' > "$existing_home/.agents/skills/local-skill/SKILL.md"
HOME="$existing_home" KIMI_CODE_HOME="$custom_home" PATH="$test_home/.kimi-code/bin:$test_bin" \
  bash "$DOTFILES_DIR/agents/kimi-code/install.sh" > "$TEMP_DIR/run.log" 2>&1 \
  || { cat "$TEMP_DIR/run.log"; fail "existing CLI with custom home failed"; }
[[ ! -e $existing_home/downloads && ! -e $existing_home/.local/bin/kimi ]] || fail "existing CLI was replaced"
[[ $(readlink "$custom_home/AGENTS.md") == "$DOTFILES_DIR/agents/AGENTS.md" ]] || fail "custom home missed global instructions"
[[ $(cat "$custom_home/config.toml") == 'local config' ]] || fail "local configuration was overwritten"
[[ $(cat "$existing_home/.agents/skills/local-skill/SKILL.md") == 'local skill' ]] || fail "local skill was overwritten"

for failure in download install; do
  failed_home="$TEMP_DIR/failed-$failure"
  mkdir -p "$failed_home"
  curl_exit=0
  install_exit=0
  if [[ $failure == download ]]; then curl_exit=22; else install_exit=42; fi
  status=0
  HOME="$failed_home" PATH="$test_bin" MOCK_CURL_EXIT="$curl_exit" MOCK_INSTALL_EXIT="$install_exit" \
    bash "$DOTFILES_DIR/agents/kimi-code/install.sh" > "$TEMP_DIR/run.log" 2>&1 || status=$?
  [[ $status -eq $((curl_exit + install_exit)) ]] || fail "$failure exit status was lost"
  [[ ! -e $failed_home/.local/bin/kimi && ! -e $failed_home/.agents ]] || fail "installer continued after $failure failure"
  if [[ $failure == download ]]; then
    [[ ! -e $failed_home/installer-ran ]] || fail "partial download was executed"
  fi
done

conflict_home="$TEMP_DIR/conflict"
mkdir -p "$conflict_home/.local/bin/kimi"
printf 'keep\n' > "$conflict_home/.local/bin/kimi/data"
if HOME="$conflict_home" PATH="$test_bin" bash "$DOTFILES_DIR/agents/kimi-code/install.sh" > "$TEMP_DIR/run.log" 2>&1; then
  fail "directory at executable path was accepted"
fi
[[ $(cat "$conflict_home/.local/bin/kimi/data") == keep && ! -e $conflict_home/downloads ]] || fail "conflict was not preserved before downloading"

printf 'Kimi installer checks passed\n'
