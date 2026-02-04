# Technology Stack: Screenshot Routing Centralization

**Project:** Dispatch Screenshot Routing Fix
**Researched:** 2026-02-03
**Confidence:** HIGH (based on direct examination of existing codebase)

## Problem Statement

Skills are saving screenshots to temp folders (e.g., `/tmp/dynamic-type-test-{timestamp}/`) instead of the Dispatch-monitored location (`~/Library/Application Support/Dispatch/Screenshots/{project}/{run-uuid}/`). This breaks the screenshot review workflow because ScreenshotWatcherService never sees the files.

## Current Architecture Analysis

### Existing API (HookServer.swift)

The Dispatch app already exposes the correct endpoints:

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/health` | GET | Check if Dispatch is running |
| `/screenshots/location` | GET | Get base save path for a project |
| `/screenshots/run` | POST | Create a new run, returns runId + path |
| `/screenshots/complete` | POST | Mark run complete, trigger scan |

### Current Skill Implementation Pattern

Each skill (test-feature, explore-app, test-dynamic-type) contains duplicated code:

```bash
# Check if Dispatch is running
DISPATCH_HEALTH=$(curl -s http://localhost:19847/health 2>/dev/null)

if echo "$DISPATCH_HEALTH" | grep -q '"status":"ok"'; then
  PROJECT_NAME=$(basename "$(pwd)")
  DEVICE_INFO=$(xcrun simctl list devices booted | ...)

  DISPATCH_RESPONSE=$(curl -s -X POST http://localhost:19847/screenshots/run ...)
  DISPATCH_RUN_ID=$(echo "$DISPATCH_RESPONSE" | grep -o ...)
  DISPATCH_SCREENSHOT_PATH=$(echo "$DISPATCH_RESPONSE" | grep -o ...)
else
  DISPATCH_SCREENSHOT_PATH="/tmp/fallback-location"
fi
```

### Problem: Why Screenshots Go to Wrong Place

1. **Duplicated logic** - Each skill re-implements Dispatch detection
2. **Inconsistent execution** - Claude doesn't always follow the skill instructions precisely
3. **No enforcement** - Skills fall back to temp dirs without warning
4. **Variable scope issues** - DISPATCH_SCREENSHOT_PATH set in one bash call, not available in later MCP calls

---

## Recommended Approach: Shared Helper Script

**Confidence:** HIGH

Create a centralized helper script that ALL skills source. This eliminates duplication and ensures consistent behavior.

### Technology: Shell Script at `~/.claude/lib/dispatch-screenshots.sh`

| Aspect | Decision | Rationale |
|--------|----------|-----------|
| Language | Bash | Skills already use bash; no new runtime dependencies |
| Location | `~/.claude/lib/` | Logical place for shared utilities across skills |
| Pattern | Source-able library | Can be `source`d at start of any skill's bash execution |

### Implementation

**File: `~/.claude/lib/dispatch-screenshots.sh`**

```bash
#!/bin/bash
# Shared Dispatch screenshot integration for Claude Code skills
# Source this at the start of any skill that takes screenshots

DISPATCH_HOST="${DISPATCH_HOST:-localhost}"
DISPATCH_PORT="${DISPATCH_PORT:-19847}"
DISPATCH_BASE_URL="http://${DISPATCH_HOST}:${DISPATCH_PORT}"

# State variables (exported for subshells)
export DISPATCH_AVAILABLE=false
export DISPATCH_RUN_ID=""
export DISPATCH_SCREENSHOT_PATH=""
export DISPATCH_SCREENSHOT_INDEX=0

# Check if Dispatch is running
dispatch_check() {
  local health
  health=$(curl -s --connect-timeout 2 "${DISPATCH_BASE_URL}/health" 2>/dev/null)
  if echo "$health" | grep -q '"status":"ok"'; then
    DISPATCH_AVAILABLE=true
    return 0
  else
    DISPATCH_AVAILABLE=false
    return 1
  fi
}

# Create a screenshot run
# Usage: dispatch_create_run "ProjectName" "Run Description" "Device Info"
dispatch_create_run() {
  local project="${1:-$(basename "$(pwd)")}"
  local name="${2:-Screenshot Run}"
  local device="${3:-}"

  if [ "$DISPATCH_AVAILABLE" != "true" ]; then
    dispatch_check || return 1
  fi

  local response
  response=$(curl -s -X POST "${DISPATCH_BASE_URL}/screenshots/run" \
    -H "Content-Type: application/json" \
    -d "{\"project\":\"${project}\",\"name\":\"${name}\",\"device\":\"${device}\"}")

  DISPATCH_RUN_ID=$(echo "$response" | grep -o '"runId":"[^"]*"' | cut -d'"' -f4)
  DISPATCH_SCREENSHOT_PATH=$(echo "$response" | grep -o '"path":"[^"]*"' | cut -d'"' -f4 | tr -d '\\')
  DISPATCH_SCREENSHOT_INDEX=0

  if [ -n "$DISPATCH_RUN_ID" ] && [ -n "$DISPATCH_SCREENSHOT_PATH" ]; then
    export DISPATCH_RUN_ID DISPATCH_SCREENSHOT_PATH DISPATCH_SCREENSHOT_INDEX
    return 0
  else
    return 1
  fi
}

# Get the next screenshot path with auto-incrementing index
# Usage: path=$(dispatch_screenshot_path "screen_name")
dispatch_screenshot_path() {
  local name="${1:-screenshot}"

  if [ -z "$DISPATCH_SCREENSHOT_PATH" ]; then
    # Fallback to temp directory
    local fallback="/tmp/screenshots-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$fallback"
    echo "${fallback}/${name}.png"
    return
  fi

  DISPATCH_SCREENSHOT_INDEX=$((DISPATCH_SCREENSHOT_INDEX + 1))
  printf "%s/%02d_%s.png" "$DISPATCH_SCREENSHOT_PATH" "$DISPATCH_SCREENSHOT_INDEX" "$name"
}

# Complete the current run
dispatch_complete_run() {
  if [ -z "$DISPATCH_RUN_ID" ]; then
    return 1
  fi

  curl -s -X POST "${DISPATCH_BASE_URL}/screenshots/complete" \
    -H "Content-Type: application/json" \
    -d "{\"runId\":\"${DISPATCH_RUN_ID}\"}" >/dev/null

  # Reset state
  DISPATCH_RUN_ID=""
  DISPATCH_SCREENSHOT_PATH=""
  DISPATCH_SCREENSHOT_INDEX=0
}

# Initialize - call at skill start
dispatch_init() {
  dispatch_check
  if [ "$DISPATCH_AVAILABLE" = "true" ]; then
    echo "Dispatch available at ${DISPATCH_BASE_URL}"
  else
    echo "Dispatch not running - screenshots will use fallback location"
  fi
}
```

### Usage in Skills

Skills would update their SKILL.md to include:

```bash
# At the start of screenshot-related work
source ~/.claude/lib/dispatch-screenshots.sh
dispatch_init
dispatch_create_run "MyApp" "Feature Test" "iPhone 15 Pro"

# When taking screenshots (in MCP calls or bash)
SCREENSHOT_PATH=$(dispatch_screenshot_path "home_screen")
mcp__ios-simulator__screenshot(path: "$SCREENSHOT_PATH")

# When done
dispatch_complete_run
```

---

## Alternative Approaches Considered

### Alternative 1: Environment Variable Only

**Approach:** Set `DISPATCH_SCREENSHOT_PATH` in global CLAUDE.md or hooks

**Why Not:**
- Environment variables don't persist across MCP tool calls
- Would need to re-query Dispatch for each screenshot (inefficient)
- Doesn't handle run lifecycle (create/complete)

### Alternative 2: MCP Server for Screenshots

**Approach:** Create a dedicated MCP server that handles screenshot routing

**Why Not:**
- Adds complexity (new server to maintain)
- Skills already have bash access; MCP adds indirection
- HookServer already provides the API; just need skills to use it consistently

### Alternative 3: Claude Code Hook on Screenshot

**Approach:** Add a PostToolUse hook that intercepts `mcp__ios-simulator__screenshot` and redirects

**Why Not:**
- Hooks can't modify tool parameters
- Would require copying files after the fact (inefficient)
- Race condition between screenshot creation and hook execution

### Alternative 4: Modify Each Skill Individually

**Approach:** Update each SKILL.md to use the Dispatch API correctly

**Why Not:**
- 37 skills to update (error-prone)
- Duplicated logic in every skill
- Future skills would need to copy the pattern

---

## Installation Requirements

### File Structure

```
~/.claude/
├── lib/
│   └── dispatch-screenshots.sh    # NEW: Shared helper
├── skills/
│   ├── test-feature/
│   │   └── SKILL.md               # UPDATE: Source helper
│   ├── explore-app/
│   │   └── SKILL.md               # UPDATE: Source helper
│   ├── test-dynamic-type/
│   │   └── SKILL.md               # UPDATE: Source helper
│   └── ... (other skills)
└── CLAUDE.md                       # NO CHANGE needed
```

### Dependencies

| Dependency | Version | Purpose | Why |
|------------|---------|---------|-----|
| bash | 3.2+ | Script execution | Already available on macOS |
| curl | any | HTTP requests | Already used by skills |
| grep | any | JSON parsing (simple) | Already used by skills |

No new dependencies required.

---

## Migration Strategy

### Phase 1: Create Helper Library

1. Create `~/.claude/lib/dispatch-screenshots.sh`
2. Test helper functions manually with curl
3. Verify run creation and path retrieval work

### Phase 2: Update Screenshot-Taking Skills

Priority order (most used first):
1. `test-feature` - Most commonly used for verification
2. `test-dynamic-type` - Heavy screenshot usage
3. `explore-app` - Full app exploration
4. `explore-feature` - Before/after captures

### Phase 3: Validate Integration

1. Run each updated skill
2. Verify screenshots appear in Dispatch
3. Verify run completion triggers scan

---

## Risk Assessment

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Helper script not sourced correctly | Medium | Add explicit instruction in SKILL.md |
| Bash variable scope issues across MCP calls | High | Document that path must be captured in same bash call as screenshot |
| Dispatch not running when skill executes | Low | Graceful fallback to temp dir (existing behavior) |

---

## Sources

| Source | Confidence | Purpose |
|--------|------------|---------|
| `/Users/eric/Dispatch/Dispatch/Services/HookServer.swift` | HIGH | Verified existing API endpoints |
| `/Users/eric/Dispatch/Dispatch/Services/ScreenshotWatcherService.swift` | HIGH | Verified expected save location |
| `/Users/eric/.claude/skills/test-feature/SKILL.md` | HIGH | Current skill implementation pattern |
| `/Users/eric/.claude/skills/explore-app/SKILL.md` | HIGH | Current skill implementation pattern |
| `/Users/eric/.claude/skills/test-dynamic-type/SKILL.md` | HIGH | Current skill implementation pattern |
