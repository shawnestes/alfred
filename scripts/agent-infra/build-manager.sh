#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_STATE_FILE="$SCRIPT_DIR/build-state.json"

# Check if jq is available, fallback to python3
HAS_JQ=false
if command -v jq >/dev/null 2>&1; then
    HAS_JQ=true
fi

# Validate inputs
validate_app() {
    local app="$1"
    if [[ ! "$app" =~ ^(dearnote|noyoupick)$ ]]; then
        echo "Error: Invalid app '$app'. Must be 'dearnote' or 'noyoupick'" >&2
        return 1
    fi
}

validate_platform() {
    local platform="$1"
    if [[ ! "$platform" =~ ^(ios|android)$ ]]; then
        echo "Error: Invalid platform '$platform'. Must be 'ios' or 'android'" >&2
        return 1
    fi
}

# Get current build number
get_current_build() {
    local app="$1"
    local platform="$2"
    
    validate_app "$app"
    validate_platform "$platform"
    
    if [[ ! -f "$BUILD_STATE_FILE" ]]; then
        echo "Error: Build state file not found: $BUILD_STATE_FILE" >&2
        return 1
    fi
    
    local build_number
    if $HAS_JQ; then
        build_number=$(jq -r ".$app.$platform.build // empty" "$BUILD_STATE_FILE")
    else
        build_number=$(python3 -c "
import json, sys
try:
    with open('$BUILD_STATE_FILE') as f:
        data = json.load(f)
    build = data.get('$app', {}).get('$platform', {}).get('build')
    if build is not None:
        print(build)
    else:
        sys.exit(1)
except (FileNotFoundError, json.JSONDecodeError, KeyError):
    sys.exit(1)
")
    fi
    
    if [[ -z "$build_number" ]]; then
        echo "Error: Build number not found for $app/$platform" >&2
        return 1
    fi
    
    echo "$build_number"
}

# Increment and save build number
increment_build() {
    local app="$1"
    local platform="$2"
    
    validate_app "$app"
    validate_platform "$platform"
    
    if [[ ! -f "$BUILD_STATE_FILE" ]]; then
        echo "Error: Build state file not found: $BUILD_STATE_FILE" >&2
        return 1
    fi
    
    local current_build
    current_build=$(get_current_build "$app" "$platform")
    local new_build=$((current_build + 1))
    
    # Update the JSON file
    local temp_file
    temp_file=$(mktemp)
    
    if $HAS_JQ; then
        jq ".$app.$platform.build = $new_build" "$BUILD_STATE_FILE" > "$temp_file"
    else
        python3 -c "
import json
with open('$BUILD_STATE_FILE') as f:
    data = json.load(f)

data['$app']['$platform']['build'] = $new_build

with open('$temp_file', 'w') as f:
    json.dump(data, f, indent=2)
"
    fi
    
    mv "$temp_file" "$BUILD_STATE_FILE"
    echo "$new_build"
}

# Get version string
get_version() {
    local app="$1"
    local platform="$2"
    
    validate_app "$app"
    validate_platform "$platform"
    
    if [[ ! -f "$BUILD_STATE_FILE" ]]; then
        echo "Error: Build state file not found: $BUILD_STATE_FILE" >&2
        return 1
    fi
    
    local version
    if $HAS_JQ; then
        version=$(jq -r ".$app.$platform.version // empty" "$BUILD_STATE_FILE")
    else
        version=$(python3 -c "
import json, sys
try:
    with open('$BUILD_STATE_FILE') as f:
        data = json.load(f)
    version = data.get('$app', {}).get('$platform', {}).get('version')
    if version is not None:
        print(version)
    else:
        sys.exit(1)
except (FileNotFoundError, json.JSONDecodeError, KeyError):
    sys.exit(1)
")
    fi
    
    if [[ -z "$version" ]]; then
        echo "Error: Version not found for $app/$platform" >&2
        return 1
    fi
    
    echo "$version"
}

# Show current state
show_current_state() {
    local app="$1"
    local platform="$2"
    
    local version
    local build
    
    version=$(get_version "$app" "$platform")
    build=$(get_current_build "$app" "$platform")
    
    echo "App: $app"
    echo "Platform: $platform"
    echo "Version: $version"
    echo "Build: $build"
}

# List all apps and platforms
list_all() {
    if [[ ! -f "$BUILD_STATE_FILE" ]]; then
        echo "Error: Build state file not found: $BUILD_STATE_FILE" >&2
        return 1
    fi
    
    echo "Build State Summary:"
    echo "==================="
    
    if $HAS_JQ; then
        jq -r '
            to_entries[] |
            .key as $app |
            .value | to_entries[] |
            "\($app)/\(.key): v\(.value.version) build \(.value.build)"
        ' "$BUILD_STATE_FILE"
    else
        python3 -c "
import json
with open('$BUILD_STATE_FILE') as f:
    data = json.load(f)

for app, platforms in data.items():
    for platform, info in platforms.items():
        version = info.get('version', 'unknown')
        build = info.get('build', 'unknown')
        print(f'{app}/{platform}: v{version} build {build}')
"
    fi
}

# Main command dispatcher
case "${1:-}" in
    "current")
        if [[ -z "${2:-}" || -z "${3:-}" ]]; then
            echo "Usage: $0 current <app> <platform>" >&2
            echo "Example: $0 current dearnote ios" >&2
            exit 1
        fi
        get_current_build "$2" "$3"
        ;;
    "next")
        if [[ -z "${2:-}" || -z "${3:-}" ]]; then
            echo "Usage: $0 next <app> <platform>" >&2
            echo "Example: $0 next dearnote ios" >&2
            exit 1
        fi
        increment_build "$2" "$3"
        ;;
    "version")
        if [[ -z "${2:-}" || -z "${3:-}" ]]; then
            echo "Usage: $0 version <app> <platform>" >&2
            echo "Example: $0 version dearnote ios" >&2
            exit 1
        fi
        get_version "$2" "$3"
        ;;
    "show")
        if [[ -z "${2:-}" || -z "${3:-}" ]]; then
            echo "Usage: $0 show <app> <platform>" >&2
            echo "Example: $0 show dearnote ios" >&2
            exit 1
        fi
        show_current_state "$2" "$3"
        ;;
    "list")
        list_all
        ;;
    *)
        echo "Usage: $0 {current|next|version|show|list}"
        echo ""
        echo "Commands:"
        echo "  current <app> <platform>  - Get current build number"
        echo "  next <app> <platform>     - Increment and get next build number"
        echo "  version <app> <platform>  - Get version string"
        echo "  show <app> <platform>     - Show all info for app/platform"
        echo "  list                      - List all apps and their current state"
        echo ""
        echo "Apps: dearnote, noyoupick"
        echo "Platforms: ios, android"
        echo ""
        echo "Examples:"
        echo "  $0 current dearnote ios"
        echo "  $0 next noyoupick android"
        echo "  $0 list"
        exit 1
        ;;
esac