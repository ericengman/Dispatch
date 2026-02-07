# Phase 8: Foundation - Research

**Researched:** 2026-02-03
**Domain:** Bash library patterns and Dispatch API integration
**Confidence:** HIGH

## Summary

Phase 8 creates a shared bash library (`~/.claude/lib/dispatch.sh`) to consolidate Dispatch integration code currently duplicated across multiple skills. The library will provide two primary functions (`dispatch_init` and `dispatch_finalize`) that handle screenshot run creation and completion via the Dispatch HTTP API.

The research examined existing Dispatch API endpoints in HookServer.swift, analyzed current skill integration patterns (test-feature, test-dynamic-type, explore-app), verified bash state persistence patterns, and reviewed bash library best practices.

**Key findings:**
- Dispatch HookServer already has complete screenshot API: POST `/screenshots/run` (create), POST `/screenshots/complete` (finalize), GET `/screenshots/location` (legacy)
- Skills currently duplicate 40-60 lines of inline Dispatch integration code per skill
- Bash requires temp file state persistence between calls (agent threads reset cwd)
- Git root detection via `git rev-parse --show-toplevel` is standard and reliable
- mktemp + trap pattern is the modern standard for safe temp file handling

**Primary recommendation:** Create library with dispatch_init/dispatch_finalize functions, use mktemp for state files, leverage existing HookServer API endpoints unchanged.

## Standard Stack

The established tools/patterns for this domain:

### Core
| Library/Tool | Version | Purpose | Why Standard |
|--------------|---------|---------|--------------|
| bash | 3.2+ (macOS default) | Shell scripting | Universal on macOS, no installation required |
| curl | 7.x+ (macOS default) | HTTP API calls | Built-in, reliable, well-documented |
| mktemp | System utility | Temp file creation | Secure, atomic, prevents race conditions |
| jq | Optional | JSON parsing | Standard for bash JSON handling (fallback: grep/cut) |
| git | 2.x+ | Project root detection | Already present in development environment |

### Supporting
| Library/Tool | Version | Purpose | When to Use |
|--------------|---------|---------|-------------|
| trap | Built-in | Cleanup on exit | Always use with temp files |
| basename | Built-in | Extract directory name | Project name from git root path |
| source (.) | Built-in | Load library | Import functions into script context |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| curl | wget | curl more common on macOS, simpler syntax |
| mktemp | /tmp/name.$$ | mktemp prevents race conditions, more secure |
| trap EXIT | Manual cleanup | trap ensures cleanup on errors/signals |
| jq | python3 -c | jq cleaner, but optional; python always available |

**Installation:**
None required - all core tools are macOS system utilities.

## Architecture Patterns

### Recommended Project Structure
```
~/.claude/
├── lib/
│   └── dispatch.sh        # Shared library
├── hooks/
│   ├── session-start.sh   # Phase 9 (sets env vars)
│   └── stop.sh            # Existing (completion hook)
└── skills/
    └── */SKILL.md         # Skills source the library
```

### Pattern 1: Library Sourcing
**What:** Skills load library functions into their bash environment
**When to use:** Every skill that takes screenshots
**Example:**
```bash
# Source: Bash best practices
# At top of skill bash script
if [ -f ~/.claude/lib/dispatch.sh ]; then
    source ~/.claude/lib/dispatch.sh
else
    echo "Warning: Dispatch library not found, using fallback"
    # Define fallback stubs
fi
```

### Pattern 2: Init-Execute-Finalize
**What:** Initialize run, execute work, finalize on completion
**When to use:** Screenshot capture workflows
**Example:**
```bash
# Source: test-dynamic-type skill (lines 195-222)
# Initialize
dispatch_init "MyProject" "Test Run" "iPhone 15 Pro"
# Returns: RUN_ID and SCREENSHOT_PATH (via temp file state)

# Execute work
for screen in screens; do
    take_screenshot "$SCREENSHOT_PATH/screen-${i}.png"
done

# Finalize
dispatch_finalize "$RUN_ID"
```

### Pattern 3: Temp File State Persistence
**What:** Use mktemp files to persist state across bash calls
**When to use:** When bash environment resets between calls (Claude agent threads)
**Example:**
```bash
# Source: Modern bash practices (2026)
# Create temp file with cleanup trap
STATE_FILE=$(mktemp /tmp/dispatch-state.XXXXXX)
trap 'rm -f "$STATE_FILE"' EXIT

# Write state
echo "RUN_ID=$RUN_ID" > "$STATE_FILE"
echo "SCREENSHOT_PATH=$SCREENSHOT_PATH" >> "$STATE_FILE"

# Later calls read state
source "$STATE_FILE"
```

### Pattern 4: Graceful Fallback
**What:** Continue working when Dispatch is not running
**When to use:** Always - don't break skills when Dispatch unavailable
**Example:**
```bash
# Source: test-feature skill (lines 196-221)
DISPATCH_HEALTH=$(curl -s http://localhost:19847/health 2>/dev/null)

if echo "$DISPATCH_HEALTH" | grep -q '"status":"ok"'; then
    # Dispatch available - use API
    dispatch_create_run
else
    # Fallback - use temp directory
    SCREENSHOT_PATH="/tmp/screenshots-$(date +%s)"
    mkdir -p "$SCREENSHOT_PATH"
    echo "Dispatch not running - screenshots saved to: $SCREENSHOT_PATH"
fi
```

### Anti-Patterns to Avoid
- **Hardcoding /tmp paths without mktemp:** Race conditions, security issues
- **Using $$ for unique IDs:** Predictable, not secure, can clash
- **No cleanup trap:** Leaves temp files littering /tmp
- **Current directory for project name:** Fails when run from subdirectory
- **Silent failures:** User must know when fallback is active

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Unique temp files | `/tmp/myfile.$$` | `mktemp /tmp/dispatch-*.XXXXXX` | Prevents race conditions, more secure, atomic creation |
| JSON parsing | awk/sed/grep chains | `jq` or `python3 -c` | Proper JSON escaping, handles edge cases |
| Project root detection | `pwd` or dirname chains | `git rev-parse --show-toplevel` | Works from any subdirectory, git-aware |
| HTTP requests | netcat/telnet | `curl` | Handles redirects, errors, timeouts properly |
| Cleanup on exit | Manual rm commands | `trap 'cleanup' EXIT` | Runs on errors, signals, normal exit |

**Key insight:** Bash has evolved best practices for common patterns. Following established patterns prevents subtle bugs around race conditions, signal handling, and error cases.

## Common Pitfalls

### Pitfall 1: State Loss Between Bash Calls
**What goes wrong:** Variables set in one bash call don't persist to the next
**Why it happens:** Claude agent threads reset working directory and environment between tool calls
**How to avoid:** Use temp files for state persistence (read in each function)
**Warning signs:** Functions complain about missing variables that were "just set"

### Pitfall 2: Current Directory Assumption
**What goes wrong:** Project name derived from `basename $(pwd)` is wrong when run from subdirectory
**Why it happens:** Skills can be invoked from any directory in the repo
**How to avoid:** Always use `git rev-parse --show-toplevel | xargs basename`
**Warning signs:** Screenshots saved to wrong project folder

### Pitfall 3: No Fallback for Missing Dispatch
**What goes wrong:** Skill fails completely when Dispatch not running
**Why it happens:** Hardcoded assumption that API is available
**How to avoid:** Always check health endpoint, provide temp directory fallback
**Warning signs:** curl errors, skill exits early

### Pitfall 4: Temp File Leakage
**What goes wrong:** /tmp fills with abandoned state files
**Why it happens:** No cleanup trap when script exits early
**How to avoid:** Always use `trap 'rm -f "$STATE_FILE"' EXIT` immediately after mktemp
**Warning signs:** Multiple /tmp/dispatch-* files remain after runs

### Pitfall 5: JSON Escaping in Curl
**What goes wrong:** POST requests fail when project names contain quotes or special chars
**Why it happens:** Shell expansion and JSON escaping interact badly
**How to avoid:** Use single quotes around JSON, escape variables properly: `'{\"name\":\"'"$VAR"'\"}'`
**Warning signs:** 400 Bad Request errors with certain project names

### Pitfall 6: Library Not Installed
**What goes wrong:** Skills fail to source library that doesn't exist yet
**Why it happens:** Library must be installed before skills can use it (Phase 10 dependency)
**How to avoid:** Check if library exists before sourcing, provide inline fallback functions
**Warning signs:** "source: file not found" errors

## Code Examples

Verified patterns from official sources and existing codebase:

### Dispatch API: Create Screenshot Run
```bash
# Source: HookServer.swift lines 421-458
# POST /screenshots/run
# Request: {"project":"string","name":"string","device":"string"}
# Response: {"runId":"uuid","path":"string"}

PROJECT_NAME=$(basename "$(git rev-parse --show-toplevel)")
DEVICE_INFO="iPhone 15 Pro"

RESPONSE=$(curl -s -X POST http://localhost:19847/screenshots/run \
  -H "Content-Type: application/json" \
  -d '{"project":"'"$PROJECT_NAME"'","name":"Feature Test","device":"'"$DEVICE_INFO"'"}')

RUN_ID=$(echo "$RESPONSE" | grep -o '"runId":"[^"]*"' | cut -d'"' -f4)
SCREENSHOT_PATH=$(echo "$RESPONSE" | grep -o '"path":"[^"]*"' | cut -d'"' -f4)

echo "Run created: $RUN_ID"
echo "Save screenshots to: $SCREENSHOT_PATH"
```

### Dispatch API: Complete Screenshot Run
```bash
# Source: HookServer.swift lines 460-485
# POST /screenshots/complete
# Request: {"runId":"uuid"}
# Response: {"completed":true}

curl -s -X POST http://localhost:19847/screenshots/complete \
  -H "Content-Type: application/json" \
  -d '{"runId":"'"$RUN_ID"'"}'

echo "Run finalized - Dispatch will scan for screenshots"
```

### Dispatch API: Health Check
```bash
# Source: HookServer.swift lines 323-324
# GET /health
# Response: {"status":"ok"}

HEALTH=$(curl -s http://localhost:19847/health 2>/dev/null)
if echo "$HEALTH" | grep -q '"status":"ok"'; then
    echo "Dispatch is running"
else
    echo "Dispatch is not running"
fi
```

### Safe Temp File State Persistence
```bash
# Source: Modern bash practices (2026)
# Create unique state file
STATE_FILE=$(mktemp /tmp/dispatch-state.XXXXXX)
trap 'rm -f "$STATE_FILE"' EXIT

# Write state
cat > "$STATE_FILE" <<EOF
RUN_ID=$RUN_ID
SCREENSHOT_PATH=$SCREENSHOT_PATH
DISPATCH_AVAILABLE=$DISPATCH_AVAILABLE
EOF

# Later function reads state
if [ -f "$STATE_FILE" ]; then
    source "$STATE_FILE"
fi
```

### Library Function Template
```bash
# Source: Google Shell Style Guide, bash-libraries
# Public function with prefix
dispatch_init() {
    local project_name="${1:-$(basename "$(git rev-parse --show-toplevel)")}"
    local run_name="${2:-Screenshot Run}"
    local device_info="${3:-Unknown Device}"

    # Create state file
    export DISPATCH_STATE_FILE=$(mktemp /tmp/dispatch-state.XXXXXX)
    trap 'rm -f "$DISPATCH_STATE_FILE"' EXIT

    # Health check
    local health=$(curl -s http://localhost:19847/health 2>/dev/null)
    if echo "$health" | grep -q '"status":"ok"'; then
        # Create run via API
        local response=$(curl -s -X POST http://localhost:19847/screenshots/run \
            -H "Content-Type: application/json" \
            -d '{"project":"'"$project_name"'","name":"'"$run_name"'","device":"'"$device_info"'"}')

        local run_id=$(echo "$response" | grep -o '"runId":"[^"]*"' | cut -d'"' -f4)
        local path=$(echo "$response" | grep -o '"path":"[^"]*"' | cut -d'"' -f4)

        # Save state
        cat > "$DISPATCH_STATE_FILE" <<EOF
DISPATCH_AVAILABLE=true
DISPATCH_RUN_ID=$run_id
DISPATCH_SCREENSHOT_PATH=$path
EOF

        echo "Dispatch run created: $run_id"
        echo "Screenshots will be saved to: $path"
        return 0
    else
        # Fallback
        local fallback_path="/tmp/screenshots-$(date +%s)"
        mkdir -p "$fallback_path"

        cat > "$DISPATCH_STATE_FILE" <<EOF
DISPATCH_AVAILABLE=false
DISPATCH_RUN_ID=
DISPATCH_SCREENSHOT_PATH=$fallback_path
EOF

        echo "Dispatch not running - screenshots saved to: $fallback_path"
        return 0
    fi
}
```

### Git Root Project Name
```bash
# Source: git-scm.com/docs/git-rev-parse
# Get project name from git repository root
PROJECT_NAME=$(basename "$(git rev-parse --show-toplevel)")

# Example: /Users/eric/Dispatch -> "Dispatch"
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Inline integration code per skill | Shared library pattern | 2026 (this phase) | Eliminates duplication, single source of truth |
| `/tmp/name.$$` for temp files | `mktemp /tmp/name.XXXXXX` | ~2015 | Security fix, prevents race conditions |
| `basename $(pwd)` for project | `git rev-parse --show-toplevel` | Git 1.7+ | Works from any subdirectory |
| Manual cleanup | `trap 'cleanup' EXIT` | Long established | Ensures cleanup on errors |
| Hardcoded Dispatch path | Health check + fallback | This milestone | Graceful degradation |

**Deprecated/outdated:**
- **`/tmp/dispatch.txt` (predictable names):** Use mktemp with random suffix
- **No error handling on curl:** Always check health before assuming API available
- **Global variables in libraries:** Use function parameters and return values

## Open Questions

Things that couldn't be fully resolved:

1. **SessionStart hook CLAUDE_ENV_FILE mechanism**
   - What we know: Phase 9 will set env vars via CLAUDE_ENV_FILE
   - What's unclear: Exact syntax/format for CLAUDE_ENV_FILE, whether it persists across bash calls
   - Recommendation: Research in Phase 9, library shouldn't depend on it yet

2. **Temp file cleanup timing**
   - What we know: trap EXIT runs when bash script exits
   - What's unclear: Whether state file should persist across multiple skill function calls within same session
   - Recommendation: Use session-scoped state file (doesn't cleanup until session ends) OR read-write pattern per function

3. **JSON parsing without jq**
   - What we know: grep/cut works for simple cases
   - What's unclear: Edge cases with escaped characters in project names
   - Recommendation: Start with grep/cut, add jq detection for complex cases

4. **Library versioning**
   - What we know: Dispatch will auto-update library (APP-02)
   - What's unclear: How skills detect library version compatibility
   - Recommendation: Version check function in library, skills can verify minimum version

## Sources

### Primary (HIGH confidence)
- `/Users/eric/Dispatch/Dispatch/Services/HookServer.swift` - Complete API implementation
- `/Users/eric/.claude/skills/test-dynamic-type/SKILL.md` - Current integration pattern
- `/Users/eric/.claude/skills/test-feature/SKILL.md` - Current integration pattern
- [Git Rev-Parse Documentation](https://git-scm.com/docs/git-rev-parse) - Official git documentation
- [Git: Output Root Directory](https://adamj.eu/tech/2023/08/21/git-output-root-directory/) - Verified pattern

### Secondary (MEDIUM confidence)
- [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html) - Industry standard bash practices
- [Bash Libraries Guide](https://www.lost-in-it.com/posts/designing-modular-bash-functions-namespaces-library-patterns/) - Library patterns
- [mktemp Best Practices](https://oneuptime.com/blog/post/2026-01-24-bash-file-operations/view) - 2026 reference
- [Bash Temporary Files](https://www.putorius.net/mktemp-working-with-temporary-files.html) - Modern patterns

### Tertiary (LOW confidence)
- [Bash Source Command](https://linuxvox.com/blog/bash-source-command/) - General sourcing info
- [Creating Persistent Variables](https://linuxvox.com/blog/variable-in-bash-script-that-keeps-it-value-from-the-last-time-running/) - State persistence patterns

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All tools are macOS system utilities, verified in codebase
- Architecture: HIGH - Patterns verified in existing skills and HookServer implementation
- Pitfalls: HIGH - Based on actual codebase analysis and documented bash gotchas
- API endpoints: HIGH - Directly from HookServer.swift source code
- State persistence: MEDIUM - Temp file pattern verified, but session scope needs testing

**Research date:** 2026-02-03
**Valid until:** 60 days (stable bash/git patterns, but Dispatch API might evolve)

**Key risks mitigated:**
- ✅ Verified API endpoints exist and are complete
- ✅ Confirmed current duplication in skills (40-60 lines per skill)
- ✅ Validated git root detection pattern
- ✅ Researched modern temp file best practices
- ⚠️  SessionStart hook env var mechanism needs Phase 9 research

**Ready for planning:** Yes - all core patterns and APIs verified.
