# Dispatch Integration Library

**Location:** `~/.claude/lib/dispatch.sh`
**Version:** 1.0.0
**Created:** 2026-02-03
**Phase:** 08-01 Foundation

## Purpose

Shared bash library that provides Dispatch integration functions for Claude Code skills.
Eliminates 40-60 lines of duplicated integration code per skill.

## API Reference

### dispatch_init

Creates a new screenshot run in Dispatch.

**Signature:** `dispatch_init RUN_NAME DEVICE_INFO`

**Parameters:**
- `RUN_NAME`: Descriptive name for this screenshot run (e.g., "Test Authentication Flow")
- `DEVICE_INFO`: Device description (e.g., "iPhone 15 Pro (iOS 17.2)")

**Behavior:**
- If Dispatch available: POST to `/screenshots/run`, sets `$DISPATCH_SCREENSHOT_PATH` to Dispatch-managed directory
- If Dispatch unavailable: Creates `/tmp/screenshots-[timestamp]`, sets `$DISPATCH_SCREENSHOT_PATH` to temp directory
- Persists state to temp file at `$DISPATCH_STATE_FILE`
- Outputs status to stderr for user visibility

**Returns:** 0 on success

### dispatch_finalize

Completes the current screenshot run.

**Signature:** `dispatch_finalize`

**Parameters:** None

**Behavior:**
- If Dispatch available: POST to `/screenshots/complete`, triggers scan for new screenshots
- If Dispatch unavailable: No-op (screenshots remain in temp directory)
- Cleans up state file
- Outputs completion message to stderr

**Returns:** 0 on success

### dispatch_get_project_name

Extracts the project name from the git repository.

**Signature:** `dispatch_get_project_name`

**Parameters:** None

**Behavior:**
- Runs `git rev-parse --show-toplevel` to get repo root
- Extracts directory name as project name
- Returns "unknown" if not in git repo

**Returns:** Project name string

### dispatch_check_health

Checks if Dispatch is running and accepting connections.

**Signature:** `dispatch_check_health`

**Parameters:** None

**Behavior:**
- GET request to `/health` endpoint
- Checks for HTTP 200 response
- Returns 0 if healthy, 1 if not

**Returns:** 0 if Dispatch available, 1 otherwise

### dispatch_get_state

Debug utility to inspect current state.

**Signature:** `dispatch_get_state`

**Parameters:** None

**Behavior:**
- Outputs contents of state file to stdout
- Shows DISPATCH_AVAILABLE, DISPATCH_RUN_ID, DISPATCH_SCREENSHOT_PATH

**Returns:** 0 on success

## Installation

The library is created by Phase 08-01 automation at:
```bash
~/.claude/lib/dispatch.sh
```

## Usage

### Single-Run Pattern

For skills that perform one test/exploration session per execution (test-feature, explore-app, qa-feature):

```bash
source ~/.claude/lib/dispatch.sh

# Initialize at start of skill
dispatch_init "Test Authentication Flow" "iPhone 15 Pro (iOS 17.2)"

# Source state to get variables
source "$DISPATCH_STATE_FILE"

# Take screenshots during skill execution
mcp__ios-simulator__screenshot(path: "$DISPATCH_SCREENSHOT_PATH/01-login-screen.png")
# ... more screenshots ...
mcp__ios-simulator__screenshot(path: "$DISPATCH_SCREENSHOT_PATH/05-success.png")

# Finalize when complete
dispatch_finalize
```

### Multi-Run Pattern

For skills that test multiple configurations in a single execution (test-dynamic-type):

```bash
source ~/.claude/lib/dispatch.sh

for SIZE in "xSmall" "Small" "Medium" "Large" "xLarge"; do
    # Create a run for each configuration
    dispatch_init "Dynamic Type Test - $SIZE" "iPhone 15 Pro (iOS 17.2)"

    # Source state to get variables
    source "$DISPATCH_STATE_FILE"

    # Configure simulator
    # ... set dynamic type size ...

    # Take screenshots for this configuration
    mcp__ios-simulator__screenshot(path: "$DISPATCH_SCREENSHOT_PATH/home-$SIZE.png")
    mcp__ios-simulator__screenshot(path: "$DISPATCH_SCREENSHOT_PATH/detail-$SIZE.png")

    # Finalize before next iteration
    dispatch_finalize
done
```

### Fallback Behavior

When Dispatch is not running:
- `dispatch_init` creates `/tmp/screenshots-[timestamp]` directory
- Clear message to stderr: "Dispatch not available - screenshots saved to /tmp/..."
- `$DISPATCH_SCREENSHOT_PATH` points to temp directory
- `dispatch_finalize` completes successfully (no-op)
- Skills continue working without Dispatch integration

## API Endpoints

- **POST** `/screenshots/run` - Create new screenshot run
- **POST** `/screenshots/complete` - Mark run complete
- **GET** `/health` - Health check

## State Persistence

State is persisted between bash calls via temp file:
```
DISPATCH_AVAILABLE=true|false
DISPATCH_RUN_ID=<uuid>
DISPATCH_SCREENSHOT_PATH=<path>
DISPATCH_STATE_FILE=<temp file path>
```

The temp file path is exported as `DISPATCH_STATE_FILE` environment variable.
