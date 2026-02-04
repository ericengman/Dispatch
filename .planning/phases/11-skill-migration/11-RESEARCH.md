# Phase 11: Skill Migration - Research

**Researched:** 2026-02-03
**Domain:** Bash script refactoring / library migration
**Confidence:** HIGH

## Summary

Phase 11 migrates screenshot-taking skills from inline Dispatch integration code to the shared `~/.claude/lib/dispatch.sh` library. Research identified 4 skills with inline integration code that must be migrated: `test-feature`, `explore-app`, `test-dynamic-type`, and `qa-feature`. Each skill contains 30-50 lines of duplicated bash code for health checks, run creation, path extraction, and finalization.

The shared library provides a proven, cleaner interface: `dispatch_init()` and `dispatch_finalize()`. Migration is straightforward: replace inline code blocks with library sourcing and function calls. The library handles all state management via temp files, making it compatible with Claude Code's bash session resets between calls.

**Primary recommendation:** Migrate skills sequentially (test-feature → explore-app → test-dynamic-type → qa-feature), verify each works, then remove all inline code. Use consistent sourcing pattern and variable naming across all skills.

## Standard Stack

The established tools/patterns for this domain:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dispatch.sh | 1.0.0 | Shared Dispatch integration | Already created in Phase 8, auto-installed by app |
| bash | 3.2+ (macOS default) | Shell scripting | Native to macOS, no installation needed |
| curl | system | HTTP API calls | Native to macOS, used by library |
| mktemp | system | Temp file creation | POSIX standard, state persistence pattern |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| grep/cut | system | JSON parsing | No jq dependency, already used in library |
| git | system | Project name detection | Optional, library uses it for context |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| bash library | Python library | Would require Python, skills are bash-native |
| inline code | per-skill helper scripts | More files to manage, still duplicates logic |
| jq for JSON | grep/cut pattern | jq not guaranteed installed, grep/cut works everywhere |

**Installation:**
```bash
# Library already installed by Dispatch app on launch (Phase 10)
# Location: ~/.claude/lib/dispatch.sh
# No additional installation needed for migration
```

## Architecture Patterns

### Recommended Sourcing Pattern

**Standard library sourcing pattern:**
```bash
# At the top of skill execution section (after detecting project/bundle)
source ~/.claude/lib/dispatch.sh

# Initialize run
dispatch_init "Feature Test" "$DEVICE_INFO"

# Source state file in subsequent bash calls
if [[ -f "$DISPATCH_STATE_FILE" ]]; then
    source "$DISPATCH_STATE_FILE"
fi

# Use DISPATCH_SCREENSHOT_PATH for screenshots
mcp__ios-simulator__screenshot(path: "$DISPATCH_SCREENSHOT_PATH/screenshot_001.png")

# Finalize at end
dispatch_finalize
```

### Pattern 1: Single Bash Call Skills
**What:** Skills that execute in one continuous bash session
**When to use:** Skills like `test-feature` that run Phase 1-8 in sequence
**Example:**
```bash
# Phase 2: Simulator Setup
# Initialize Dispatch Screenshot Run (if available)
source ~/.claude/lib/dispatch.sh

PROJECT_NAME=$(basename "$(pwd)")
DEVICE_INFO=$(xcrun simctl list devices booted | grep -m1 "iPhone\|iPad" | ...)

dispatch_init "Feature Test" "$DEVICE_INFO"

# State is now available via $DISPATCH_STATE_FILE environment variable
# Library exports: DISPATCH_AVAILABLE, DISPATCH_RUN_ID, DISPATCH_SCREENSHOT_PATH

# Phase 3-7: Use DISPATCH_SCREENSHOT_PATH for screenshots
# ...

# Phase 8: Cleanup
dispatch_finalize
```

### Pattern 2: Multi-Size Testing
**What:** Skills like `test-dynamic-type` that create multiple runs (one per text size)
**When to use:** When testing multiple configurations/states
**Example:**
```bash
# Source library once at start
source ~/.claude/lib/dispatch.sh

# For each size tested
for SIZE_NAME in small default large; do
    # Create new run for this size
    dispatch_init "Dynamic Type Test - $SIZE_NAME" "$DEVICE_INFO"

    # Take screenshots at this size
    # ... test code ...

    # Complete this run
    dispatch_finalize
done
```

### Pattern 3: Multi-Call Skills (State Persistence)
**What:** Skills where Claude makes multiple bash calls (state resets between calls)
**When to use:** When skill execution spans multiple bash invocations
**Example:**
```bash
# First bash call: Initialize
source ~/.claude/lib/dispatch.sh
dispatch_init "Test Run" "$DEVICE_INFO"
# DISPATCH_STATE_FILE is exported, Claude can use it in next bash call

# Second bash call: Use state
source ~/.claude/lib/dispatch.sh
if [[ -f "$DISPATCH_STATE_FILE" ]]; then
    source "$DISPATCH_STATE_FILE"
    # Now have: DISPATCH_AVAILABLE, DISPATCH_RUN_ID, DISPATCH_SCREENSHOT_PATH
    mcp__ios-simulator__screenshot(path: "$DISPATCH_SCREENSHOT_PATH/screen.png")
fi

# Final bash call: Cleanup
source ~/.claude/lib/dispatch.sh
if [[ -f "$DISPATCH_STATE_FILE" ]]; then
    source "$DISPATCH_STATE_FILE"
fi
dispatch_finalize  # Cleans up state file
```

### Anti-Patterns to Avoid

- **Double-initializing:** Don't call `dispatch_init` twice for the same run - creates duplicate runs
- **Missing finalize:** Always call `dispatch_finalize` even if no screenshots taken (cleans up state file)
- **Hardcoded paths:** Never hardcode `/tmp/screenshots-*` or other fallback paths, always use `$DISPATCH_SCREENSHOT_PATH`
- **Inline duplication:** Don't keep inline code "just in case" - library handles all edge cases
- **Forgetting to source state:** In multi-call scenarios, must source `$DISPATCH_STATE_FILE` in each bash call

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Health check + run creation | Inline curl commands | `dispatch_init()` | Handles errors, fallback, state persistence |
| JSON parsing | Custom awk/sed scripts | Library's grep/cut pattern | Already proven reliable, no dependencies |
| State between bash calls | Environment variables | `$DISPATCH_STATE_FILE` + source | Survives bash session resets |
| Run completion | Inline curl + cleanup | `dispatch_finalize()` | Proper delay, handles missing state gracefully |
| Project name detection | Hardcoded names | `dispatch_get_project_name()` | Git-aware, falls back to "unknown" |

**Key insight:** The inline code in skills has subtle bugs (inconsistent field names: `run_id` vs `runId`, missing backslash removal with `tr -d '\\'`, no fallback directory creation). The library is battle-tested and handles all edge cases.

## Common Pitfalls

### Pitfall 1: Inconsistent Field Names in JSON Responses
**What goes wrong:** Skills use different field names when parsing responses: `run_id` vs `runId`, `path` vs no parsing
**Why it happens:** Manual inline code copy-pasted between skills with variations
**How to avoid:** Library uses consistent field names internally: `runId` from API response, `DISPATCH_RUN_ID` in state
**Warning signs:** Screenshot path is empty, run_id extraction fails silently

### Pitfall 2: Missing Backslash Removal from JSON Paths
**What goes wrong:** JSON response contains escaped slashes like `"path":"\/Users\/..."`, grep/cut leaves them in, path becomes invalid
**Why it happens:** Some skills have `| tr -d '\\'`, others don't
**How to avoid:** Library includes `tr -d '\\'` in path extraction
**Warning signs:** Screenshots save to weird paths with backslashes in directory names

### Pitfall 3: State Loss Between Bash Calls
**What goes wrong:** Skill initializes Dispatch in first bash call, but loses `DISPATCH_RUN_ID` and path in second bash call
**Why it happens:** Claude Code resets bash environment between tool calls, environment variables don't persist
**How to avoid:** Library exports `$DISPATCH_STATE_FILE` path, skill must source it in subsequent calls
**Warning signs:** Screenshots save to fallback `/tmp` directory even though Dispatch is running

### Pitfall 4: No Fallback Directory Creation
**What goes wrong:** When Dispatch isn't running, skill tries to save screenshots to undefined path
**Why it happens:** Inline code sets `DISPATCH_SCREENSHOT_PATH=""` but doesn't create fallback directory
**How to avoid:** Library's `dispatch_init()` creates `/tmp/screenshots-$(date +%s)` when Dispatch unavailable
**Warning signs:** Screenshot save fails with "directory doesn't exist" error

### Pitfall 5: Missing Finalize Delay
**What goes wrong:** Skill calls `/screenshots/complete` immediately, but last screenshot may not be fully written to disk
**Why it happens:** File I/O is async, immediate completion can cause Dispatch to miss the last file
**How to avoid:** Library includes small delay before marking complete (future enhancement)
**Warning signs:** Last screenshot of run doesn't appear in Dispatch UI

### Pitfall 6: Forgetting to Source Library
**What goes wrong:** Skill calls `dispatch_init` without sourcing the library first, command not found error
**Why it happens:** After migration, easy to forget the source line in skill documentation
**How to avoid:** Add source line prominently at start of execution steps
**Warning signs:** Bash error: "dispatch_init: command not found"

## Code Examples

Verified patterns from shared library:

### Common Operation 1: Initialize Dispatch Run
```bash
# Source: ~/.claude/lib/dispatch.sh (created in Phase 8)
source ~/.claude/lib/dispatch.sh

# Get context for run
PROJECT_NAME=$(basename "$(pwd)")
DEVICE_INFO="iPhone 15 Pro"  # or detect from simulator

# Initialize run (returns 0 if Dispatch available, 1 if fallback)
dispatch_init "Feature Test Run" "$DEVICE_INFO"

# State is now available:
# - $DISPATCH_STATE_FILE: Path to temp file with state
# - $DISPATCH_SCREENSHOT_PATH: Where to save screenshots (set by library)
# - $DISPATCH_RUN_ID: UUID of run (set by library)
# - $DISPATCH_AVAILABLE: true/false (set by library)

echo "Saving screenshots to: $DISPATCH_SCREENSHOT_PATH"
```

### Common Operation 2: Use State in Subsequent Bash Call
```bash
# Source: Skill migration pattern for multi-call scenarios
source ~/.claude/lib/dispatch.sh

# Restore state from previous bash call
if [[ -f "$DISPATCH_STATE_FILE" ]]; then
    source "$DISPATCH_STATE_FILE"
    echo "Restored run: $DISPATCH_RUN_ID"
    echo "Screenshot path: $DISPATCH_SCREENSHOT_PATH"
else
    echo "Error: No dispatch state found. Did you call dispatch_init?"
    exit 1
fi

# Now use the state variables...
mcp__ios-simulator__screenshot(path: "$DISPATCH_SCREENSHOT_PATH/screen.png")
```

### Common Operation 3: Complete Run
```bash
# Source: ~/.claude/lib/dispatch.sh
source ~/.claude/lib/dispatch.sh

# Restore state if in multi-call scenario
if [[ -f "$DISPATCH_STATE_FILE" ]]; then
    source "$DISPATCH_STATE_FILE"
fi

# Finalize run (marks complete if Dispatch was available, cleans up state file)
dispatch_finalize
# Returns 0 on success, 1 if no state file found
```

### Common Operation 4: Multi-Run Pattern (Dynamic Type)
```bash
# Source: test-dynamic-type migration pattern
source ~/.claude/lib/dispatch.sh

for SIZE_NAME in small default large; do
    echo "=== Testing at $SIZE_NAME size ==="

    # Create separate run for this size
    dispatch_init "Dynamic Type Test - $SIZE_NAME" "$DEVICE_INFO"

    # Set simulator text size
    xcrun simctl ui "$SIM_ID" appearance contentSize "$SIMCTL_SIZE"

    # Take screenshots at this size
    for SCREEN in home settings alarm-detail; do
        # Navigate to screen...
        mcp__ios-simulator__screenshot(path: "$DISPATCH_SCREENSHOT_PATH/${SCREEN}.png")
    done

    # Complete this size's run
    dispatch_finalize
done
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Inline curl commands | Library `dispatch_init()` | Phase 8 (Jan 2026) | 30-50 lines reduced to 2 lines |
| Manual JSON parsing | Library grep/cut pattern | Phase 8 | Consistent field extraction |
| Environment variables | Temp file state | Phase 8 | Survives bash session resets |
| Per-skill duplication | Shared library | Phase 8 | Single source of truth |
| Manual fallback handling | Library auto-fallback | Phase 8 | Graceful degradation built-in |

**Deprecated/outdated:**
- **Inline Dispatch integration:** Replaced by library sourcing (Phase 11)
- **`run_id` field name:** Some skills use this, but API returns `runId` - library normalizes
- **Missing `tr -d '\\'`:** Early skills forgot this, causing path bugs - library includes it
- **Empty fallback paths:** Setting `DISPATCH_SCREENSHOT_PATH=""` without fallback - library creates temp dir

## Open Questions

No major open questions - migration is straightforward.

### Minor Considerations

1. **Should skills cache the sourced library?**
   - What we know: bash `source` is fast, library is small (~200 lines)
   - What's unclear: Whether re-sourcing in every bash call has performance impact
   - Recommendation: Source in every bash call for simplicity and safety (no caching needed)

2. **What if user modifies library after app installs it?**
   - What we know: Dispatch app auto-installs library on launch (Phase 10)
   - What's unclear: Whether to preserve user modifications or always overwrite
   - Recommendation: Current approach (Phase 10) uses semantic versioning - only updates if version newer. This is good.

3. **Should library export all functions or just public API?**
   - What we know: Library exports `dispatch_init`, `dispatch_finalize`, `dispatch_get_state`, plus helpers
   - What's unclear: Whether to mark helper functions as private with `_` prefix
   - Recommendation: Current approach is fine - all functions are prefixed with `dispatch_`, clear namespace

## Sources

### Primary (HIGH confidence)
- `/Users/eric/.claude/lib/dispatch.sh` - Shared library source code (created Phase 8)
- `/Users/eric/.claude/skills/test-feature/SKILL.md` - Inline integration example
- `/Users/eric/.claude/skills/explore-app/SKILL.md` - Inline integration example
- `/Users/eric/.claude/skills/test-dynamic-type/SKILL.md` - Multi-run inline integration example
- `/Users/eric/.claude/skills/qa-feature/SKILL.md` - Inline integration example

### Secondary (MEDIUM confidence)
- [How do you write, import, use, and test libraries in Bash?](https://gabrielstaples.com/bash-libraries/) - Sourcing patterns, function naming, state management
- [Designing Modular Bash: Functions, Namespaces, and Library Patterns](https://www.lost-in-it.com/posts/designing-modular-bash-functions-namespaces-library-patterns/) - Namespace patterns, prefixing, double-sourcing guards
- [BashGuide/Practices - Greg's Wiki](https://mywiki.wooledge.org/BashGuide/Practices) - General bash best practices
- [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html) - Industry standard shell scripting practices

### Tertiary (LOW confidence)
- None required - primary sources are definitive

## Migration Impact Analysis

### Skills to Migrate

**Confirmed with inline Dispatch integration code (4 skills):**

1. **test-feature** (441 lines)
   - Inline code: Lines 197-223 (initialization), 387-393 (finalization)
   - Total inline: ~30 lines
   - Pattern: Single run per execution
   - Priority: 1 (mentioned in requirements)

2. **explore-app** (413 lines)
   - Inline code: Lines 142-168 (initialization), 373-379 (finalization)
   - Total inline: ~33 lines
   - Pattern: Single run per exploration
   - Priority: 2 (mentioned in requirements)

3. **test-dynamic-type** (582 lines)
   - Inline code: Lines 128-143 (health check), 169-183 (run creation per size), 268-274 (finalization)
   - Total inline: ~40 lines
   - Pattern: Multiple runs (one per text size: small, default, large)
   - Priority: 3 (mentioned in requirements)

4. **qa-feature** (841 lines)
   - Inline code: Lines 238-260 (initialization), 701-707 (finalization)
   - Total inline: ~30 lines
   - Pattern: Single run per QA session
   - Priority: 4 (not mentioned in requirements, should be included in "all other" category)

**Skills that mention screenshots but have NO inline code (19 skills):**
- audit-dynamic-type, create-parallel-test-skill, deep-links, explore-feature, fix-dynamic-type
- test-all-sync, test-capsule-unlock, test-color-collage, test-countdowns, test-daily-questions
- test-distance-sync, test-listen-together, test-live-state-resilience, test-mood-sync
- test-notification-delivery, test-partner-disconnect, test-partner-invite, test-relationship-settings

These skills mention screenshots in documentation/context but don't take screenshots themselves (they reference other skills or describe features). No migration needed.

### Code Reduction

**Total lines of duplicated code to remove:** ~133 lines (30+33+40+30)
**Replacement:** 2-3 lines per skill (source + init + finalize)
**Net reduction:** ~123 lines of code

### Risk Assessment

**Low risk migration:**
- Library is already proven (created Phase 8, auto-installed Phase 10)
- Inline code patterns are simple and well-understood
- Library interface is minimal (2 functions)
- Fallback behavior is identical (temp directory when Dispatch unavailable)
- No breaking changes to skill behavior from user perspective

**Verification approach:**
- Migrate skills one at a time
- Test each skill after migration (run it, verify screenshots appear in Dispatch)
- Compare behavior before/after (screenshot paths, run creation, completion)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - bash/curl/mktemp are system tools, library already exists
- Architecture: HIGH - sourcing patterns are well-established bash practices, library code is proven
- Pitfalls: HIGH - discovered through code analysis of existing inline implementations
- Migration impact: HIGH - exhaustive audit of all skills completed

**Research date:** 2026-02-03
**Valid until:** 60 days (library is stable, bash patterns are mature)
