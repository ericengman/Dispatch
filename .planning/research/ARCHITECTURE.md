# Architecture Patterns: Skill-to-Dispatch Screenshot Integration

**Domain:** Cross-skill configuration sharing for macOS/Claude Code integration
**Researched:** 2026-02-03
**Confidence:** HIGH (verified against official Claude Code documentation and existing codebase)

## Executive Summary

The core problem is that skills currently duplicate the Dispatch API integration code, and many skills don't implement it at all. Screenshots end up in temp folders instead of being routed to Dispatch for user review and annotation.

**Recommended architecture:** A **shared bash library** (`~/.claude/lib/dispatch.sh`) that skills source, combined with a **SessionStart hook** that sets environment variables for the current session. This provides:
- Single source of truth for integration code
- Zero-config for skill authors (just source the library)
- Graceful fallback when Dispatch isn't running
- Automatic environment setup via Claude Code's native hook system

## Current State Analysis

### Existing Components

**Dispatch HookServer (Port 19847)**
- Already implements all required endpoints:
  - `GET /health` - Check if Dispatch is running
  - `POST /screenshots/run` - Create a run, returns `{runId, path}`
  - `POST /screenshots/complete` - Mark run complete, trigger scan
  - `GET /screenshots/location?project=X` - Get screenshot directory
- NWListener-based, already works reliably
- No changes needed to the server

**ScreenshotWatcherService**
- Watches the screenshot directory for new runs
- Creates SwiftData records when screenshots appear
- Handles cleanup of old runs
- Works correctly when screenshots arrive in the right location

**Existing Skills**
- Skills like `test-feature`, `explore-app`, `test-dynamic-type` already document the API
- Each skill duplicates ~30 lines of bash for Dispatch integration
- Many skills skip the integration entirely (problem source)

### The Gap

Skills are supposed to:
1. Check if Dispatch is running (`curl /health`)
2. Create a run (`POST /screenshots/run`)
3. Save screenshots to the returned path
4. Mark complete (`POST /screenshots/complete`)

But in practice:
- Integration code is copy-pasted (and often outdated)
- New skills skip it because it's "optional"
- Skills save to `/tmp/` or default locations
- Dispatch never sees the screenshots

## Recommended Architecture

### Pattern: Shared Library + SessionStart Hook

```
~/.claude/
├── lib/
│   └── dispatch.sh          # Shared library (NEW)
├── hooks/
│   └── session-start.sh     # SessionStart hook (NEW)
└── skills/
    └── */SKILL.md           # Skills source the library
```

### Component 1: Shared Library (`~/.claude/lib/dispatch.sh`)

A sourceable bash library that encapsulates all Dispatch integration logic.

```bash
#!/bin/bash
# ~/.claude/lib/dispatch.sh
# Dispatch Screenshot Integration Library
# Source this in skills: . ~/.claude/lib/dispatch.sh

DISPATCH_PORT="${DISPATCH_PORT:-19847}"
DISPATCH_BASE_URL="http://localhost:${DISPATCH_PORT}"

# Check if Dispatch is running
# Returns: 0 if running, 1 if not
dispatch_is_running() {
    local health
    health=$(curl -s --connect-timeout 1 "${DISPATCH_BASE_URL}/health" 2>/dev/null)
    [[ "$health" == *'"status":"ok"'* ]]
}

# Create a screenshot run
# Args: $1=project_name $2=run_name $3=device_info (optional)
# Sets: DISPATCH_RUN_ID, DISPATCH_SCREENSHOT_PATH
# Returns: 0 on success, 1 on failure
dispatch_create_run() {
    local project="${1:-$(basename "$(pwd)")}"
    local name="${2:-Screenshot Run}"
    local device="${3:-}"

    if ! dispatch_is_running; then
        # Fallback to temp directory
        DISPATCH_RUN_ID=""
        DISPATCH_SCREENSHOT_PATH="/tmp/dispatch-screenshots-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$DISPATCH_SCREENSHOT_PATH"
        return 1
    fi

    local response
    response=$(curl -s -X POST "${DISPATCH_BASE_URL}/screenshots/run" \
        -H "Content-Type: application/json" \
        -d "{\"project\":\"${project}\",\"name\":\"${name}\",\"device\":\"${device}\"}" 2>/dev/null)

    if [[ -z "$response" ]]; then
        DISPATCH_RUN_ID=""
        DISPATCH_SCREENSHOT_PATH="/tmp/dispatch-screenshots-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$DISPATCH_SCREENSHOT_PATH"
        return 1
    fi

    # Parse response - handle both camelCase and snake_case
    DISPATCH_RUN_ID=$(echo "$response" | grep -oE '"runId"\s*:\s*"[^"]+"' | cut -d'"' -f4)
    [[ -z "$DISPATCH_RUN_ID" ]] && DISPATCH_RUN_ID=$(echo "$response" | grep -oE '"run_id"\s*:\s*"[^"]+"' | cut -d'"' -f4)

    DISPATCH_SCREENSHOT_PATH=$(echo "$response" | grep -oE '"path"\s*:\s*"[^"]+"' | cut -d'"' -f4 | tr -d '\\')

    if [[ -n "$DISPATCH_RUN_ID" && -n "$DISPATCH_SCREENSHOT_PATH" ]]; then
        export DISPATCH_RUN_ID
        export DISPATCH_SCREENSHOT_PATH
        return 0
    fi

    DISPATCH_RUN_ID=""
    DISPATCH_SCREENSHOT_PATH="/tmp/dispatch-screenshots-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$DISPATCH_SCREENSHOT_PATH"
    return 1
}

# Complete a screenshot run
# Args: $1=run_id (optional, defaults to DISPATCH_RUN_ID)
# Returns: 0 on success, 1 on failure
dispatch_complete_run() {
    local run_id="${1:-$DISPATCH_RUN_ID}"

    [[ -z "$run_id" ]] && return 1

    curl -s -X POST "${DISPATCH_BASE_URL}/screenshots/complete" \
        -H "Content-Type: application/json" \
        -d "{\"runId\":\"${run_id}\"}" 2>/dev/null

    return 0
}

# Get screenshot save path (without creating a run)
# Args: $1=project_name (optional)
# Returns: path on stdout
dispatch_get_screenshot_path() {
    local project="${1:-$(basename "$(pwd)")}"

    if dispatch_is_running; then
        local response
        response=$(curl -s "${DISPATCH_BASE_URL}/screenshots/location?project=${project}" 2>/dev/null)
        local path
        path=$(echo "$response" | grep -oE '"path"\s*:\s*"[^"]+"' | cut -d'"' -f4)
        [[ -n "$path" ]] && echo "$path" && return 0
    fi

    # Fallback
    echo "/tmp/dispatch-screenshots-${project}"
}

# Initialize Dispatch for a skill session
# Call this at the start of any skill that takes screenshots
# Args: $1=run_name $2=project_name (optional)
dispatch_init() {
    local run_name="${1:-Skill Run}"
    local project="${2:-$(basename "$(pwd)")}"
    local device
    device=$(xcrun simctl list devices booted 2>/dev/null | grep -m1 "iPhone\|iPad" | sed 's/.*(\([^)]*\)).*/\1/' | xargs)

    dispatch_create_run "$project" "$run_name" "$device"

    if [[ -n "$DISPATCH_RUN_ID" ]]; then
        echo "Dispatch: Run created (${DISPATCH_RUN_ID})"
        echo "Screenshots: ${DISPATCH_SCREENSHOT_PATH}"
    else
        echo "Dispatch: Not running - using fallback path"
        echo "Screenshots: ${DISPATCH_SCREENSHOT_PATH}"
    fi
}

# Finalize Dispatch session
# Call this at the end of any skill that takes screenshots
dispatch_finalize() {
    if [[ -n "$DISPATCH_RUN_ID" ]]; then
        dispatch_complete_run
        echo "Dispatch: Run completed - screenshots available for review"
    fi
}
```

### Component 2: SessionStart Hook

A hook that runs when Claude Code starts, setting up environment variables for the session.

**Location:** `~/.claude/hooks/session-start.sh` or configured in `~/.claude/settings.json`

```bash
#!/bin/bash
# SessionStart hook: Set up Dispatch environment
# This runs when Claude Code starts and persists env vars for the session

DISPATCH_PORT="${DISPATCH_PORT:-19847}"

# Check if Dispatch is running
if curl -s --connect-timeout 1 "http://localhost:${DISPATCH_PORT}/health" 2>/dev/null | grep -q '"status":"ok"'; then
    # Dispatch is running - export to CLAUDE_ENV_FILE for session persistence
    if [[ -n "$CLAUDE_ENV_FILE" ]]; then
        echo "export DISPATCH_AVAILABLE=true" >> "$CLAUDE_ENV_FILE"
        echo "export DISPATCH_PORT=${DISPATCH_PORT}" >> "$CLAUDE_ENV_FILE"
        echo "export DISPATCH_BASE_URL=http://localhost:${DISPATCH_PORT}" >> "$CLAUDE_ENV_FILE"
    fi

    # Return context for Claude
    echo '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"Dispatch app is running. Screenshots can be routed through Dispatch for review."}}'
else
    if [[ -n "$CLAUDE_ENV_FILE" ]]; then
        echo "export DISPATCH_AVAILABLE=false" >> "$CLAUDE_ENV_FILE"
    fi
fi

exit 0
```

**Hook configuration** (`~/.claude/settings.json`):
```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/session-start.sh"
          }
        ]
      }
    ]
  }
}
```

### Component 3: Updated Skill Pattern

Skills become much simpler - they just source the library and call init/finalize:

```markdown
---
name: test-feature
description: Test a specific iOS feature in the simulator
---

## Screenshot Integration

```bash
# At the start of the skill
. ~/.claude/lib/dispatch.sh
dispatch_init "Feature Test"

# Take screenshots during testing (save to $DISPATCH_SCREENSHOT_PATH)
mcp__ios-simulator__screenshot(path: "$DISPATCH_SCREENSHOT_PATH/01-login.png")

# At the end of the skill
dispatch_finalize
```
```

### Component 4: HookInstaller Enhancement (Dispatch App)

The Dispatch app's `HookInstaller.swift` should be updated to:
1. Install the shared library to `~/.claude/lib/dispatch.sh`
2. Install the SessionStart hook
3. Update skills to use the library (or provide a migration guide)

```swift
// New method in HookInstaller.swift
func installSharedLibrary() throws {
    let libDirectory = homeDirectory.appendingPathComponent(".claude/lib", isDirectory: true)
    try FileManager.default.createDirectory(at: libDirectory, withIntermediateDirectories: true)

    let libraryPath = libDirectory.appendingPathComponent("dispatch.sh")
    let libraryContent = generateLibraryScript(port: port)
    try libraryContent.write(to: libraryPath, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: libraryPath.path)
}
```

## Integration Points with Existing System

### HookServer Endpoints (No Changes Needed)

| Endpoint | Method | Purpose | Status |
|----------|--------|---------|--------|
| `/health` | GET | Check if Dispatch running | Already implemented |
| `/screenshots/run` | POST | Create screenshot run | Already implemented |
| `/screenshots/complete` | POST | Mark run complete | Already implemented |
| `/screenshots/location` | GET | Get screenshot directory | Already implemented |

### ScreenshotWatcherService (No Changes Needed)

The watcher already:
- Monitors the correct directory
- Parses manifest files
- Creates SwiftData records
- Handles cleanup

### Skills Integration (Update Needed)

Skills need to be updated to source the library:

**Before (30+ lines of duplicated bash):**
```bash
DISPATCH_HEALTH=$(curl -s http://localhost:19847/health 2>/dev/null)
if echo "$DISPATCH_HEALTH" | grep -q '"status":"ok"'; then
  PROJECT_NAME=$(basename "$(pwd)")
  DEVICE_INFO=$(xcrun simctl list devices booted | ...)
  DISPATCH_RESPONSE=$(curl -s -X POST http://localhost:19847/screenshots/run ...)
  DISPATCH_RUN_ID=$(echo "$DISPATCH_RESPONSE" | grep -o ...)
  DISPATCH_SCREENSHOT_PATH=$(echo "$DISPATCH_RESPONSE" | grep -o ...)
  # ... more parsing and error handling
fi
```

**After (3 lines):**
```bash
. ~/.claude/lib/dispatch.sh
dispatch_init "Test Feature"
# ... screenshots go to $DISPATCH_SCREENSHOT_PATH
dispatch_finalize
```

## Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                      Session Start                               │
├─────────────────────────────────────────────────────────────────┤
│  1. Claude Code starts                                          │
│  2. SessionStart hook runs                                      │
│  3. Hook checks if Dispatch running                             │
│  4. Sets DISPATCH_AVAILABLE, DISPATCH_PORT in CLAUDE_ENV_FILE   │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Skill Execution                             │
├─────────────────────────────────────────────────────────────────┤
│  1. Skill sources ~/.claude/lib/dispatch.sh                     │
│  2. dispatch_init() creates run via POST /screenshots/run       │
│  3. Dispatch returns {runId, path}                              │
│  4. Skill saves screenshots to path                             │
│  5. dispatch_finalize() calls POST /screenshots/complete        │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Dispatch Processing                         │
├─────────────────────────────────────────────────────────────────┤
│  1. /screenshots/complete triggers scan                         │
│  2. ScreenshotWatcherService finds new run directory            │
│  3. Reads manifest.json, discovers screenshot files             │
│  4. Creates SimulatorRun + Screenshot SwiftData records         │
│  5. UI updates to show new screenshots                          │
└─────────────────────────────────────────────────────────────────┘
```

## Alternative Approaches Considered

### Option A: Environment Variable Only (Rejected)

Set `DISPATCH_SCREENSHOT_PATH` via SessionStart hook, skills check it.

**Pros:**
- Simplest implementation
- No library needed

**Cons:**
- Skills still need to manually call API for run creation
- No encapsulation of error handling
- Path alone isn't enough (need run_id for completion)

### Option B: Centralized "Screenshot" Skill (Rejected)

Create a skill that other skills delegate screenshot operations to.

**Pros:**
- Single point of control

**Cons:**
- Skills can't easily delegate mid-execution
- Adds complexity for simple screenshot operations
- Claude Code skills aren't designed for inter-skill delegation

### Option C: MCP Server (Considered but Deferred)

Implement Dispatch integration as an MCP server that provides screenshot tools.

**Pros:**
- Native tool integration
- Type-safe parameters
- Automatic discovery

**Cons:**
- More complex to implement
- Requires MCP server infrastructure
- Overkill for current needs (can add later)

### Option D: Shared Bash Library (Recommended)

The chosen approach. Source a library, call functions.

**Pros:**
- Familiar pattern for shell scripts
- Easy to update centrally
- Graceful fallback built-in
- Works with Claude Code's execution model
- Can be installed/updated by Dispatch app

**Cons:**
- Skills must remember to source it
- Bash-only (but that's what skills use)

## Build Order

### Phase 1: Foundation (Do First)
1. Create `~/.claude/lib/` directory structure
2. Write `dispatch.sh` library with all functions
3. Test library independently

### Phase 2: Hook Integration
1. Create SessionStart hook script
2. Update `~/.claude/settings.json` with hook configuration
3. Test hook execution on session start

### Phase 3: Dispatch App Updates
1. Add `installSharedLibrary()` to HookInstaller
2. Update Settings UI to show library status
3. Add "Reinstall Integration" button

### Phase 4: Skill Migration
1. Update `test-feature` skill as template
2. Update remaining skills to use library
3. Remove duplicated integration code

### Phase 5: Verification
1. End-to-end test: skill -> screenshot -> Dispatch UI
2. Test fallback when Dispatch not running
3. Test session restart behavior

## Anti-Patterns to Avoid

### Don't: Hardcode Port Numbers in Skills
Skills should use `$DISPATCH_PORT` or the library's defaults, not hardcoded `19847`.

### Don't: Skip the Library for "Simple" Cases
Every screenshot operation should go through the library for consistency.

### Don't: Block on Dispatch Availability
Skills should gracefully fallback to temp directories, not fail.

### Don't: Forget to Call `dispatch_finalize`
Always pair `dispatch_init` with `dispatch_finalize` for proper cleanup.

## Scalability Considerations

| Scale | Approach |
|-------|----------|
| 1-10 skills | Shared library works well |
| 10-50 skills | Consider MCP server for better tooling |
| 50+ skills | MCP server + project-level configuration |

For the current ~40 skills, the shared library approach is appropriate.

## Sources

- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks) - Official documentation on hooks, SessionStart, CLAUDE_ENV_FILE
- [Claude Code Settings](https://code.claude.com/docs/en/settings) - Environment variable configuration
- [Bash Library Best Practices](https://www.tecmint.com/write-custom-shell-functions-and-libraries-in-linux/) - Shell library patterns
- Existing codebase: `/Users/eric/Dispatch/Dispatch/Services/HookServer.swift` - Current API implementation
- Existing codebase: `/Users/eric/Dispatch/Dispatch/Services/ScreenshotWatcherService.swift` - Screenshot processing
- Existing skills: `/Users/eric/.claude/skills/test-feature/SKILL.md` - Current integration pattern
