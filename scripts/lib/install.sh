# Shared installer helpers. Source from Bash 3.2+ after setting DOTFILES_DIR.

install_init() {
  INSTALL_NAME=$1
  INSTALL_TOTAL=$2
  shift 2
  DRY_RUN=false
  INSTALL_ARGS=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) DRY_RUN=true; INSTALL_ARGS=(--dry-run) ;;
      -h|--help)
        printf 'Usage: %s [--dry-run]\n\n%s\n\n  --dry-run  Preview actions without downloads or changes.\n' "${0#"$DOTFILES_DIR/"}" "$INSTALL_NAME"
        exit 0
        ;;
      *) printf 'Unknown option: %s. Use --help for usage.\n' "$1" >&2; exit 2 ;;
    esac
    shift
  done

  INSTALL_STEP=0
  INSTALL_LABEL=preflight
  INSTALL_WARNINGS=0
  INSTALL_SKIPPED=0
  INSTALL_TEMP_DIR=""
  INSTALL_ERROR_LINE=""
  INSTALL_COLOR=""
  INSTALL_RESET=""
  if [[ -t 1 && ${TERM:-dumb} != dumb && -z ${NO_COLOR:-} ]]; then
    INSTALL_COLOR=$'\033[36m'
    INSTALL_RESET=$'\033[0m'
  fi
  trap 'INSTALL_ERROR_LINE=$LINENO' ERR
  trap 'install_exit "$?"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  printf '\n%s%s%s' "$INSTALL_COLOR" "$INSTALL_NAME" "$INSTALL_RESET"
  if $DRY_RUN; then printf ' (dry run)'; fi
  printf '\n'
}

install_exit() {
  local status=$1
  trap - EXIT
  if [[ -n $INSTALL_TEMP_DIR ]]; then rm -rf -- "$INSTALL_TEMP_DIR"; fi
  if [[ $status -ne 0 ]]; then
    printf '\n[FAIL] %s: %s (exit %s%s). Fix the error above and rerun.\n' \
      "$INSTALL_NAME" "$INSTALL_LABEL" "$status" "${INSTALL_ERROR_LINE:+, line $INSTALL_ERROR_LINE}" >&2
  fi
  exit "$status"
}

progress() {
  local completed=$1 filled i bar=""
  filled=$((completed * 20 / INSTALL_TOTAL))
  for ((i=0; i<20; i++)); do
    if ((i < filled)); then bar+='#'; else bar+='-'; fi
  done
  printf '%s[%s] %3d%%%s' "$INSTALL_COLOR" "$bar" "$((completed * 100 / INSTALL_TOTAL))" "$INSTALL_RESET"
}

step() {
  INSTALL_STEP=$((INSTALL_STEP + 1))
  INSTALL_LABEL=$1
  printf '\n'
  progress "$((INSTALL_STEP - 1))"
  printf '  %d/%d %s\n' "$INSTALL_STEP" "$INSTALL_TOTAL" "$INSTALL_LABEL"
}

info() { printf '  [INFO] %s\n' "$*"; }
skip() { INSTALL_SKIPPED=$((INSTALL_SKIPPED + 1)); printf '  [SKIP] %s\n' "$*"; }
warn() { INSTALL_WARNINGS=$((INSTALL_WARNINGS + 1)); printf '  [WARN] %s\n' "$*" >&2; }
die() { printf '  [ERROR] %s\n' "$*" >&2; exit 1; }

finish() {
  [[ $INSTALL_STEP -eq $INSTALL_TOTAL ]] || die "Installer step count is incorrect."
  printf '\n'
  progress "$INSTALL_TOTAL"
  if $DRY_RUN; then
    printf '  %s: preview complete.\n' "$INSTALL_NAME"
  else
    printf '  %s: finished (%d skipped, %d warnings).\n' "$INSTALL_NAME" "$INSTALL_SKIPPED" "$INSTALL_WARNINGS"
  fi
}

run() {
  if $DRY_RUN; then printf '  [PLAN]'; else printf '  [RUN]'; fi
  printf ' %q' "$@"
  printf '\n'
  if ! $DRY_RUN; then "$@"; fi
}

link_file() {
  local output
  output=$("$DOTFILES_DIR/scripts/link-file" ${INSTALL_ARGS[@]+"${INSTALL_ARGS[@]}"} "$@")
  printf '%s\n' "$output"
  case "$output" in
    '  [SKIP]'*) INSTALL_SKIPPED=$((INSTALL_SKIPPED + 1)) ;;
  esac
}

# Unlike run, nested installers must execute their own preview to check sources.
run_installer() {
  bash "$1" ${INSTALL_ARGS[@]+"${INSTALL_ARGS[@]}"}
}

require_commands() {
  local tool
  for tool in "$@"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      die "Required command '$tool' is missing. Install it and rerun."
    fi
  done
}

require_os() {
  if $DRY_RUN; then info "Requires $1 for a real installation."
  elif [[ $(uname -s) != "$1" ]]; then die "This installer requires $1 (found $(uname -s))."; fi
}

make_temp_dir() {
  $DRY_RUN && die "Internal error: attempted to create temporary files during a dry run."
  if [[ -z $INSTALL_TEMP_DIR ]]; then INSTALL_TEMP_DIR=$(mktemp -d); fi
}

# Never pipe partial downloads into a shell. Call only outside dry-run branches.
download() {
  local url=$1 destination=$2
  $DRY_RUN && die "Internal error: attempted a download during a dry run."
  info "Downloading $url"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --connect-timeout 15 --max-time 600 --silent --show-error "$url" -o "$destination"
  elif command -v wget >/dev/null 2>&1; then
    wget --tries=3 --timeout=30 -q "$url" -O "$destination"
  else
    die "curl or wget is required to download $url."
  fi
  [[ -s $destination ]] || die "Downloaded file is empty: $url"
}
