#!/bin/bash
set -euo pipefail

# QuickDraw Service Monitor & Watchdog
# Auto-restarts services and handles hanging processes
# Logs all actions to /var/log/quickdraw-watchdog.log

SLACK_TOKEN="${SLACK_TOKEN:-}"
CHANNEL="C0ACL9Q55EX"  # #quickdraw
WATCHDOG_LOG="/var/log/quickdraw-watchdog.log"

# Ensure log file exists and is writable
sudo touch "$WATCHDOG_LOG"
sudo chmod 666 "$WATCHDOG_LOG"

log_action() {
    echo "[$(date)] $1" >> "$WATCHDOG_LOG"
}

post_alert() {
    local message="$1"
    curl -s -X POST "https://slack.com/api/chat.postMessage" \
        -H "Authorization: Bearer $SLACK_TOKEN" \
        -H "Content-type: application/json" \
        -d "{
            \"channel\": \"$CHANNEL\",
            \"text\": \"$message\"
        }" > /dev/null
}

restart_service() {
    local service="$1"
    log_action "Restarting $service due to issues"
    
    # Force kill then restart
    sudo systemctl kill "$service" 2>/dev/null || true
    sleep 3
    sudo systemctl start "$service"
    
    # Verify restart
    if systemctl is-active "$service" > /dev/null; then
        log_action "$service restarted successfully"
        post_alert "🔄 *$service* restarted automatically by watchdog"
    else
        log_action "Failed to restart $service"
        post_alert "❌ *$service* restart FAILED - manual intervention required"
    fi
}

log_action "Watchdog scan started"

# Check quickdraw-strategy service and pong timeouts
STRATEGY_STATUS=$(systemctl is-active quickdraw-strategy || echo "inactive")
if [[ "$STRATEGY_STATUS" != "active" ]]; then
    log_action "quickdraw-strategy is $STRATEGY_STATUS"
    restart_service "quickdraw-strategy"
else
    # Check pong timeouts in last 30 minutes
    THIRTY_MIN_AGO=$(date -d "30 minutes ago" +"%Y-%m-%d %H:%M")
    PONG_TIMEOUTS=$(journalctl -u quickdraw-strategy --since "$THIRTY_MIN_AGO" --no-pager | grep -c "pong wasn't received" || echo 0)
    PONG_TIMEOUTS=$(echo "$PONG_TIMEOUTS" | tr -d '\n\r' | head -1)
    
    if [[ $PONG_TIMEOUTS -gt 10 ]]; then
        log_action "quickdraw-strategy has $PONG_TIMEOUTS pong timeouts in 30min (threshold: >10)"
        restart_service "quickdraw-strategy"
    fi
fi

# Check quickdraw-data-collector service
COLLECTOR_STATUS=$(systemctl is-active quickdraw-data-collector || echo "inactive")
if [[ "$COLLECTOR_STATUS" != "active" ]]; then
    log_action "quickdraw-data-collector is $COLLECTOR_STATUS"
    restart_service "quickdraw-data-collector"
fi

# Check for hanging git operations (running >5 minutes)
HANGING_GIT=$(ps -eo pid,etime,cmd | grep -E "git (push|pull)" | grep -v grep | awk '$2 ~ /[0-9][0-9]:[0-9][0-9]/ && $2 > "05:00" {print $1, $3, $4}' || true)

if [[ -n "$HANGING_GIT" ]]; then
    log_action "Found hanging git operations: $HANGING_GIT"
    echo "$HANGING_GIT" | while read -r pid cmd; do
        if [[ -n "$pid" ]]; then
            log_action "Killing hanging git process: PID $pid ($cmd)"
            kill -9 "$pid" 2>/dev/null || true
        fi
    done
    post_alert "🔪 Killed hanging git operations (running >5 minutes)"
fi

# Check for orphan node processes related to quickdraw
ORPHAN_NODES=$(ps aux | grep -E "node.*quickdraw" | grep -v grep | grep -v "systemd\|openclaw" || true)

if [[ -n "$ORPHAN_NODES" ]]; then
    log_action "Found orphan QuickDraw node processes"
    echo "$ORPHAN_NODES" | while read -r user pid rest; do
        if [[ "$user" != "root" && -n "$pid" ]]; then
            log_action "Killing orphan node process: PID $pid (user: $user)"
            kill -9 "$pid" 2>/dev/null || true
        fi
    done
    post_alert "🧹 Cleaned up orphan QuickDraw node processes"
fi

log_action "Watchdog scan completed"