#!/bin/bash

set -euo pipefail

# Configuration
REPOS=(
  "quickdraw:/root/.openclaw/agents/quickdraw/workspace/repo"
  "dearnote:/root/.openclaw/agents/dearnote/workspace/repo"  
  "ghostreel:/root/.openclaw/agents/ghostreel/workspace/repo"
  "noyoupick:/root/.openclaw/agents/noyoupick/workspace/repo"
)

SERVICES=(
  "quickdraw:openclaw-quickdraw,quickdraw-strategy,quickdraw-data-collector"
  "dearnote:openclaw-dearnote"
  "ghostreel:openclaw-ghostreel"
  "noyoupick:openclaw-noyoupick"
)

# JSON helper functions
HAS_JQ=false
if command -v jq >/dev/null 2>&1; then
    HAS_JQ=true
fi

# Check if project exists in config
find_repo() {
    local project="$1"
    for repo_entry in "${REPOS[@]}"; do
        if [[ "$repo_entry" =~ ^${project}: ]]; then
            echo "${repo_entry#*:}"
            return 0
        fi
    done
    return 1
}

find_services() {
    local project="$1"
    for service_entry in "${SERVICES[@]}"; do
        if [[ "$service_entry" =~ ^${project}: ]]; then
            echo "${service_entry#*:}"
            return 0
        fi
    done
    return 1
}

# Health check functions
check_systemctl() {
    local project="$1"
    local services
    local result="pass"
    local details=""
    
    services=$(find_services "$project")
    if [[ -z "$services" ]]; then
        echo "\"systemctl\": {\"status\": \"skip\", \"reason\": \"No services configured\"}"
        return
    fi
    
    IFS=',' read -ra service_array <<< "$services"
    for service in "${service_array[@]}"; do
        if ! systemctl is-active "$service" >/dev/null 2>&1; then
            result="fail"
            local status
            status=$(systemctl is-active "$service" 2>/dev/null || echo "inactive")
            details="${details}Service $service is $status. "
        fi
    done
    
    if [[ "$result" == "pass" ]]; then
        echo "\"systemctl\": {\"status\": \"pass\"}"
    else
        echo "\"systemctl\": {\"status\": \"fail\", \"details\": \"${details%% }\"}"
    fi
}

check_error_logs() {
    local project="$1"
    local result="pass"
    local details=""
    local error_count=0
    
    # Check systemd logs for the last hour
    local services
    services=$(find_services "$project")
    if [[ -n "$services" ]]; then
        IFS=',' read -ra service_array <<< "$services"
        for service in "${service_array[@]}"; do
            local service_errors
            service_errors=$(journalctl -u "$service" --since="1 hour ago" --priority=err --no-pager -q 2>/dev/null | wc -l || echo "0")
            service_errors=${service_errors:-0}
            if [[ "$service_errors" -gt 0 ]] 2>/dev/null; then
                error_count=$((error_count + service_errors))
                details="${details}$service: $service_errors errors. "
            fi
        done
    fi
    
    # Check project-specific log files if they exist
    local repo_path
    repo_path=$(find_repo "$project" 2>/dev/null || echo "")
    if [[ -n "$repo_path" && -d "$repo_path" ]]; then
        # Look for common log locations
        local log_dirs=("$repo_path/logs" "$repo_path/log" "$repo_path/.logs")
        for log_dir in "${log_dirs[@]}"; do
            if [[ -d "$log_dir" ]]; then
                local file_errors
                file_errors=$(find "$log_dir" -name "*.log" -mtime -1 -exec grep -i "error\|exception\|fatal" {} \; 2>/dev/null | wc -l || echo "0")
                file_errors=${file_errors:-0}
                if [[ "$file_errors" -gt 0 ]] 2>/dev/null; then
                    error_count=$((error_count + file_errors))
                    details="${details}Log files: $file_errors errors. "
                fi
                break
            fi
        done
    fi
    
    # Special case for Quickdraw live logs
    if [[ "$project" == "quickdraw" && -f "/var/log/quickdraw-live.log" ]]; then
        local live_errors
        live_errors=$(tail -n 1000 /var/log/quickdraw-live.log | grep -E "error|Error|ERROR|exception|Exception|EXCEPTION|fatal|Fatal|FATAL" | wc -l || echo "0")
        live_errors=${live_errors:-0}
        if [[ "$live_errors" -gt 0 ]] 2>/dev/null; then
            error_count=$((error_count + live_errors))
            details="${details}Live log: $live_errors errors. "
        fi
    fi
    
    if [[ "$error_count" -gt 0 ]]; then
        result="fail"
    fi
    
    if [[ "$result" == "pass" ]]; then
        echo "\"error_logs\": {\"status\": \"pass\"}"
    else
        echo "\"error_logs\": {\"status\": \"fail\", \"details\": \"$details(total: $error_count)\"}"
    fi
}

check_orphan_processes() {
    local project="$1"
    local result="pass"
    local details=""
    local orphan_count=0
    
    # Look for processes containing the project name that might be orphaned
    local processes
    processes=$(ps aux | grep -i "$project" | grep -v grep | grep -v "health-check" | grep -v "systemctl" || true)
    
    if [[ -n "$processes" ]]; then
        # Count processes that aren't clearly managed by systemd
        local services
        services=$(find_services "$project")
        if [[ -n "$services" ]]; then
            IFS=',' read -ra service_array <<< "$services"
            
            # Get PIDs of legitimate systemd services
            local legitimate_pids=""
            for service in "${service_array[@]}"; do
                local service_pid
                service_pid=$(systemctl show "$service" --property=MainPID --value 2>/dev/null || echo "0")
                if [[ "$service_pid" != "0" && "$service_pid" != "" ]]; then
                    legitimate_pids="$legitimate_pids $service_pid"
                fi
            done
            
            # Check each process
            while IFS= read -r process_line; do
                if [[ -n "$process_line" ]]; then
                    local pid
                    pid=$(echo "$process_line" | awk '{print $2}')
                    if [[ ! "$legitimate_pids" =~ $pid ]]; then
                        orphan_count=$((orphan_count + 1))
                        local cmd
                        cmd=$(echo "$process_line" | awk '{for(i=11;i<=NF;i++) printf "%s ", $i; printf "\n"}' | cut -c1-50)
                        details="${details}PID $pid: $cmd. "
                    fi
                fi
            done <<< "$processes"
        else
            # No services configured, all processes might be orphans
            orphan_count=$(echo "$processes" | wc -l)
            details="Found $orphan_count processes (no services configured to verify). "
        fi
    fi
    
    if [[ "$orphan_count" -gt 0 ]]; then
        result="fail"
    fi
    
    if [[ "$result" == "pass" ]]; then
        echo "\"orphan_processes\": {\"status\": \"pass\"}"
    else
        echo "\"orphan_processes\": {\"status\": \"fail\", \"details\": \"${details%% }\"}"
    fi
}

check_npm_audit() {
    local project="$1"
    local repo_path
    repo_path=$(find_repo "$project" 2>/dev/null || echo "")
    
    if [[ -z "$repo_path" || ! -d "$repo_path" ]]; then
        echo "\"npm_audit\": {\"status\": \"skip\", \"reason\": \"Repository not found\"}"
        return
    fi
    
    if [[ ! -f "$repo_path/package.json" ]]; then
        echo "\"npm_audit\": {\"status\": \"skip\", \"reason\": \"No package.json found\"}"
        return
    fi
    
    cd "$repo_path"
    local audit_output
    local audit_exit_code=0
    
    # Run npm audit and capture both output and exit code
    audit_output=$(npm audit --audit-level=high --json 2>/dev/null || audit_exit_code=$?)
    
    if [[ "$audit_exit_code" -eq 0 ]]; then
        echo "\"npm_audit\": {\"status\": \"pass\"}"
    else
        # Extract vulnerability count from JSON output
        local vuln_count="unknown"
        if [[ -n "$audit_output" ]]; then
            if $HAS_JQ; then
                vuln_count=$(echo "$audit_output" | jq -r '.metadata.vulnerabilities.total // "unknown"' 2>/dev/null || echo "unknown")
            else
                vuln_count=$(echo "$audit_output" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get('metadata', {}).get('vulnerabilities', {}).get('total', 'unknown'))
except:
    print('unknown')
" 2>/dev/null || echo "unknown")
            fi
        fi
        echo "\"npm_audit\": {\"status\": \"fail\", \"details\": \"Found $vuln_count vulnerabilities\"}"
    fi
}

# Main health check function
run_health_check() {
    local project="$1"
    
    echo "{"
    echo "  \"project\": \"$project\","
    echo "  \"timestamp\": \"$(date -Iseconds)\","
    echo "  \"checks\": {"
    
    # Run all checks
    local systemctl_result
    local error_logs_result
    local orphan_processes_result
    local npm_audit_result
    
    systemctl_result=$(check_systemctl "$project")
    error_logs_result=$(check_error_logs "$project")
    orphan_processes_result=$(check_orphan_processes "$project")
    npm_audit_result=$(check_npm_audit "$project")
    
    echo "    $systemctl_result,"
    echo "    $error_logs_result,"
    echo "    $orphan_processes_result,"
    echo "    $npm_audit_result"
    
    echo "  },"
    
    # Overall status
    local overall="pass"
    if [[ "$systemctl_result" =~ \"status\":[[:space:]]*\"fail\" ]] ||
       [[ "$error_logs_result" =~ \"status\":[[:space:]]*\"fail\" ]] ||
       [[ "$orphan_processes_result" =~ \"status\":[[:space:]]*\"fail\" ]] ||
       [[ "$npm_audit_result" =~ \"status\":[[:space:]]*\"fail\" ]]; then
        overall="fail"
    fi
    
    echo "  \"overall\": \"$overall\""
    echo "}"
}

# Validate input
if [[ -z "${1:-}" ]]; then
    echo "Usage: $0 <project>"
    echo ""
    echo "Available projects:"
    for repo_entry in "${REPOS[@]}"; do
        echo "  ${repo_entry%%:*}"
    done
    exit 1
fi

project="$1"

# Validate project exists
if ! find_repo "$project" >/dev/null 2>&1; then
    echo "{\"error\": \"Unknown project: $project\"}" >&2
    exit 1
fi

# Run the health check
run_health_check "$project"