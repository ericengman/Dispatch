---
phase: 17-claude-code-integration
plan: 01
subsystem: terminal
tags: [swiftterm, claude-code, environment, process-management]

# Dependency graph
requires:
  - phase: 14-swiftterm-integration
    provides: EmbeddedTerminalView with LocalProcessTerminalView
  - phase: 16-process-lifecycle
    provides: TerminalProcessRegistry for PID tracking

provides:
  - ClaudeCodeLauncher service for spawning Claude Code with proper environment
  - TerminalLaunchMode enum for flexible terminal launch modes
  - Environment configuration (TERM, COLORTERM, PATH) for colored output
  - Integration with TerminalProcessRegistry for lifecycle tracking

affects: [18-prompt-dispatch, 19-completion-detection, claude-code-integration]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Singleton launcher service pattern for process configuration"
    - "Enum-based launch mode selection for NSViewRepresentable"
    - "Environment array building with Terminal.getEnvironmentVariables()"

key-files:
  created:
    - Dispatch/Services/ClaudeCodeLauncher.swift
  modified:
    - Dispatch/Views/Terminal/EmbeddedTerminalView.swift

key-decisions:
  - "ClaudeCodeLauncher as singleton - single configuration point for all Claude Code launches"
  - "TerminalLaunchMode enum in EmbeddedTerminalView - backward compatible, defaults to shell"
  - "PATH prepending for Claude CLI discovery - checks ~/.claude/local/bin, /usr/local/bin, /opt/homebrew/bin"
  - "Terminal.getEnvironmentVariables() baseline - ensures TERM=xterm-256color and COLORTERM=truecolor"
  - "--dangerously-skip-permissions default true - reduces friction for embedded usage"

patterns-established:
  - "findClaudeCLI() checks multiple paths before PATH fallback"
  - "buildEnvironment() merges SwiftTerm baseline with process inheritance"
  - "Launch modes switch in makeNSView for process-specific initialization"

# Metrics
duration: 3min
completed: 2026-02-08
---

# Phase 17 Plan 01: Claude Code Launcher Summary

**ClaudeCodeLauncher service with environment configuration (TERM, COLORTERM, PATH), TerminalLaunchMode enum for shell/Claude Code selection, and PID registration integration**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-08T05:17:01Z
- **Completed:** 2026-02-08T05:20:05Z
- **Tasks:** 3
- **Files modified:** 2

## Accomplishments
- ClaudeCodeLauncher service locates claude CLI and configures environment for colored output
- EmbeddedTerminalView supports dual launch modes (shell or Claude Code) via TerminalLaunchMode enum
- Backward compatible - existing code continues to launch shell by default
- PID registration integrated for Claude Code process lifecycle tracking

## Task Commits

Each task was committed atomically:

1. **Task 1: Create ClaudeCodeLauncher service** - `b8ca3fd` (feat)
2. **Task 2: Add Claude Code launch mode to EmbeddedTerminalView** - `f9b3a11` (feat)
3. **Task 3: Verify Claude Code launch infrastructure** - `75ca15f` (chore)

## Files Created/Modified
- `Dispatch/Services/ClaudeCodeLauncher.swift` - Singleton service to spawn Claude Code with environment configuration
- `Dispatch/Views/Terminal/EmbeddedTerminalView.swift` - Added TerminalLaunchMode enum and switch logic in makeNSView

## Decisions Made

1. **ClaudeCodeLauncher as singleton** - Single configuration point for all Claude Code launches, consistent with other service patterns (TerminalProcessRegistry, ExecutionStateMachine)

2. **TerminalLaunchMode enum** - Clean API for launch mode selection, backward compatible (defaults to .shell), extensible for future modes

3. **PATH prepending strategy** - Check common paths (~/.claude/local/bin, /usr/local/bin, /opt/homebrew/bin) before falling back to PATH resolution. Handles most installation scenarios without requiring user configuration.

4. **Terminal.getEnvironmentVariables() baseline** - Start with SwiftTerm's environment helper for TERM/COLORTERM/LANG, then augment with PATH and user variables. Ensures correct color support and Unicode rendering.

5. **--dangerously-skip-permissions default** - Reduces friction for embedded usage. User can override by passing skipPermissions: false if needed.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None. All tasks completed as planned with successful builds and verification.

## User Setup Required

None - no external service configuration required. Claude CLI must be installed separately (prerequisite).

## Next Phase Readiness

**Ready for Phase 17-02 (Prompt Dispatch):**
- ClaudeCodeLauncher can spawn Claude Code in embedded terminal
- Environment configured for colored output (TERM, COLORTERM)
- PATH includes claude CLI locations
- PID registered for lifecycle tracking
- EmbeddedTerminalView supports both shell and Claude Code modes

**Blockers/Concerns:**
- None. Infrastructure is in place for prompt dispatch via PTY.

---
*Phase: 17-claude-code-integration*
*Completed: 2026-02-08*
