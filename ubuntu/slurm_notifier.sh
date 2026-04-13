#!/usr/bin/env bash
#
# Monitors SLURM jobs and sends Slack DMs when jobs complete or fail.
# Ignores cancelled jobs (manual scancel).
#
# Usage:
#   bash ~/slurm_notifier.sh
#   nohup bash ~/slurm_notifier.sh &>/dev/null &
#
# Environment (set in ~/.slurm_notifier.env):
#   SLACK_BOT_TOKEN - Slack Bot User OAuth Token (xoxb-...)
#   SLACK_USER_ID   - Slack user ID to DM
#   POLL_INTERVAL   - seconds between checks (default: 30)

set -euo pipefail

SLACK_BOT_TOKEN="${SLACK_BOT_TOKEN:-}"
SLACK_USER_ID="${SLACK_USER_ID:-}"
POLL_INTERVAL="${POLL_INTERVAL:-30}"
USER_NAME="${USER:-$(whoami)}"

if [[ -z "$SLACK_BOT_TOKEN" || -z "$SLACK_USER_ID" ]]; then
  echo "[slurm-notifier] Error: SLACK_BOT_TOKEN and SLACK_USER_ID must be set."
  exit 1
fi

slack_notify() {
  local msg="$1"
  local payload
  payload=$(jq -nc --arg ch "$SLACK_USER_ID" --arg txt "$msg" \
    '{channel: $ch, text: $txt}')
  curl -sf -X POST "https://slack.com/api/chat.postMessage" \
    -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
    -H "Content-type: application/json" \
    -d "$payload" >/dev/null 2>&1 || true
}

# Snapshot current job IDs so we don't notify for pre-existing jobs
declare -A TRACKED_JOBS
while IFS='|' read -r jobid state; do
  [[ -z "$jobid" ]] && continue
  TRACKED_JOBS[$jobid]="$state"
done < <(squeue -u "$USER_NAME" -h -o "%i|%T" 2>/dev/null || true)

echo "[slurm-notifier] monitoring jobs for: $USER_NAME"
echo "[slurm-notifier] tracking ${#TRACKED_JOBS[@]} existing job(s)"
echo "[slurm-notifier] poll interval: ${POLL_INTERVAL}s"

while true; do
  sleep "$POLL_INTERVAL"

  # Get current jobs
  declare -A CURRENT_JOBS
  while IFS='|' read -r jobid state; do
    [[ -z "$jobid" ]] && continue
    CURRENT_JOBS[$jobid]="$state"
  done < <(squeue -u "$USER_NAME" -h -o "%i|%T" 2>/dev/null || true)

  # Pick up new jobs
  for jobid in "${!CURRENT_JOBS[@]}"; do
    if [[ -z "${TRACKED_JOBS[$jobid]:-}" ]]; then
      TRACKED_JOBS[$jobid]="${CURRENT_JOBS[$jobid]}"
      echo "[$(date '+%H:%M:%S')] Tracking new job $jobid (${CURRENT_JOBS[$jobid]})"
    fi
  done

  # Check for jobs that disappeared from the queue
  for jobid in "${!TRACKED_JOBS[@]}"; do
    if [[ -z "${CURRENT_JOBS[$jobid]:-}" ]]; then
      # Job gone from squeue — check final state via sacct
      sacct_line=$(sacct -j "$jobid" -n -o JobName%50,State%20,Elapsed%20 -X 2>/dev/null | head -1 || true)

      if [[ -z "$sacct_line" ]]; then
        unset "TRACKED_JOBS[$jobid]"
        continue
      fi

      job_name=$(echo "$sacct_line" | awk '{print $1}')
      final_state=$(echo "$sacct_line" | awk '{print $2}')
      elapsed=$(echo "$sacct_line" | awk '{print $3}')

      case "$final_state" in
        COMPLETED)
          slack_notify ":white_check_mark: Job *${jobid}* (\`${job_name}\`) *COMPLETED* in ${elapsed}"
          echo "[$(date '+%H:%M:%S')] $jobid ($job_name) COMPLETED ($elapsed)"
          ;;
        FAILED|OUT_OF_ME+)
          slack_notify ":x: Job *${jobid}* (\`${job_name}\`) *FAILED* (${final_state}) after ${elapsed}"
          echo "[$(date '+%H:%M:%S')] $jobid ($job_name) FAILED ($final_state, $elapsed)"
          ;;
        TIMEOUT)
          slack_notify ":warning: Job *${jobid}* (\`${job_name}\`) *TIMED OUT* after ${elapsed}"
          echo "[$(date '+%H:%M:%S')] $jobid ($job_name) TIMEOUT ($elapsed)"
          ;;
        CANCELLED*|CANCELLED+)
          # Ignore cancelled jobs (manual scancel)
          echo "[$(date '+%H:%M:%S')] $jobid ($job_name) CANCELLED — skipping notification"
          ;;
        *)
          echo "[$(date '+%H:%M:%S')] $jobid ($job_name) ended ($final_state) — skipping notification"
          ;;
      esac

      unset "TRACKED_JOBS[$jobid]"
    fi
  done

  unset CURRENT_IDS 2>/dev/null || true
  unset CURRENT_JOBS
done
