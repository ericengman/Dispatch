#!/bin/bash
# session-start.sh - Detect Dispatch availability at session start
# Created by Phase 09-01: Hook Integration

# Check if dispatch.sh library exists before sourcing
if [ ! -f ~/.claude/lib/dispatch.sh ]; then
    echo "Dispatch library not installed" >&2
    exit 0
fi

# Source the library
source ~/.claude/lib/dispatch.sh

# Perform health check using library function
if dispatch_check_health; then
    # Dispatch is available
    echo "Dispatch server detected (port ${DISPATCH_DEFAULT_PORT})" >&2

    # Set environment variables for session (only if CLAUDE_ENV_FILE is set)
    if [ -n "$CLAUDE_ENV_FILE" ]; then
        echo "export DISPATCH_AVAILABLE=true" >> "$CLAUDE_ENV_FILE"
        echo "export DISPATCH_PORT=${DISPATCH_DEFAULT_PORT}" >> "$CLAUDE_ENV_FILE"
    fi

    # Output context for Claude to see (stdout)
    echo "Dispatch integration active - screenshot commands available"
else
    # Dispatch not available
    echo "Dispatch server not detected at localhost:${DISPATCH_DEFAULT_PORT}" >&2

    # Set environment variable indicating unavailability
    if [ -n "$CLAUDE_ENV_FILE" ]; then
        echo "export DISPATCH_AVAILABLE=false" >> "$CLAUDE_ENV_FILE"
    fi

    # Output context for Claude to see (stdout)
    echo "Dispatch not running - screenshot features unavailable"
fi

# Always exit 0 (hook failure should not block session)
exit 0
