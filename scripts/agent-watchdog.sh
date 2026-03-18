#!/usr/bin/env bash
# Agent Watchdog — detects stalled/context-overflow agents and auto-restarts them
# Run via cron every 5 minutes

set -euo pipefail

LOG_FILE="/root/.openclaw/workspace/memory/watchdog.log"
AGENTS=("dearnote" "ghostreel" "noyoupick" "quickdraw")

log() { echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] $*" >> "$LOG_FILE"; }

for agent in "${AGENTS[@]}"; do
  service="openclaw-${agent}"

  # Skip if not running
  if ! systemctl is-active "$service" &>/dev/null; then
    continue
  fi

  # Check 1: Context overflow errors in last 10 minutes
  overflow_count=$(journalctl -u "$service" --since "10 min ago" --no-pager 2>/dev/null \
    | grep -c "exceed context limit\|context_length_exceeded\|max_tokens.*exceed" || true)

  if [[ "$overflow_count" -ge 2 ]]; then
    log "RESTART $service — context overflow detected ($overflow_count errors in 10min)"
    systemctl restart "$service"
    echo "restarted:context_overflow:$agent"
    continue
  fi

  # Check 2: Repeated identical errors (same error 3+ times in 10 min)
  repeat_errors=$(journalctl -u "$service" --since "10 min ago" --no-pager 2>/dev/null \
    | grep -i "error\|fatal\|fail" \
    | sort | uniq -c | sort -rn | head -1 | awk '{print $1}' || echo 0)

  if [[ "${repeat_errors:-0}" -ge 5 ]]; then
    log "RESTART $service — repeated error loop ($repeat_errors identical errors in 10min)"
    systemctl restart "$service"
    echo "restarted:error_loop:$agent"
    continue
  fi
done
