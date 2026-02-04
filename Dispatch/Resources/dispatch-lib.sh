#!/bin/bash
#
# dispatch.sh - Shared Dispatch integration library for Claude Code skills
#
# Usage:
#   source ~/.claude/lib/dispatch.sh
#   dispatch_init "Run Name" "Device Info"
#   # ... take screenshots ...
#   dispatch_finalize
#

# Library version
DISPATCH_LIB_VERSION="1.0.0"

# Default Dispatch server configuration
DISPATCH_DEFAULT_PORT=19847

# ============================================================================
# Helper Functions
# ============================================================================

# Get project name from git repository root
# Returns basename of git root, or "unknown" if not in a git repo
dispatch_get_project_name() {
    local git_root
    git_root=$(git rev-parse --show-toplevel 2>/dev/null)

    if [[ -n "$git_root" ]]; then
        basename "$git_root"
    else
        echo "unknown"
    fi
}

# Check if Dispatch server is running and healthy
# Returns 0 if healthy, 1 if not
dispatch_check_health() {
    local response
    response=$(curl -s "http://localhost:${DISPATCH_DEFAULT_PORT}/health" 2>/dev/null)

    if [[ "$response" == *'"status":"ok"'* ]]; then
        return 0
    else
        return 1
    fi
}

# ============================================================================
# Main Functions
# ============================================================================

# Initialize a new screenshot run with Dispatch
# Creates a state file to persist run information between bash calls
#
# Parameters:
#   $1 - run_name (optional, defaults to "Screenshot Run")
#   $2 - device_info (optional, defaults to empty)
#
# Exports:
#   DISPATCH_STATE_FILE - Path to temp file containing run state
#
# State file contains:
#   DISPATCH_AVAILABLE=true|false
#   DISPATCH_RUN_ID=<uuid>
#   DISPATCH_SCREENSHOT_PATH=<path>
#   DISPATCH_STATE_FILE=<this file path>
#
dispatch_init() {
    local run_name="${1:-Screenshot Run}"
    local device_info="${2:-}"
    local project_name

    # Get project name from git
    project_name=$(dispatch_get_project_name)

    # Create state file
    local state_file
    state_file=$(mktemp /tmp/dispatch-state.XXXXXX)

    # Check if Dispatch is available
    if dispatch_check_health; then
        # Dispatch is running - create screenshot run
        local json_payload
        json_payload='{"project":"'"$project_name"'","name":"'"$run_name"'"'

        if [[ -n "$device_info" ]]; then
            json_payload="${json_payload}"',"device":"'"$device_info"'"}'
        else
            json_payload="${json_payload}"'}'
        fi

        local response
        response=$(curl -s -X POST \
            -H "Content-Type: application/json" \
            -d "$json_payload" \
            "http://localhost:${DISPATCH_DEFAULT_PORT}/screenshots/run" 2>/dev/null)

        # Parse response to extract runId and path
        # Using grep/cut to avoid jq dependency
        local run_id
        local screenshot_path

        run_id=$(echo "$response" | grep -o '"runId":"[^"]*"' | cut -d'"' -f4)
        screenshot_path=$(echo "$response" | grep -o '"path":"[^"]*"' | cut -d'"' -f4)

        if [[ -n "$run_id" ]] && [[ -n "$screenshot_path" ]]; then
            # Success - write state file
            {
                echo "DISPATCH_AVAILABLE=true"
                echo "DISPATCH_RUN_ID=\"$run_id\""
                echo "DISPATCH_SCREENSHOT_PATH=\"$screenshot_path\""
                echo "DISPATCH_STATE_FILE=\"$state_file\""
            } > "$state_file"

            echo "Dispatch run created: $run_id" >&2
            echo "Screenshots will be saved to: $screenshot_path" >&2

            # Export state file path for subsequent calls
            export DISPATCH_STATE_FILE="$state_file"

            return 0
        else
            # Failed to parse response - fall back to temp directory
            echo "Warning: Failed to parse Dispatch response, using fallback" >&2
            local fallback_path="/tmp/screenshots-$(date +%s)"
            mkdir -p "$fallback_path"

            {
                echo "DISPATCH_AVAILABLE=false"
                echo "DISPATCH_RUN_ID=\"\""
                echo "DISPATCH_SCREENSHOT_PATH=\"$fallback_path\""
                echo "DISPATCH_STATE_FILE=\"$state_file\""
            } > "$state_file"

            echo "Dispatch not running - screenshots saved to: $fallback_path" >&2

            export DISPATCH_STATE_FILE="$state_file"
            return 1
        fi
    else
        # Dispatch not running - use fallback directory
        local fallback_path="/tmp/screenshots-$(date +%s)"
        mkdir -p "$fallback_path"

        {
            echo "DISPATCH_AVAILABLE=false"
            echo "DISPATCH_RUN_ID=\"\""
            echo "DISPATCH_SCREENSHOT_PATH=\"$fallback_path\""
            echo "DISPATCH_STATE_FILE=\"$state_file\""
        } > "$state_file"

        echo "Dispatch not running - screenshots saved to: $fallback_path" >&2

        export DISPATCH_STATE_FILE="$state_file"
        return 1
    fi
}

# Finalize the screenshot run and mark it complete in Dispatch
# Reads state from DISPATCH_STATE_FILE environment variable
# Cleans up the state file after completion
#
dispatch_finalize() {
    if [[ -z "$DISPATCH_STATE_FILE" ]] || [[ ! -f "$DISPATCH_STATE_FILE" ]]; then
        echo "Error: No dispatch state file found. Did you call dispatch_init?" >&2
        return 1
    fi

    # Source the state file to get variables
    # shellcheck disable=SC1090
    source "$DISPATCH_STATE_FILE"

    if [[ "$DISPATCH_AVAILABLE" == "true" ]] && [[ -n "$DISPATCH_RUN_ID" ]]; then
        # Dispatch was available - mark run as complete
        local json_payload='{"runId":"'"$DISPATCH_RUN_ID"'"}'

        curl -s -X POST \
            -H "Content-Type: application/json" \
            -d "$json_payload" \
            "http://localhost:${DISPATCH_DEFAULT_PORT}/screenshots/complete" >/dev/null 2>&1

        echo "Dispatch run finalized - screenshots ready for review" >&2
    else
        # Dispatch was not running - just inform user
        echo "Dispatch was not running - screenshots remain in: $DISPATCH_SCREENSHOT_PATH" >&2
    fi

    # Clean up state file
    rm -f "$DISPATCH_STATE_FILE"
    unset DISPATCH_STATE_FILE

    return 0
}

# Get the current dispatch state (for debugging)
# Outputs the contents of the state file to stdout
#
dispatch_get_state() {
    if [[ -z "$DISPATCH_STATE_FILE" ]] || [[ ! -f "$DISPATCH_STATE_FILE" ]]; then
        echo "No dispatch state file found" >&2
        return 1
    fi

    echo "Dispatch State:" >&2
    cat "$DISPATCH_STATE_FILE"

    return 0
}
