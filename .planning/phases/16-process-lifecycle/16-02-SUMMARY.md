---
phase: 16-process-lifecycle
plan: 02
subsystem: terminal
tags: [process-management, lifecycle, crash-recovery, POSIX, signals]

# Dependency graph
requires:
  - phase: 16-01
    provides: TerminalProcessRegistry with PID tracking
provides:
  - Process lifecycle utilities (isProcessRunning, terminateProcessGroupGracefully, cleanupOrphanedProcesses)
  - EmbeddedTerminalView integration with registry (register on spawn, unregister on exit)
  - Orphan cleanup on app launch (recovers from crashes/force-quits)
  - Two-stage graceful termination (SIGTERM → timeout → SIGKILL)
affects: [terminal-management, session-recovery]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Two-stage process termination: SIGTERM with timeout fallback to SIGKILL"
    - "Process group termination via killpg to kill shell + children"
    - "kill(pid, 0) for zero-overhead process existence check"

key-files:
  created: []
  modified:
    - Dispatch/Services/TerminalProcessRegistry.swift
    - Dispatch/Views/Terminal/EmbeddedTerminalView.swift
    - Dispatch/DispatchApp.swift

key-decisions:
  - "Two-stage termination with 3s timeout (2s for deinit) prevents zombies while allowing graceful shutdown"
  - "killpg sends signal to entire process group (shell + Claude Code children)"
  - "kill(pid, 0) syscall for lightweight process existence check"

patterns-established:
  - "Coordinator lifecycle: register in makeNSView, unregister in processTerminated + deinit"
  - "Orphan cleanup runs synchronously early in setupApp before async services"

# Metrics
duration: 3min
completed: 2026-02-07
---

# Phase 16 Plan 02: Process Lifecycle Management Summary

**Two-stage graceful termination (SIGTERM → SIGKILL) with process group cleanup and orphan recovery on launch**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-07T23:26:47Z
- **Completed:** 2026-02-07T23:29:57Z
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments
- Process lifecycle utilities (isProcessRunning, terminateProcessGroupGracefully, cleanupOrphanedProcesses)
- TerminalProcessRegistry integrated with EmbeddedTerminalView for automatic PID tracking
- Orphan cleanup on app launch terminates shell processes from crashed sessions
- Process group termination kills shell and all children (Claude Code) via killpg

## Task Commits

Each task was committed atomically:

1. **Task 1: Add process lifecycle utilities to TerminalProcessRegistry** - `14ab347` (feat)
2. **Task 2: Integrate registry with EmbeddedTerminalView** - `0ec7e49` (feat)
3. **API fix: Use process.shellPid to access terminal PID** - `494d4e4` (fix)
4. **Task 3: Add orphan cleanup to app startup** - `24bf6db` (feat)

## Files Created/Modified
- `Dispatch/Services/TerminalProcessRegistry.swift` - Added isProcessRunning, terminateProcessGroupGracefully, cleanupOrphanedProcesses
- `Dispatch/Views/Terminal/EmbeddedTerminalView.swift` - Registry integration in makeNSView, processTerminated, deinit
- `Dispatch/DispatchApp.swift` - Orphan cleanup call in setupApp()

## Decisions Made

**1. Two-stage termination with timeout**
- SIGTERM first (graceful), wait up to timeout, then SIGKILL (force)
- 3-second default timeout (2s for deinit cleanup)
- Prevents zombie processes while allowing clean shutdown

**2. killpg for process group termination**
- Sends signal to entire process group (shell + children)
- Kills Claude Code child processes when terminal closes
- Uses process group ID (same as shell PID due to POSIX_SPAWN_SETSID)

**3. kill(pid, 0) for process existence check**
- Zero-overhead syscall (no signal sent)
- errno distinguishes cases: ESRCH (no process), EPERM (exists but no permission)
- Used in wait loop and orphan detection

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] SwiftTerm API correction**
- **Found during:** Task 2 (EmbeddedTerminalView integration)
- **Issue:** Code used `terminal.shellPid` but SwiftTerm API is `terminal.process.shellPid`
- **Fix:** Corrected all three usages (makeNSView, processTerminated, deinit)
- **Files modified:** Dispatch/Views/Terminal/EmbeddedTerminalView.swift
- **Verification:** Build succeeds, correct property accessed
- **Committed in:** 494d4e4 (separate fix commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** API correction necessary for compilation. No scope creep.

## Issues Encountered

**Compilation error on first build attempt**
- Used incorrect property name `shellPid` instead of `process.shellPid`
- Identified via build error output
- Fixed by checking SwiftTerm LocalProcess API documentation
- Build succeeded after correction

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

**Process lifecycle system complete:**
- Terminals register PIDs on spawn
- Processes terminate gracefully on view disposal
- Orphaned processes cleaned up on app relaunch
- Two-stage SIGTERM → SIGKILL prevents zombies

**Ready for:**
- Phase 17+ (if defined)
- Production use of embedded terminals with crash recovery

**No blockers or concerns.**

---
*Phase: 16-process-lifecycle*
*Completed: 2026-02-07*
