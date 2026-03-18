#!/bin/bash
set -euo pipefail

# Agent Health Report Monitor
# Checks all specialist agents + QuickDraw services
# Posts to #all-shadowteam only if any issues found

SLACK_TOKEN="${SLACK_TOKEN:-}"
CHANNEL="C0ACF9NQS4E"  # #all-shadowteam

# Services to monitor
SERVICES=(
    "openclaw-dearnote"
    "openclaw-ghostreel"
    "openclaw-noyoupick"
    "openclaw-quickdraw"
    "quickdraw-data-collector"
    "quickdraw-strategy"
)

ISSUES=()
ERROR_THRESHOLD=10

# Check each service
for service in "${SERVICES[@]}"; do
    # Check if service is active
    STATUS=$(systemctl is-active "$service" 2>/dev/null || echo "inactive")
    
    if [[ "$STATUS" != "active" ]]; then
        ISSUES+=("🔴 *$service*: $STATUS")
        continue
    fi
    
    # Get memory usage from systemctl status
    MEMORY=$(systemctl status "$service" --no-pager -l | grep -o "Memory: [0-9.]*[KMGT]*" | head -1 || echo "Memory: unknown")
    
    # Check for errors in last hour
    ERROR_COUNT=$(journalctl -u "$service" --since "1 hour ago" --no-pager 2>/dev/null | grep -ci error || echo "0")
    ERROR_COUNT=$(echo "$ERROR_COUNT" | tr -d '\n\r' | head -1)
    
    if [[ $ERROR_COUNT -gt $ERROR_THRESHOLD ]]; then
        ISSUES+=("⚠️ *$service*: $ERROR_COUNT errors in last hour ($MEMORY)")
    fi
done

# If no issues, exit silently
if [[ ${#ISSUES[@]} -eq 0 ]]; then
    exit 0
fi

# Build report message
MESSAGE="🚨 *Agent Health Alert*\n\n"
for issue in "${ISSUES[@]}"; do
    MESSAGE+="• $issue\n"
done
MESSAGE+="\n_Health check completed: $(date)_"

# Post to Slack
curl -s -X POST "https://slack.com/api/chat.postMessage" \
    -H "Authorization: Bearer $SLACK_TOKEN" \
    -H "Content-type: application/json" \
    -d "{
        \"channel\": \"$CHANNEL\",
        \"text\": \"$(echo -e "$MESSAGE")\"
    }" > /dev/null

echo "Agent health alert sent to #all-shadowteam"