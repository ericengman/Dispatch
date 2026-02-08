---
phase: 17-claude-code-integration
plan: 02
subsystem: terminal
tags: [swifterm, pty, pattern-matching, completion-detection]

# Dependency graph
requires:
  - phase: 17-01
    provides: ClaudeCodeLauncher service with environment configuration
  - phase: 16-02
    provides: Process lifecycle management
  - phase: 14-01
    provides: SwiftTerm embedded terminal infrastructure
provides:
  - PTY-based prompt dispatch via EmbeddedTerminalView.Coordinator
  - Pattern-based completion detection in ClaudeCodeLauncher
  - Embedded terminal monitoring in ExecutionStateMachine
affects: [17-03-prompt-workflow, terminal-integration, execution-flow]

# Tech tracking
tech-stack:
  added: []
  patterns: [pty-dispatch, pattern-detection, dual-monitoring]

key-files:
  created: []
  modified:
    - Dispatch/Views/Terminal/EmbeddedTerminalView.swift
    - Dispatch/Services/ClaudeCodeLauncher.swift
    - Dispatch/Services/ExecutionStateMachine.swift

key-decisions:
  - "dispatchPrompt separate from sendIfRunning for different use cases"
  - "getBufferAsData for terminal content access (not buffer.lines)"
  - "Dual monitoring (HookServer + pattern) for robust completion detection"
  - "1.5s polling interval balances responsiveness and CPU usage"

patterns-established:
  - "PTY dispatch: terminal.send(txt: prompt + \\n) for Claude Code input"
  - "Pattern detection: Check last 200 chars for ╭─, ╰─, > prompt indicators"
  - "Dual monitoring: HookServer primary, pattern matching fallback"

# Metrics
duration: 3min
completed: 2026-02-08
---

# Phase 17 Plan 02: Prompt Dispatch Summary

**PTY-based prompt dispatch with automatic newline handling and pattern-based completion detection via terminal buffer scanning**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-08T05:23:09Z
- **Completed:** 2026-02-08T05:26:30Z
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments
- EmbeddedTerminalView.Coordinator can dispatch prompts with automatic newline handling
- ClaudeCodeLauncher detects Claude Code idle state via terminal buffer patterns
- ExecutionStateMachine monitors embedded terminals for completion alongside HookServer
- Pattern matching provides robust fallback when hooks unavailable

## Task Commits

Each task was committed atomically:

1. **Task 1: Add prompt dispatch to EmbeddedTerminalView.Coordinator** - `c085ddc` (feat)
2. **Task 2: Add completion pattern detection to ClaudeCodeLauncher** - `6b579a2` (feat)
3. **Task 3: Add embedded terminal monitoring to ExecutionStateMachine** - `e450382` (feat)

## Files Created/Modified
- `Dispatch/Views/Terminal/EmbeddedTerminalView.swift` - Added dispatchPrompt method and isReadyForDispatch property to Coordinator
- `Dispatch/Services/ClaudeCodeLauncher.swift` - Added isClaudeCodeIdle method with pattern-based detection
- `Dispatch/Services/ExecutionStateMachine.swift` - Added startEmbeddedTerminalMonitoring method

## Decisions Made

1. **dispatchPrompt separate from sendIfRunning** - Both methods serve different purposes: dispatchPrompt for user prompts with newline handling, sendIfRunning for raw data/commands. Keeping both provides clear API for different use cases.

2. **getBufferAsData for content access** - SwiftTerm's buffer.lines property is internal. Using public getBufferAsData() API is the correct approach, returns full buffer as UTF-8 Data.

3. **Dual monitoring (HookServer + pattern)** - HookServer is authoritative when available, pattern matching provides fallback. First detection method to fire wins (markCompleted stops polling). Ensures completion detected even if hooks fail.

4. **1.5s polling interval** - Balances responsiveness (detects completion reasonably fast) with CPU efficiency (doesn't hammer terminal buffer). Faster than Terminal.app polling (2s) since pattern check is local.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Used getBufferAsData instead of buffer.lines**
- **Found during:** Task 2 (Pattern detection implementation)
- **Issue:** Plan's research suggested buffer.lines[row] access, but SwiftTerm's lines property is internal (not public API)
- **Fix:** Used terminalInstance.getBufferAsData() which returns full buffer as Data, decode as UTF-8 string, then search last 200 chars
- **Files modified:** Dispatch/Services/ClaudeCodeLauncher.swift
- **Verification:** Build succeeded, API is public and stable
- **Committed in:** 6b579a2 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Fix necessary for correct API usage. getBufferAsData is the public API for this use case. No functional changes to plan.

## Issues Encountered

None - all tasks executed as planned after API correction.

## Next Phase Readiness

**Ready for Phase 17-03 (Prompt Workflow Integration):**
- Prompt dispatch available via EmbeddedTerminalView.Coordinator.dispatchPrompt()
- Completion detection working (dual approach: hooks + patterns)
- ExecutionStateMachine supports embedded terminal monitoring
- Infrastructure complete for end-to-end prompt flow

**Technical notes for 17-03:**
- Call coordinator.dispatchPrompt(promptText) to send to Claude Code
- Call stateMachine.startEmbeddedTerminalMonitoring(terminal: terminal) after dispatch
- HookServer will also fire if stop hook installed
- Pattern detection searches for ╭─, ╰─, or > near end of buffer

---
*Phase: 17-claude-code-integration*
*Completed: 2026-02-08*
