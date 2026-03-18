#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/strategy-config.json"

# Check if jq is available, fallback to python3
HAS_JQ=false
if command -v jq >/dev/null 2>&1; then
    HAS_JQ=true
fi

# JSON helper functions
json_get() {
    local path="$1"
    if $HAS_JQ; then
        jq -r "$path" "$CONFIG_FILE"
    else
        python3 -c "
import json, sys
with open('$CONFIG_FILE') as f:
    data = json.load(f)
path = '$path'.strip('.')
parts = path.split('.')
result = data
for part in parts:
    if part.startswith('[') and part.endswith(']'):
        idx = int(part[1:-1])
        result = result[idx]
    else:
        result = result.get(part, None)
        if result is None:
            sys.exit(1)
print(result if isinstance(result, str) else json.dumps(result))
"
    fi
}

json_set() {
    local path="$1"
    local value="$2"
    local temp_file
    temp_file=$(mktemp)
    
    if $HAS_JQ; then
        jq "$path = $value" "$CONFIG_FILE" > "$temp_file"
    else
        python3 -c "
import json, sys
from datetime import datetime
with open('$CONFIG_FILE') as f:
    data = json.load(f)

# Parse the jq-style path and value
path = '$path'
value = $value

# Update the data
if path == '.strategies.$2.enabled':
    strategy = '$2'
    data['strategies'][strategy]['enabled'] = value
elif path.startswith('.strategies.') and path.endswith('.disabled_reason'):
    strategy = '$2'
    if 'disabled_reason' not in data['strategies'][strategy]:
        data['strategies'][strategy]['disabled_reason'] = ''
    data['strategies'][strategy]['disabled_reason'] = value
elif path.startswith('.strategies.') and path.endswith('.disabled_at'):
    strategy = '$2'
    data['strategies'][strategy]['disabled_at'] = value

# Update metadata
data['updated_at'] = datetime.now().isoformat()
data['updated_by'] = 'agent'
data['version'] = data.get('version', 1) + 1

with open('$temp_file', 'w') as f:
    json.dump(data, f, indent=2)
"
    fi
    mv "$temp_file" "$CONFIG_FILE"
}

add_changelog_entry() {
    local by="$1"
    local changes="$2"
    local temp_file
    temp_file=$(mktemp)
    
    if $HAS_JQ; then
        jq --arg by "$by" --arg changes "$changes" --arg date "$(date -Iseconds)" '
            .changelog += [{
                "version": .version,
                "date": $date,
                "by": $by,
                "changes": $changes
            }]
        ' "$CONFIG_FILE" > "$temp_file"
    else
        python3 -c "
import json
from datetime import datetime
with open('$CONFIG_FILE') as f:
    data = json.load(f)

entry = {
    'version': data['version'],
    'date': datetime.now().isoformat(),
    'by': '$by',
    'changes': '$changes'
}
data['changelog'].append(entry)

with open('$temp_file', 'w') as f:
    json.dump(data, f, indent=2)
"
    fi
    mv "$temp_file" "$CONFIG_FILE"
}

update_metadata() {
    local temp_file
    temp_file=$(mktemp)
    
    if $HAS_JQ; then
        jq --arg date "$(date -Iseconds)" '
            .updated_at = $date |
            .updated_by = "agent" |
            .version += 1
        ' "$CONFIG_FILE" > "$temp_file"
    else
        python3 -c "
import json
from datetime import datetime
with open('$CONFIG_FILE') as f:
    data = json.load(f)

data['updated_at'] = datetime.now().isoformat()
data['updated_by'] = 'agent'
data['version'] = data.get('version', 1) + 1

with open('$temp_file', 'w') as f:
    json.dump(data, f, indent=2)
"
    fi
    mv "$temp_file" "$CONFIG_FILE"
}

cmd_status() {
    echo "Strategy Status:"
    echo "=============="
    
    if $HAS_JQ; then
        jq -r '.strategies | to_entries[] | "\(.key): \(if .value.enabled then "ENABLED" else "DISABLED" end)\(.value.disabled_reason // "" | if . != "" then " (" + . + ")" else "" end)"' "$CONFIG_FILE"
    else
        python3 -c "
import json
with open('$CONFIG_FILE') as f:
    data = json.load(f)

for name, config in data['strategies'].items():
    status = 'ENABLED' if config.get('enabled', False) else 'DISABLED'
    reason = config.get('disabled_reason', '')
    if reason:
        print(f'{name}: {status} ({reason})')
    else:
        print(f'{name}: {status}')
"
    fi
}

cmd_enable() {
    local strategy="$1"
    
    # Check if strategy exists
    if ! json_get ".strategies.$strategy" >/dev/null 2>&1; then
        echo "Error: Strategy '$strategy' does not exist" >&2
        return 1
    fi
    
    # Enable the strategy
    local temp_file
    temp_file=$(mktemp)
    
    if $HAS_JQ; then
        jq --arg strategy "$strategy" --arg date "$(date -Iseconds)" '
            .strategies[$strategy].enabled = true |
            if .strategies[$strategy] | has("disabled_reason") then
                .strategies[$strategy] |= del(.disabled_reason)
            else . end |
            if .strategies[$strategy] | has("disabled_at") then
                .strategies[$strategy] |= del(.disabled_at)
            else . end |
            .updated_at = $date |
            .updated_by = "agent" |
            .version += 1
        ' "$CONFIG_FILE" > "$temp_file"
    else
        python3 -c "
import json
from datetime import datetime
with open('$CONFIG_FILE') as f:
    data = json.load(f)

strategy = '$strategy'
data['strategies'][strategy]['enabled'] = True
if 'disabled_reason' in data['strategies'][strategy]:
    del data['strategies'][strategy]['disabled_reason']
if 'disabled_at' in data['strategies'][strategy]:
    del data['strategies'][strategy]['disabled_at']

data['updated_at'] = datetime.now().isoformat()
data['updated_by'] = 'agent'
data['version'] = data.get('version', 1) + 1

with open('$temp_file', 'w') as f:
    json.dump(data, f, indent=2)
"
    fi
    mv "$temp_file" "$CONFIG_FILE"
    
    add_changelog_entry "agent" "Enabled strategy: $strategy"
    echo "Strategy '$strategy' enabled"
}

cmd_disable() {
    local strategy="$1"
    local reason="${2:-No reason provided}"
    
    # Check if strategy exists
    if ! json_get ".strategies.$strategy" >/dev/null 2>&1; then
        echo "Error: Strategy '$strategy' does not exist" >&2
        return 1
    fi
    
    # Disable the strategy
    local temp_file
    temp_file=$(mktemp)
    
    if $HAS_JQ; then
        jq --arg strategy "$strategy" --arg reason "$reason" --arg date "$(date -Iseconds)" '
            .strategies[$strategy].enabled = false |
            .strategies[$strategy].disabled_reason = $reason |
            .strategies[$strategy].disabled_at = $date |
            .updated_at = $date |
            .updated_by = "agent" |
            .version += 1
        ' "$CONFIG_FILE" > "$temp_file"
    else
        python3 -c "
import json
from datetime import datetime
with open('$CONFIG_FILE') as f:
    data = json.load(f)

strategy = '$strategy'
now = datetime.now().isoformat()
data['strategies'][strategy]['enabled'] = False
data['strategies'][strategy]['disabled_reason'] = '$reason'
data['strategies'][strategy]['disabled_at'] = now

data['updated_at'] = now
data['updated_by'] = 'agent'
data['version'] = data.get('version', 1) + 1

with open('$temp_file', 'w') as f:
    json.dump(data, f, indent=2)
"
    fi
    mv "$temp_file" "$CONFIG_FILE"
    
    add_changelog_entry "agent" "Disabled strategy: $strategy ($reason)"
    echo "Strategy '$strategy' disabled: $reason"
}

cmd_get() {
    local strategy="$1"
    
    if ! json_get ".strategies.$strategy" >/dev/null 2>&1; then
        echo "Error: Strategy '$strategy' does not exist" >&2
        return 1
    fi
    
    json_get ".strategies.$strategy"
}

# Main command dispatcher
case "${1:-}" in
    "status")
        cmd_status
        ;;
    "enable")
        if [[ -z "${2:-}" ]]; then
            echo "Usage: $0 enable <strategy>" >&2
            exit 1
        fi
        cmd_enable "$2"
        ;;
    "disable")
        if [[ -z "${2:-}" ]]; then
            echo "Usage: $0 disable <strategy> [reason]" >&2
            exit 1
        fi
        cmd_disable "$2" "${3:-}"
        ;;
    "get")
        if [[ -z "${2:-}" ]]; then
            echo "Usage: $0 get <strategy>" >&2
            exit 1
        fi
        cmd_get "$2"
        ;;
    *)
        echo "Usage: $0 {status|enable|disable|get}"
        echo ""
        echo "Commands:"
        echo "  status                     - Show all strategies and their status"
        echo "  enable <strategy>          - Enable a strategy"
        echo "  disable <strategy> [reason] - Disable a strategy with optional reason"
        echo "  get <strategy>             - Get configuration for a specific strategy"
        exit 1
        ;;
esac