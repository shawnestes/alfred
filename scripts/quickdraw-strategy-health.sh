#!/bin/bash
set -euo pipefail

# QuickDraw Strategy Health Monitor
# Checks MFI/RSI signals, EPIPE errors, and service status
# Posts to #quickdraw only if problems found

SLACK_TOKEN="${SLACK_TOKEN:-}"
CHANNEL="C0ACL9Q55EX"  # #quickdraw
LOG_FILE="/var/log/quickdraw-live.log"

# Calculate timestamps (2 hours ago, 1 hour ago)
TWO_HOURS_AGO=$(date -d "2 hours ago" +"%Y-%m-%d %H:%M")
ONE_HOUR_AGO=$(date -d "1 hour ago" +"%Y-%m-%d %H:%M")

ALERTS=()

# Check if log file exists
if [[ ! -f "$LOG_FILE" ]]; then
    ALERTS+=("❌ QuickDraw log file missing: $LOG_FILE")
fi

# Check MFI signals in last 2 hours
if [[ -f "$LOG_FILE" ]]; then
    MFI_COUNT=$(awk -v cutoff="$TWO_HOURS_AGO" '$0 >= cutoff' "$LOG_FILE" | grep -ci "MFI" || true)
    if [[ $MFI_COUNT -eq 0 ]]; then
        ALERTS+=("⚠️ Zero MFI signals in last 2 hours")
    fi

    # Check RSI signals in last 2 hours
    RSI_COUNT=$(awk -v cutoff="$TWO_HOURS_AGO" '$0 >= cutoff' "$LOG_FILE" | grep -ci "RSI" || true)
    if [[ $RSI_COUNT -eq 0 ]]; then
        ALERTS+=("⚠️ Zero RSI signals in last 2 hours")
    fi

    # Check EPIPE errors in last hour
    EPIPE_COUNT=$(awk -v cutoff="$ONE_HOUR_AGO" '$0 >= cutoff' "$LOG_FILE" | grep -ci "EPIPE\|pipe" || true)
    if [[ $EPIPE_COUNT -gt 5 ]]; then
        ALERTS+=("🚨 $EPIPE_COUNT EPIPE errors in last hour (threshold: >5)")
    fi

    # Check for strategies with zero activity (trades/signals) in extended period
    # Look for patterns indicating no activity in last 4 hours
    FOUR_HOURS_AGO=$(date -d "4 hours ago" +"%Y-%m-%d %H:%M")
    RECENT_ACTIVITY=$(awk -v cutoff="$FOUR_HOURS_AGO" '$0 >= cutoff' "$LOG_FILE" | grep -ci "signal\|trade\|order" || true)
    if [[ $RECENT_ACTIVITY -eq 0 ]]; then
        ALERTS+=("⚠️ No trading activity (signals/trades) detected in last 4 hours")
    fi
fi

# Check service status
STRATEGY_STATUS=$(systemctl is-active quickdraw-strategy || echo "inactive")
COLLECTOR_STATUS=$(systemctl is-active quickdraw-data-collector || echo "inactive")

if [[ "$STRATEGY_STATUS" != "active" ]]; then
    ALERTS+=("🔴 quickdraw-strategy service: $STRATEGY_STATUS")
fi

if [[ "$COLLECTOR_STATUS" != "active" ]]; then
    ALERTS+=("🔴 quickdraw-data-collector service: $COLLECTOR_STATUS")
fi

# If no alerts, exit silently
if [[ ${#ALERTS[@]} -eq 0 ]]; then
    exit 0
fi

# Build alert message
MESSAGE="🚨 *QuickDraw Health Alert*\n\n"
for alert in "${ALERTS[@]}"; do
    MESSAGE+="• $alert\n"
done
MESSAGE+="\n_Timestamp: $(date)_"

# Post to Slack
curl -s -X POST "https://slack.com/api/chat.postMessage" \
    -H "Authorization: Bearer $SLACK_TOKEN" \
    -H "Content-type: application/json" \
    -d "{
        \"channel\": \"$CHANNEL\",
        \"text\": \"$(echo -e "$MESSAGE")\"
    }" > /dev/null

echo "Alert sent to #quickdraw"