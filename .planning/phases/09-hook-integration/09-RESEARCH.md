# Phase 9: Hook Integration - Research

**Researched:** 2026-02-03
**Domain:** Claude Code SessionStart hooks and environment variable persistence
**Confidence:** HIGH

## Summary

Phase 9 creates a SessionStart hook at `~/.claude/hooks/session-start.sh` that detects Dispatch availability at session startup and sets environment variables via `CLAUDE_ENV_FILE` for session-wide access. The hook leverages the existing dispatch.sh library created in Phase 8.

Claude Code's hook system provides a SessionStart event that fires when a new session begins or resumes. SessionStart hooks have unique access to `CLAUDE_ENV_FILE`, an environment variable containing a file path where export statements can be written to persist variables throughout the entire Claude Code session. This is the ideal mechanism for detecting Dispatch once at session start and making that status available to all subsequent bash commands.

The research verified Claude Code's official hook documentation, examined existing hooks in ~/.claude/hooks/, analyzed the dispatch.sh library implementation, and reviewed HookInstaller.swift to understand the existing hook management patterns.

**Key findings:**
- SessionStart hooks fire on startup, resume, clear, and compact (matcher: "startup", "resume", "clear", "compact")
- CLAUDE_ENV_FILE is available ONLY to SessionStart hooks, not other hook types
- Hook stdout becomes Claude's context (can inject status messages)
- Hooks are bash scripts with shebang, must be executable (chmod +x)
- Hook location: ~/.claude/hooks/session-start.sh (user-level, all projects)
- dispatch.sh library already provides dispatch_check_health() function
- State file pattern from dispatch.sh NOT needed for SessionStart (env vars persist)

**Primary recommendation:** Create session-start.sh that sources dispatch.sh, calls dispatch_check_health(), writes export statements to CLAUDE_ENV_FILE, and outputs a status message that Claude sees.

## Standard Stack

The established tools/patterns for Claude Code hooks:

### Core
| Library/Tool | Version | Purpose | Why Standard |
|--------------|---------|---------|--------------|
| bash | 3.2+ (macOS default) | Hook script language | All Claude Code hooks are bash scripts |
| CLAUDE_ENV_FILE | N/A | Session env vars | Official mechanism for SessionStart persistence |
| curl | 7.x+ (macOS default) | HTTP health check | Already used by dispatch.sh library |

### Supporting
| Library/Tool | Version | Purpose | When to Use |
|--------------|---------|---------|-------------|
| source (.) | Built-in | Load dispatch.sh library | Import existing dispatch functions |
| echo | Built-in | Status output to stdout | Inject context for Claude to see |
| export | Built-in | Set environment variables | Via CLAUDE_ENV_FILE for persistence |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| CLAUDE_ENV_FILE | Temp file persistence | CLAUDE_ENV_FILE is the official mechanism, persists for entire session |
| SessionStart hook | PreToolUse hook | SessionStart runs once at startup, PreToolUse runs on every tool call |
| stdout context | JSON additionalContext | stdout is simpler for SessionStart, JSON is for decision control |

**Installation:**
No external dependencies required - all tools are macOS/Linux system utilities.

## Architecture Patterns

### Recommended Hook Structure
```
~/.claude/
├── hooks/
│   ├── session-start.sh    # Phase 9 (this hook)
│   ├── post-tool-use.sh    # Existing (completion notification)
│   ├── after-edit.sh       # Existing (Swift formatting)
│   └── gsd-*.js            # Existing (GSD hooks)
└── lib/
    └── dispatch.sh         # Phase 8 (library sourced by hook)
```

### Pattern 1: SessionStart Hook Lifecycle
**What:** Hook runs when Claude Code session starts/resumes/compacts
**When to use:** One-time setup at session start
**Example:**
```bash
# Source: Official Claude Code hooks documentation
#!/bin/bash
# session-start.sh

# Hook runs at session start
# Matcher options: "startup", "resume", "clear", "compact"
# Hook input available via stdin (JSON)
# stdout becomes context for Claude

# Perform health check
if dispatch_check_health; then
    echo "Dispatch is available" >&2
    echo "export DISPATCH_AVAILABLE=true" >> "$CLAUDE_ENV_FILE"
else
    echo "Dispatch not available" >&2
    echo "export DISPATCH_AVAILABLE=false" >> "$CLAUDE_ENV_FILE"
fi
```

### Pattern 2: CLAUDE_ENV_FILE Environment Persistence
**What:** Write export statements to special file for session-wide variables
**When to use:** Only in SessionStart hooks
**Example:**
```bash
# Source: https://code.claude.com/docs/en/hooks#persist-environment-variables
#!/bin/bash

if [ -n "$CLAUDE_ENV_FILE" ]; then
  # Write export statements (use append >> to preserve other hooks' vars)
  echo 'export NODE_ENV=production' >> "$CLAUDE_ENV_FILE"
  echo 'export DISPATCH_AVAILABLE=true' >> "$CLAUDE_ENV_FILE"
  echo 'export DISPATCH_PORT=19847' >> "$CLAUDE_ENV_FILE"
fi

exit 0
```

### Pattern 3: Library Sourcing in Hooks
**What:** Import functions from shared library
**When to use:** When functionality already exists in dispatch.sh
**Example:**
```bash
# Source: dispatch.sh library pattern
#!/bin/bash

# Check if library exists before sourcing
if [ -f ~/.claude/lib/dispatch.sh ]; then
    source ~/.claude/lib/dispatch.sh

    # Use library functions
    if dispatch_check_health; then
        # Health check passed
    fi
else
    # Fallback - define inline function
    dispatch_check_health() {
        curl -s http://localhost:19847/health 2>/dev/null | grep -q '"status":"ok"'
    }
fi
```

### Pattern 4: Hook Output Modes
**What:** stdout vs stderr for different audiences
**When to use:** Always - Claude sees stdout, user sees stderr
**Example:**
```bash
# Source: Official hooks documentation
#!/bin/bash

# User-facing messages to stderr
echo "Checking Dispatch availability..." >&2

# Claude-facing context to stdout
echo "Dispatch health check: Server is running at localhost:19847"

# Environment variables to CLAUDE_ENV_FILE
echo "export DISPATCH_AVAILABLE=true" >> "$CLAUDE_ENV_FILE"
```

### Anti-Patterns to Avoid
- **Using state files instead of CLAUDE_ENV_FILE:** SessionStart has official env var mechanism, don't reinvent
- **Not checking CLAUDE_ENV_FILE exists:** Always verify `[ -n "$CLAUDE_ENV_FILE" ]` before writing
- **Using single `>` instead of `>>`:** Overwrites other hooks' variables, always append with `>>`
- **Not making hook executable:** Hook won't run if missing execute permissions
- **Complex logic in hooks:** Keep hooks simple, move complexity to libraries
- **JSON output in SessionStart:** SessionStart uses stdout for context, not JSON decision control

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Health check against Dispatch | inline curl command | dispatch_check_health() from dispatch.sh | Already tested, handles errors, consistent |
| Project name detection | basename $(pwd) | dispatch_get_project_name() from dispatch.sh | Works from subdirectories, git-aware |
| Environment persistence | Custom state file | CLAUDE_ENV_FILE (SessionStart hooks) | Official mechanism, session-wide scope |
| Hook installation | Manual copy | HookInstaller.swift pattern (Phase 10) | Versioning, conflict handling, validation |
| Hook file permissions | Manual chmod | FileManager.setAttributes in Swift | Proper error handling, platform-agnostic |

**Key insight:** Phase 8's dispatch.sh library already provides health checking. Phase 10's HookInstaller provides installation patterns. The SessionStart hook should be thin orchestration, not reimplementation.

## Common Pitfalls

### Pitfall 1: CLAUDE_ENV_FILE Not Available in Other Hook Types
**What goes wrong:** Trying to use CLAUDE_ENV_FILE in PreToolUse, PostToolUse, or other hooks
**Why it happens:** Misunderstanding that CLAUDE_ENV_FILE is SessionStart-only
**How to avoid:** Only access CLAUDE_ENV_FILE in SessionStart hooks, check official docs
**Warning signs:** Environment variable is empty string in non-SessionStart hooks

### Pitfall 2: Overwriting Other Hooks' Variables
**What goes wrong:** Using `>` instead of `>>` erases variables set by other SessionStart hooks
**Why it happens:** Forgetting that multiple hooks can write to CLAUDE_ENV_FILE
**How to avoid:** Always use `>>` (append) when writing to CLAUDE_ENV_FILE
**Warning signs:** Other hooks' environment variables missing in bash commands

### Pitfall 3: Hook Not Executable
**What goes wrong:** Hook file exists but never runs
**Why it happens:** Created file without execute permissions (chmod +x)
**How to avoid:** Always set 0755 permissions after creating hook file
**Warning signs:** Hook doesn't appear in verbose output, no messages logged

### Pitfall 4: Missing Shebang
**What goes wrong:** Hook executes with wrong shell or fails to run
**Why it happens:** Forgot `#!/bin/bash` at top of file
**How to avoid:** First line must be `#!/bin/bash` for bash hooks
**Warning signs:** "bad interpreter" errors or unexpected bash behavior

### Pitfall 5: Not Checking Library Exists
**What goes wrong:** Hook fails when dispatch.sh not installed yet
**Why it happens:** Assuming library exists without verification
**How to avoid:** Use `if [ -f ~/.claude/lib/dispatch.sh ]; then source ...; fi` pattern
**Warning signs:** "source: file not found" errors in hook output

### Pitfall 6: State File Complexity in SessionStart
**What goes wrong:** Using mktemp/state file pattern from dispatch.sh in SessionStart hook
**Why it happens:** Copy-pasting patterns without understanding context
**How to avoid:** SessionStart hooks persist via CLAUDE_ENV_FILE, not state files
**Warning signs:** Temp files created but environment variables not available

## Code Examples

Verified patterns from official sources and existing codebase:

### SessionStart Hook Template
```bash
# Source: Official Claude Code hooks documentation
#!/bin/bash
# session-start.sh - Detect Dispatch availability at session start

# Read hook input (optional - contains session info)
# INPUT=$(cat)

# Check if library exists
if [ ! -f ~/.claude/lib/dispatch.sh ]; then
    echo "Warning: Dispatch library not installed" >&2
    exit 0
fi

# Source the library
source ~/.claude/lib/dispatch.sh

# Perform health check
if dispatch_check_health; then
    # Dispatch is available
    echo "Dispatch server is running" >&2

    # Set environment variables for session
    if [ -n "$CLAUDE_ENV_FILE" ]; then
        echo "export DISPATCH_AVAILABLE=true" >> "$CLAUDE_ENV_FILE"
        echo "export DISPATCH_PORT=${DISPATCH_DEFAULT_PORT}" >> "$CLAUDE_ENV_FILE"
    fi

    # Output context for Claude to see
    echo "Dispatch integration active - screenshot commands available"
else
    # Dispatch not available
    echo "Dispatch server not detected" >&2

    if [ -n "$CLAUDE_ENV_FILE" ]; then
        echo "export DISPATCH_AVAILABLE=false" >> "$CLAUDE_ENV_FILE"
    fi

    echo "Dispatch not running - screenshot features unavailable"
fi

exit 0
```

### Minimal SessionStart Hook
```bash
#!/bin/bash
# Minimal version - just health check and env var

source ~/.claude/lib/dispatch.sh 2>/dev/null || exit 0

if dispatch_check_health; then
    [ -n "$CLAUDE_ENV_FILE" ] && echo "export DISPATCH_AVAILABLE=true" >> "$CLAUDE_ENV_FILE"
    echo "Dispatch available"
else
    [ -n "$CLAUDE_ENV_FILE" ] && echo "export DISPATCH_AVAILABLE=false" >> "$CLAUDE_ENV_FILE"
    echo "Dispatch not available"
fi
```

### Using Environment Variables in Bash Commands
```bash
# After SessionStart hook runs, these variables are available in all bash commands

# Check if Dispatch is available
if [ "$DISPATCH_AVAILABLE" = "true" ]; then
    echo "Using Dispatch for screenshots"
    source ~/.claude/lib/dispatch.sh
    dispatch_init "My Feature Test" "iPhone 15 Pro"
else
    echo "Dispatch unavailable, using fallback"
fi
```

### Hook Installation Pattern (From HookInstaller.swift)
```bash
# Source: HookInstaller.swift lines 86-124
# Pattern for creating hook with proper permissions

HOOK_DIR="$HOME/.claude/hooks"
HOOK_FILE="$HOOK_DIR/session-start.sh"

# Create directory if needed
mkdir -p "$HOOK_DIR"

# Write hook content
cat > "$HOOK_FILE" <<'EOF'
#!/bin/bash
# Your hook content here
EOF

# Make executable
chmod 755 "$HOOK_FILE"

echo "Hook installed at $HOOK_FILE"
```

### Reading SessionStart Hook Input
```bash
# Source: Official hooks reference - common input fields
#!/bin/bash
# SessionStart hooks receive JSON input via stdin

INPUT=$(cat)

# Extract session info (using grep/cut to avoid jq dependency)
SESSION_ID=$(echo "$INPUT" | grep -o '"session_id":"[^"]*"' | cut -d'"' -f4)
SOURCE=$(echo "$INPUT" | grep -o '"source":"[^"]*"' | cut -d'"' -f4)
CWD=$(echo "$INPUT" | grep -o '"cwd":"[^"]*"' | cut -d'"' -f4)

# SOURCE can be: "startup", "resume", "clear", "compact"
echo "Session starting: $SOURCE from $CWD" >&2
```

### Multiple Environment Variables
```bash
#!/bin/bash
# Setting multiple related environment variables

source ~/.claude/lib/dispatch.sh

if [ -n "$CLAUDE_ENV_FILE" ]; then
    if dispatch_check_health; then
        # Export multiple variables
        {
            echo "export DISPATCH_AVAILABLE=true"
            echo "export DISPATCH_PORT=${DISPATCH_DEFAULT_PORT}"
            echo "export DISPATCH_PROJECT=$(dispatch_get_project_name)"
            echo "export DISPATCH_LIB_VERSION=${DISPATCH_LIB_VERSION}"
        } >> "$CLAUDE_ENV_FILE"
    else
        echo "export DISPATCH_AVAILABLE=false" >> "$CLAUDE_ENV_FILE"
    fi
fi
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Check Dispatch availability per-command | Check once at SessionStart | Phase 9 (2026) | Reduces overhead, consistent state |
| Inline health check in every skill | Source dispatch.sh library | Phase 8 (2026) | DRY principle, maintainability |
| State file for session vars | CLAUDE_ENV_FILE | SessionStart feature added | Official mechanism, no cleanup needed |
| Manual hook installation | HookInstaller.swift | Dispatch app (Phase 10) | Version management, conflict handling |
| No session context | Hook stdout to Claude | Current Claude Code | Claude aware of Dispatch status |

**Deprecated/outdated:**
- **Per-command health checks:** Now centralized at session start
- **State file for session scope:** Use CLAUDE_ENV_FILE instead
- **Manual hook creation:** Will be auto-installed by Dispatch app (Phase 10)

## Open Questions

Things that couldn't be fully resolved:

1. **Hook execution order with multiple SessionStart hooks**
   - What we know: Multiple SessionStart hooks can exist (GSD has several)
   - What's unclear: Guaranteed execution order when multiple hooks write to CLAUDE_ENV_FILE
   - Recommendation: Use descriptive variable names to avoid conflicts, test with existing hooks

2. **CLAUDE_ENV_FILE empty string issue (GitHub Issue #15840)**
   - What we know: Some users report CLAUDE_ENV_FILE is empty string when hook runs
   - What's unclear: Whether this is fixed in latest Claude Code version (2026-02)
   - Recommendation: Always check `[ -n "$CLAUDE_ENV_FILE" ]` before writing, gracefully degrade

3. **Hook persistence across resume/compact**
   - What we know: SessionStart fires on resume and compact
   - What's unclear: Whether CLAUDE_ENV_FILE is cleared or preserves previous values
   - Recommendation: Always overwrite variables (don't append), assume clean slate

4. **Interaction with .claude/settings.json hooks**
   - What we know: Hooks can be in ~/.claude/hooks/ OR .claude/settings.json
   - What's unclear: Whether file-based hook and settings-based hook both run
   - Recommendation: Use file-based hook for Phase 9, document settings.json alternative

## Sources

### Primary (HIGH confidence)
- [Hooks Reference - Claude Code Docs](https://code.claude.com/docs/en/hooks) - Official documentation
- [Automate workflows with hooks - Claude Code Docs](https://code.claude.com/docs/en/hooks-guide) - Official guide
- `/Users/eric/.claude/hooks/after-edit.sh` - Existing hook example (PostToolUse)
- `/Users/eric/.claude/hooks/gsd-statusline.js` - Existing hook example (Node.js)
- `/Users/eric/.claude/lib/dispatch.sh` - Phase 8 library implementation
- `/Users/eric/Dispatch/Dispatch/Services/HookInstaller.swift` - Hook installation patterns
- `/Users/eric/Dispatch/.planning/phases/08-foundation/08-RESEARCH.md` - Phase 8 research

### Secondary (MEDIUM confidence)
- [Claude Code Setup Hooks: Automate Onboarding](https://claudefa.st/blog/tools/hooks/claude-code-setup-hooks) - Community guide
- [A complete guide to hooks in Claude Code](https://www.eesel.ai/blog/hooks-in-claude-code) - Third-party comprehensive guide
- [GitHub - disler/claude-code-hooks-mastery](https://github.com/disler/claude-code-hooks-mastery) - Community examples

### Tertiary (LOW confidence - known issues)
- [GitHub Issue #15840: CLAUDE_ENV_FILE not provided to SessionStart hooks](https://github.com/anthropics/claude-code/issues/15840) - Bug report (may be fixed)
- [GitHub Issue #11649: SessionStart hook doesn't receive CLAUDE_ENV_FILE when installed by plugin](https://github.com/anthropics/claude-code/issues/11649) - Plugin-specific issue

## Metadata

**Confidence breakdown:**
- Hook system architecture: HIGH - Official documentation comprehensive
- CLAUDE_ENV_FILE mechanism: HIGH - Official docs, verified in code examples
- SessionStart event: HIGH - Official docs specify all matchers and input schema
- dispatch.sh integration: HIGH - Library exists, functions verified in Phase 8
- Hook installation: HIGH - HookInstaller.swift provides pattern, Phase 10 ready

**Research date:** 2026-02-03
**Valid until:** 30 days (Claude Code hooks system is stable, but versions may add features)

**Key risks mitigated:**
- ✅ Verified CLAUDE_ENV_FILE is SessionStart-only mechanism
- ✅ Confirmed hook output modes (stdout to Claude, stderr to user)
- ✅ Validated dispatch.sh library provides needed functions
- ✅ Checked existing hooks for patterns (after-edit.sh, gsd-*.js)
- ✅ Reviewed HookInstaller.swift for installation patterns
- ⚠️  CLAUDE_ENV_FILE empty string issue reported but may be resolved
- ⚠️  Hook execution order with multiple SessionStart hooks not deterministic

**Ready for planning:** Yes - all patterns verified, library functions available, hook mechanism understood.
