# SessionStart Hook for Dispatch Detection

**Location:** `~/.claude/hooks/session-start.sh`
**Created:** 2026-02-03
**Phase:** 09-01 Hook Integration
**Type:** Claude Code SessionStart Hook

## Purpose

Detects Dispatch availability at Claude Code session start and sets environment variables via `CLAUDE_ENV_FILE` for session-wide access. This enables skills to know upfront whether screenshot integration is available, eliminating per-command health check overhead.

## Trigger Events

The SessionStart hook fires on these Claude Code events:
- **startup** - New session started
- **resume** - Existing session resumed
- **clear** - Session cleared
- **compact** - Session compacted

## Environment Variables Set

The hook writes these variables to `CLAUDE_ENV_FILE` (available to all bash commands in the session):

| Variable | Value When Available | Value When Unavailable |
|----------|---------------------|------------------------|
| `DISPATCH_AVAILABLE` | `true` | `false` |
| `DISPATCH_PORT` | `19847` | (not set) |

## Dependencies

**Required:**
- `~/.claude/lib/dispatch.sh` - Shared library created in Phase 08-01
  - Provides `dispatch_check_health()` function
  - Provides `DISPATCH_DEFAULT_PORT` constant

**Optional:**
- Dispatch app running on localhost:19847
  - If not running, hook sets `DISPATCH_AVAILABLE=false`
  - Hook always exits 0 (never blocks session)

## Hook Behavior

### When Dispatch is Available

1. Calls `dispatch_check_health()` from library
2. Health check succeeds (HTTP 200 from `/health`)
3. Writes to `CLAUDE_ENV_FILE`:
   ```bash
   export DISPATCH_AVAILABLE=true
   export DISPATCH_PORT=19847
   ```
4. Outputs to stderr (user sees): `"Dispatch server detected (port 19847)"`
5. Outputs to stdout (Claude sees): `"Dispatch integration active - screenshot commands available"`

### When Dispatch is Not Available

1. Calls `dispatch_check_health()` from library
2. Health check fails (connection refused or non-200)
3. Writes to `CLAUDE_ENV_FILE`:
   ```bash
   export DISPATCH_AVAILABLE=false
   ```
4. Outputs to stderr (user sees): `"Dispatch server not detected at localhost:19847"`
5. Outputs to stdout (Claude sees): `"Dispatch not running - screenshot features unavailable"`

### When Library Not Installed

1. Checks `[ ! -f ~/.claude/lib/dispatch.sh ]`
2. Outputs to stderr: `"Dispatch library not installed"`
3. Exits 0 (graceful degradation)

## Output Modes

The hook uses different output streams for different audiences:

- **stdout** - Becomes context for Claude to read
  - "Dispatch integration active" or "Dispatch not running"
- **stderr** - Messages for user in terminal
  - "Dispatch server detected (port 19847)"
- **CLAUDE_ENV_FILE** - Environment variables for all bash commands
  - `export DISPATCH_AVAILABLE=true/false`

## Usage in Skills

After the SessionStart hook runs, skills can check the environment variable:

```bash
#!/bin/bash
# Example skill that uses Dispatch if available

if [ "$DISPATCH_AVAILABLE" = "true" ]; then
    echo "Using Dispatch for screenshots"
    source ~/.claude/lib/dispatch.sh
    dispatch_init "My Test" "iPhone 15 Pro"

    # Take screenshots to $DISPATCH_SCREENSHOT_PATH
    xcrun simctl io booted screenshot "$DISPATCH_SCREENSHOT_PATH/screen.png"

    dispatch_finalize
else
    echo "Dispatch unavailable, using fallback"
    # Fallback behavior
fi
```

## Testing Manually

### Test with Dispatch Running

```bash
# Ensure Dispatch app is running
# Then test the hook:
export CLAUDE_ENV_FILE=$(mktemp)
~/.claude/hooks/session-start.sh
echo "Environment variables set:"
cat $CLAUDE_ENV_FILE
rm $CLAUDE_ENV_FILE
```

Expected output:
```
Dispatch server detected (port 19847)
Dispatch integration active - screenshot commands available
Environment variables set:
export DISPATCH_AVAILABLE=true
export DISPATCH_PORT=19847
```

### Test with Dispatch Not Running

```bash
# Stop Dispatch app
# Then test the hook:
export CLAUDE_ENV_FILE=$(mktemp)
~/.claude/hooks/session-start.sh
echo "Environment variables set:"
cat $CLAUDE_ENV_FILE
rm $CLAUDE_ENV_FILE
```

Expected output:
```
Dispatch server not detected at localhost:19847
Dispatch not running - screenshot features unavailable
Environment variables set:
export DISPATCH_AVAILABLE=false
```

### Test without CLAUDE_ENV_FILE

```bash
# Simulates non-SessionStart context
unset CLAUDE_ENV_FILE
~/.claude/hooks/session-start.sh
```

Expected: Still outputs status messages, exits 0, no crash

## Installation

The hook is created manually during Phase 09-01. Future phases may automate installation:

```bash
# Create hook
cat > ~/.claude/hooks/session-start.sh <<'EOF'
[hook content]
EOF

# Make executable
chmod 755 ~/.claude/hooks/session-start.sh
```

## Relationship to HookInstaller.swift

Phase 10 may implement automatic hook installation via `HookInstaller.swift`. The installer would:

1. Check if hook exists at `~/.claude/hooks/session-start.sh`
2. Compare version/content with built-in template
3. Update hook if needed (with user permission)
4. Set executable permissions
5. Validate hook can execute

This would ensure users get the latest hook version when Dispatch app updates.

## Technical Details

**File size:** ~1.4 KB
**Lines:** ~40
**Language:** Bash (#!/bin/bash)
**Permissions:** 755 (rwxr-xr-x)
**Exit code:** Always 0 (never blocks session)

**Key patterns used:**
- Check library exists before sourcing
- Append `>>` to CLAUDE_ENV_FILE (preserves other hooks' variables)
- Different output streams for different audiences
- Graceful degradation when library missing
- Always exit 0 to prevent session blockage

## See Also

- Phase 08-01: Shared Dispatch Integration Library
- `~/.claude/lib/dispatch.sh` - Library documentation
- `.planning/phases/09-hook-integration/09-RESEARCH.md` - Hook system research
- `.planning/phases/09-hook-integration/09-01-PLAN.md` - Implementation plan
