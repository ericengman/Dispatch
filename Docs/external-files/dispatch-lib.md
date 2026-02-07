# Dispatch Integration Library

**Location:** `~/.claude/lib/dispatch.sh`
**Version:** 1.0.0
**Created:** 2026-02-03
**Phase:** 08-01 Foundation

## Purpose

Shared bash library that provides Dispatch integration functions for Claude Code skills.
Eliminates 40-60 lines of duplicated integration code per skill.

## Functions

### dispatch_init
- Creates screenshot run via POST to `/screenshots/run`
- Returns screenshot directory path
- Persists state to `/tmp/dispatch-state.XXXXXX`
- Falls back to temp directory if Dispatch unavailable

### dispatch_finalize
- Marks run complete via POST to `/screenshots/complete`
- Triggers Dispatch to scan for new screenshots
- Cleans up state file

### dispatch_get_project_name
- Extracts project name from `git rev-parse --show-toplevel`
- Fallback to "unknown" if not in git repo

### dispatch_check_health
- Checks if Dispatch is running via GET `/health`
- Returns 0 if healthy, 1 if not

### dispatch_get_state
- Debug utility to inspect current state

## Installation

The library is created by Phase 08-01 automation at:
```bash
~/.claude/lib/dispatch.sh
```

## Usage

```bash
source ~/.claude/lib/dispatch.sh

# Initialize
dispatch_init "My Screenshot Run" "iPhone 15 Pro"

# Take screenshots to $DISPATCH_SCREENSHOT_PATH

# Finalize
dispatch_finalize
```

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
