---
phase: 16-process-lifecycle
plan: 01
subsystem: terminal
tags: [swiftterm, process-management, pid-tracking, userdefaults, crash-recovery]

# Dependency graph
requires:
  - phase: 15-safe-terminal-wrapper
    provides: SafeTerminalWrapper with process lifecycle awareness
provides:
  - TerminalProcessRegistry singleton for PID tracking
  - UserDefaults persistence for crash recovery
  - Thread-safe PID register/unregister API
affects: [17-startup-orphan-cleanup, process-management]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Singleton registry with UserDefaults persistence"
    - "NSLock for thread-safe collection access"
    - "Automatic persistence on mutation"

key-files:
  created:
    - Dispatch/Services/TerminalProcessRegistry.swift
  modified: []

key-decisions:
  - "UserDefaults for PID persistence (simple, sufficient for crash recovery)"
  - "NSLock over actor isolation (synchronous API, simple locking pattern)"
  - "Set<pid_t> in-memory structure (fast lookup, no duplicates)"
  - "No synchronize() call (deprecated, automatic sync sufficient)"

patterns-established:
  - "Registry pattern: singleton with lock-protected collection + persistence"
  - "PID lifecycle: register on spawn, unregister on exit/termination"

# Metrics
duration: 1min
completed: 2026-02-08
---

# Phase 16 Plan 01: Process Registry Summary

**Thread-safe PID registry with UserDefaults persistence enabling orphan process cleanup on app relaunch**

## Performance

- **Duration:** 1 min
- **Started:** 2026-02-08T04:25:48Z
- **Completed:** 2026-02-08T04:26:45Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- TerminalProcessRegistry singleton service created
- Thread-safe PID tracking with NSLock
- UserDefaults persistence on register/unregister
- getAllPIDs() for orphan cleanup at startup

## Task Commits

Each task was committed atomically:

1. **Task 1: Create TerminalProcessRegistry service** - `016f1ec` (feat)
2. **Task 2: Verify build succeeds** - (verification only, no commit)

**Plan metadata:** (will be committed after summary)

## Files Created/Modified
- `Dispatch/Services/TerminalProcessRegistry.swift` - Singleton registry tracking active process PIDs with UserDefaults persistence and NSLock thread safety

## Decisions Made

**UserDefaults for persistence**
- Simple, reliable persistence mechanism
- Sufficient for crash recovery use case
- Automatic sync without deprecated synchronize() call

**NSLock over actor isolation**
- Synchronous API more appropriate for simple getter/setter
- Familiar locking pattern for team
- Lower complexity than Swift concurrency for this use case

**Set<pid_t> data structure**
- Fast O(1) contains() lookup
- Automatic duplicate prevention
- Natural fit for registry pattern

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

**Ready for Plan 02 (Terminal Integration)**
- TerminalProcessRegistry.shared available for use
- register(pid:) ready to call after Process.run()
- unregister(pid:) ready for termination handler
- getAllPIDs() ready for startup orphan cleanup

**Ready for Plan 03 (Startup Cleanup)**
- getAllPIDs() returns persisted PIDs from previous session
- Can iterate and check process liveness
- Can unregister dead processes

No blockers or concerns.

---
*Phase: 16-process-lifecycle*
*Completed: 2026-02-08*
