#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
fail() { echo "Muse installer check failed: $*" >&2; exit 1; }
unset XDG_CONFIG_HOME

agent_bin="$TEMP_DIR/bin"
agent_home="$TEMP_DIR/home"
mkdir -p "$agent_bin" "$agent_home"
for tool in bash dirname basename mkdir readlink ln rm mktemp cat chmod python3; do
  ln -s "$(command -v "$tool")" "$agent_bin/$tool"
done
cat > "$agent_bin/curl" <<'CURL'
#!/usr/bin/env bash
set -euo pipefail
printf 'download\n' >> "$HOME/downloads"
cat > "${!#}" <<'INSTALLER'
#!/usr/bin/env bash
set -euo pipefail
printf 'installed\n' >> "$HOME/installer-ran"
[[ $MUSE_INSTALL_DIR == "$HOME/.local/bin" && $MUSE_NO_MODIFY_PATH == 1 && $MUSE_LOGIN == 0 ]]
case ":$PATH:" in *":$MUSE_INSTALL_DIR:"*) ;; *) exit 91 ;; esac
[[ ${MOCK_INSTALL_EXIT:-0} == 0 ]] || exit "$MOCK_INSTALL_EXIT"
mkdir -p "$MUSE_INSTALL_DIR"
cat > "$MUSE_INSTALL_DIR/muse" <<'MUSE'
#!/usr/bin/env bash
[[ $* == --version && $MUSE_NO_AUTO_UPDATE == 1 ]] || exit 91
printf 'Muse Code test\n'
exit "${MOCK_MUSE_EXIT:-0}"
MUSE
chmod +x "$MUSE_INSTALL_DIR/muse"
INSTALLER
exit "${MOCK_CURL_EXIT:-0}"
CURL
chmod +x "$agent_bin/curl"

HOME="$agent_home" PATH="$agent_bin" bash "$DOTFILES_DIR/agents/muse-code/install.sh" --dry-run > "$TEMP_DIR/muse.log" 2>&1 \
  || { cat "$TEMP_DIR/muse.log"; fail "preview without Muse failed"; }
[[ -z $(find "$agent_home" -mindepth 1) ]] || fail "preview downloaded or changed files"
for attempt in 1 2; do
  HOME="$agent_home" PATH="$agent_bin" bash "$DOTFILES_DIR/agents/muse-code/install.sh" > "$TEMP_DIR/muse.log" 2>&1 \
    || { cat "$TEMP_DIR/muse.log"; fail "installation attempt $attempt failed"; }
done
[[ $(cat "$agent_home/downloads") == download && $(cat "$agent_home/installer-ran") == installed ]] || fail "rerun reinstalled Muse"
[[ $(readlink "$agent_home/.config/muse/AGENTS.md") == "$DOTFILES_DIR/agents/AGENTS.md" ]] || fail "personal instructions do not use the shared source"
for skill in "$DOTFILES_DIR"/agents/skills/*/; do
  [[ $(readlink "$agent_home/.agents/skills/$(basename "$skill")") == "${skill%/}" ]] || fail "shared skill link is missing"
done

existing_home="$TEMP_DIR/existing"
config_root="$TEMP_DIR/custom-config"
mkdir -p "$existing_home/.agents/skills/local" "$config_root/muse"
printf 'preserve skill\n' > "$existing_home/.agents/skills/local/SKILL.md"
printf '{"schema_version":1,"model_catalog":{"custom":"keep"},"contributor_mode_enabled":true}\n' > "$config_root/muse/settings.json"
HOME="$existing_home" XDG_CONFIG_HOME="$config_root" PATH="$agent_home/.local/bin:$agent_bin" \
  bash "$DOTFILES_DIR/agents/muse-code/install.sh" > "$TEMP_DIR/muse.log" 2>&1 \
  || { cat "$TEMP_DIR/muse.log"; fail "existing CLI or custom XDG configuration failed"; }
[[ ! -e $existing_home/downloads && ! -e $existing_home/.local/bin/muse ]] || fail "replaced an existing CLI"
[[ $(readlink "$config_root/muse/AGENTS.md") == "$DOTFILES_DIR/agents/AGENTS.md" && ! -e $existing_home/.config/muse ]] || fail "ignored XDG_CONFIG_HOME"
[[ $(cat "$existing_home/.agents/skills/local/SKILL.md") == 'preserve skill' ]] || fail "changed a machine-local skill"
python3 - "$config_root/muse/settings.json" "$DOTFILES_DIR/agents/muse-code/configure.py" <<'PY'
import json
from pathlib import Path
import subprocess
import sys

path = Path(sys.argv[1])
helper = sys.argv[2]
data = json.loads(path.read_text())
assert data == {"schema_version": 1, "model_catalog": {"custom": "keep"}, "contributor_mode_enabled": False, "contributor_mode_disclosure_acknowledged": True}, data
before = path.stat().st_mtime_ns
subprocess.run([sys.executable, helper, str(path)], check=True, capture_output=True)
assert path.stat().st_mtime_ns == before, "rerun rewrote unchanged settings"
assert path.stat().st_mode & 0o777 == 0o600, "settings are not private"
target = path.with_name("local-settings.json")
path.rename(target)
path.symlink_to(target)
target.write_text('{"schema_version":1,"contributor_mode_enabled":true}')
subprocess.run([sys.executable, helper, str(path)], check=True, capture_output=True)
assert path.is_symlink(), "replaced a local settings symlink"
assert json.loads(target.read_text())["contributor_mode_enabled"] is False
for content in ['{"broken":', '[]', '{"schema_version":2}', '{"schema_version":1,"secret":"fixture",broken}']:
    target.write_text(content)
    result = subprocess.run([sys.executable, helper, str(path)], text=True, capture_output=True)
    assert result.returncode != 0, "accepted invalid or unsupported settings"
    assert target.read_text() == content, "overwrote invalid settings"
    assert "fixture" not in result.stderr, "printed settings contents on failure"
assert not list(path.parent.glob(".settings-*")), "leaked temporary settings"
PY

for failure in download install version; do
  failed_home="$TEMP_DIR/failed-$failure"
  mkdir -p "$failed_home"
  curl_exit=0 install_exit=0 muse_exit=0 expected=0
  case "$failure" in
    download) curl_exit=22; expected=22 ;;
    install) install_exit=42; expected=42 ;;
    version) muse_exit=43; expected=43 ;;
  esac
  status=0
  HOME="$failed_home" PATH="$agent_bin" MOCK_CURL_EXIT="$curl_exit" MOCK_INSTALL_EXIT="$install_exit" MOCK_MUSE_EXIT="$muse_exit" \
    bash "$DOTFILES_DIR/agents/muse-code/install.sh" > "$TEMP_DIR/muse.log" 2>&1 || status=$?
  [[ $status -eq $expected ]] || fail "$failure lost its failure exit status"
  [[ ! -e $failed_home/.config/muse ]] || fail "$failure continued into configuration"
  if [[ $failure == download ]]; then
    [[ ! -e $failed_home/installer-ran ]] || fail "executed a partial download"
  fi
done

conflict_home="$TEMP_DIR/conflict"
mkdir -p "$conflict_home/.config/muse"
printf 'local instructions\n' > "$conflict_home/.config/muse/AGENTS.md"
if HOME="$conflict_home" PATH="$agent_bin" bash "$DOTFILES_DIR/agents/muse-code/install.sh" > "$TEMP_DIR/muse.log" 2>&1; then
  fail "discarded unmanaged instructions"
fi
grep -q 'unmanaged instructions' "$TEMP_DIR/muse.log" || fail "instruction conflict failed for the wrong reason"
[[ $(cat "$conflict_home/.config/muse/AGENTS.md") == 'local instructions' && ! -e $conflict_home/downloads ]] || fail "instruction conflict changed local state"

echo 'Muse installer checks passed'
