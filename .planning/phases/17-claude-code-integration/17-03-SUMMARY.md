---
phase: 17-claude-code-integration
plan: 03
subsystem: terminal
tags: [swiftui, terminal, claude-code, embedded-terminal]

requires:
  - phase: 17-01
    provides: ClaudeCodeLauncher service and TerminalLaunchMode enum
  - phase: 17-02
    provides: dispatchPrompt and completion detection

provides:
  - Claude Code as default terminal launch mode
  - Terminal panel opens Claude Code on Cmd+Shift+T

affects: [phase-18-multi-session, phase-20-service-integration]

tech-stack:
  added: []
  patterns:
    - "TerminalLaunchMode.claudeCode as default"

key-files:
  created: []
  modified:
    - Dispatch/Views/MainView.swift
    - Dispatch/Services/ClaudeCodeLauncher.swift

key-decisions:
  - "workingDirectory: nil for now (wired to project in Phase 20)"
  - "skipPermissions: true for embedded usage friction reduction"
  - "Added ~/.local/bin to claude CLI search paths (npm global install)"

duration: 3min
completed: 2026-02-08
---

# Phase 17 Plan 03: Wire Claude Code as Default Terminal Mode Summary

**Terminal panel now launches Claude Code directly instead of shell, with proper CLI path resolution**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-08T05:30:00Z
- **Completed:** 2026-02-08T05:33:00Z
- **Tasks:** 2 (1 auto + 1 checkpoint)
- **Files modified:** 2

## Accomplishments

- Changed EmbeddedTerminalView instantiation in MainView to use .claudeCode launch mode
- Fixed claude CLI discovery to include ~/.local/bin (npm global install location)
- Human verified: Claude Code launches with colored output in terminal panel

## Task Commits

1. **Task 1: Change terminal launch mode to Claude Code** - `dc99e54` (feat)
2. **Fix: Add ~/.local/bin to claude CLI paths** - `c5af391` (fix)

## Files Created/Modified

- `Dispatch/Views/MainView.swift` - Changed EmbeddedTerminalView to use .claudeCode(workingDirectory: nil, skipPermissions: true)
- `Dispatch/Services/ClaudeCodeLauncher.swift` - Added ~/.local/bin to findClaudeCLI() candidates and PATH prepending

## Decisions Made

- workingDirectory: nil for now - will be wired to project path in Phase 20
- skipPermissions: true - matches 17-01 decision for embedded usage
- Added ~/.local/bin to CLI search paths - fixes npm global install location

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added ~/.local/bin to claude CLI search paths**
- **Found during:** Human verification checkpoint
- **Issue:** Claude CLI installed at ~/.local/bin/claude but findClaudeCLI() only checked ~/.claude/local/bin, /usr/local/bin, /opt/homebrew/bin
- **Fix:** Added ~/.local/bin/claude to candidates and PATH prepending
- **Files modified:** Dispatch/Services/ClaudeCodeLauncher.swift
- **Verification:** Claude Code now launches successfully
- **Committed in:** c5af391

---

**Total deviations:** 1 auto-fixed (blocking issue)
**Impact on plan:** Essential fix for CLI discovery. No scope creep.

## Issues Encountered

- Initial launch showed "dispatch_source_create returned NULL" error because claude executable wasn't found at expected paths
- Fixed by adding ~/.local/bin to search paths

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Gap 1 closed: Terminal panel opens Claude Code by default
- Ready for Phase 18 (Multi-Session UI) or remaining gap closure

---
*Phase: 17-claude-code-integration*
*Completed: 2026-02-08*
