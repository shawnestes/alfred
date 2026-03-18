#!/bin/bash
set -euo pipefail

# Thread Monitor - Check for unanswered threads in project channels
# Alerts Nexus via DM only if unanswered threads found

SLACK_TOKEN="${SLACK_TOKEN:-}"
NEXUS_DM="D0ACMRE3TPE"
NEXUS_USER="U0ACX5EDN1X"
SHAWN_USER="U0ACHB3MA5Q"

# Project channels to monitor
declare -A CHANNELS=(
    ["C0ACL9Q55EX"]="#quickdraw"
    ["C0ACSM5LDLJ"]="#dearnote"
    ["C0ADM6EG456"]="#ghostreel"
    ["C0AD5K17QP3"]="#noyoupick"
)

UNANSWERED_THREADS=()

# Function to check if Nexus replied in a thread
check_nexus_reply() {
    local channel_id="$1"
    local thread_ts="$2"
    
    # Get thread replies
    local replies=$(curl -s -G "https://slack.com/api/conversations.replies" \
        -H "Authorization: Bearer $SLACK_TOKEN" \
        -d "channel=$channel_id" \
        -d "ts=$thread_ts")
    
    # Check if Nexus (U0ACX5EDN1X) has replied
    echo "$replies" | grep -q "\"user\":\"$NEXUS_USER\"" && return 0 || return 1
}

# Check each channel
for channel_id in "${!CHANNELS[@]}"; do
    channel_name="${CHANNELS[$channel_id]}"
    
    # Get last 10 messages from channel
    messages=$(curl -s -G "https://slack.com/api/conversations.history" \
        -H "Authorization: Bearer $SLACK_TOKEN" \
        -d "channel=$channel_id" \
        -d "limit=10")
    
    # Parse messages with threads (reply_count > 0)
    echo "$messages" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for msg in data.get('messages', []):
    if msg.get('reply_count', 0) > 0:
        # Check if thread was started by Shawn or an agent (bot)
        user = msg.get('user', '')
        if user == '$SHAWN_USER' or msg.get('bot_id'):
            print(f\"{msg['ts']}|{user}|{msg.get('text', '')[:100]}\")
" | while IFS='|' read -r thread_ts user text; do
        if [[ -n "$thread_ts" ]]; then
            # Check if Nexus replied to this thread
            if ! check_nexus_reply "$channel_id" "$thread_ts"; then
                UNANSWERED_THREADS+=("{\"channel\": \"$channel_name\", \"thread_ts\": \"$thread_ts\", \"last_message_user\": \"$user\", \"last_message_text\": \"$text\"}")
            fi
        fi
    done
done

# If no unanswered threads, exit silently
if [[ ${#UNANSWERED_THREADS[@]} -eq 0 ]]; then
    exit 0
fi

# Write JSON output
JSON_OUTPUT="["
for ((i=0; i<${#UNANSWERED_THREADS[@]}; i++)); do
    JSON_OUTPUT+="${UNANSWERED_THREADS[$i]}"
    if [[ $i -lt $((${#UNANSWERED_THREADS[@]}-1)) ]]; then
        JSON_OUTPUT+=","
    fi
done
JSON_OUTPUT+="]"

echo "$JSON_OUTPUT" > /tmp/unanswered-threads.json

# Build alert message
MESSAGE="📋 *Unanswered Threads Detected*\n\n"
MESSAGE+="Found ${#UNANSWERED_THREADS[@]} unanswered thread(s) across project channels.\n\n"
MESSAGE+="Details saved to: \`/tmp/unanswered-threads.json\`\n"
MESSAGE+="_Check timestamp: $(date)_"

# Send DM to Nexus
curl -s -X POST "https://slack.com/api/chat.postMessage" \
    -H "Authorization: Bearer $SLACK_TOKEN" \
    -H "Content-type: application/json" \
    -d "{
        \"channel\": \"$NEXUS_DM\",
        \"text\": \"$(echo -e "$MESSAGE")\"
    }" > /dev/null

echo "Unanswered thread alert sent to Nexus DM"