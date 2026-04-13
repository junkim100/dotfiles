#!/usr/bin/env bash
#
# Monitors SLURM jobs for the current user and sends Slack DM notifications
# when jobs start, change state, complete, or fail.
#
# Usage:
#   bash ~/slurm_notifier.sh                    # monitor in foreground
#   nohup bash ~/slurm_notifier.sh &            # monitor in background
#   bash ~/slurm_notifier.sh --poll-interval 10 # custom poll interval
#
# Environment:
#   SLACK_BOT_TOKEN - Slack Bot User OAuth Token (xoxb-...)
#   SLACK_USER_ID   - Slack user ID to DM
#   POLL_INTERVAL   - seconds between checks (default: 15)
#

set -euo pipefail

SLACK_BOT_TOKEN="${SLACK_BOT_TOKEN:-}"
SLACK_USER_ID="${SLACK_USER_ID:-}"
POLL_INTERVAL="${POLL_INTERVAL:-15}"
MONITOR_USER="${USER:-$(whoami)}"

# Parse CLI args
while [ $# -gt 0 ]; do
  case "$1" in
    --poll-interval) POLL_INTERVAL="$2"; shift 2 ;;
    --user) MONITOR_USER="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [ -z "$SLACK_BOT_TOKEN" ]; then
  echo "Error: SLACK_BOT_TOKEN is not set."
  exit 1
fi

slack_notify() {
  local msg="$1"
  curl -sf -X POST "https://slack.com/api/chat.postMessage" \
    -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
    -H 'Content-type: application/json' \
    -d "{\"channel\": \"$SLACK_USER_ID\", \"text\": \"$msg\"}" >/dev/null 2>&1 || true
}

# Track known job states: associative array of JOBID -> STATE
declare -A JOB_STATES

echo "[slurm-notifier] monitoring jobs for user: $MONITOR_USER"
echo "[slurm-notifier] poll interval: ${POLL_INTERVAL}s"
echo "[slurm-notifier] Ctrl+C to stop"

while true; do
  # Get current jobs: JOBID|STATE|JOBNAME|NODELIST|NODES
  CURRENT_JOBS=$(squeue -u "$MONITOR_USER" -h -o "%i|%T|%j|%N|%D" 2>/dev/null || true)

  # Build set of current job IDs
  declare -A CURRENT_IDS

  while IFS='|' read -r jobid state name nodelist nodes; do
    [ -z "$jobid" ] && continue
    CURRENT_IDS[$jobid]=1
    prev_state="${JOB_STATES[$jobid]:-}"

    if [ -z "$prev_state" ]; then
      # New job we haven't seen before
      JOB_STATES[$jobid]="$state"
      if [ "$state" = "RUNNING" ]; then
        slack_notify "[SLURM] Job *${jobid}* (\`${name}\`) is *RUNNING* on \`${nodelist}\` (${nodes} node(s))"
      else
        slack_notify "[SLURM] Job *${jobid}* (\`${name}\`) queued — state: *${state}*"
      fi
      echo "[$(date '+%H:%M:%S')] Job $jobid ($name) $state"
    elif [ "$prev_state" != "$state" ]; then
      # State changed
      JOB_STATES[$jobid]="$state"
      if [ "$state" = "RUNNING" ]; then
        slack_notify "[SLURM] Job *${jobid}* (\`${name}\`) is *RUNNING* on \`${nodelist}\` (${nodes} node(s))"
      else
        slack_notify "[SLURM] Job *${jobid}* (\`${name}\`) state changed: *${prev_state}* → *${state}*"
      fi
      echo "[$(date '+%H:%M:%S')] Job $jobid ($name) $prev_state -> $state"
    fi
  done <<< "$CURRENT_JOBS"

  # Check for jobs that disappeared (completed or failed)
  for jobid in "${!JOB_STATES[@]}"; do
    if [ -z "${CURRENT_IDS[$jobid]:-}" ]; then
      # Job no longer in squeue — check final state via sacct
      final_state=$(sacct -j "$jobid" -n -o State -X 2>/dev/null | head -1 | xargs || echo "UNKNOWN")
      job_name=$(sacct -j "$jobid" -n -o JobName -X 2>/dev/null | head -1 | xargs || echo "unknown")
      elapsed=$(sacct -j "$jobid" -n -o Elapsed -X 2>/dev/null | head -1 | xargs || echo "?")

      case "$final_state" in
        COMPLETED)
          slack_notify "[SLURM] Job *${jobid}* (\`${job_name}\`) *COMPLETED* (elapsed: ${elapsed})"
          echo "[$(date '+%H:%M:%S')] Job $jobid ($job_name) COMPLETED ($elapsed)"
          ;;
        FAILED|OUT_OF_MEMORY)
          slack_notify "[SLURM] Job *${jobid}* (\`${job_name}\`) *FAILED* — state: ${final_state} (elapsed: ${elapsed})"
          echo "[$(date '+%H:%M:%S')] Job $jobid ($job_name) FAILED ($final_state, $elapsed)"
          ;;
        CANCELLED*)
          slack_notify "[SLURM] Job *${jobid}* (\`${job_name}\`) was *CANCELLED* (elapsed: ${elapsed})"
          echo "[$(date '+%H:%M:%S')] Job $jobid ($job_name) CANCELLED ($elapsed)"
          ;;
        TIMEOUT)
          slack_notify "[SLURM] Job *${jobid}* (\`${job_name}\`) *TIMED OUT* (elapsed: ${elapsed})"
          echo "[$(date '+%H:%M:%S')] Job $jobid ($job_name) TIMEOUT ($elapsed)"
          ;;
        *)
          slack_notify "[SLURM] Job *${jobid}* (\`${job_name}\`) ended — state: ${final_state} (elapsed: ${elapsed})"
          echo "[$(date '+%H:%M:%S')] Job $jobid ($job_name) ended ($final_state, $elapsed)"
          ;;
      esac

      unset "JOB_STATES[$jobid]"
    fi
  done

  unset CURRENT_IDS
  sleep "$POLL_INTERVAL"
done
