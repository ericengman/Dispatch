---
phase: 22-migration-cleanup
plan: 01
subsystem: execution
tags: [terminal, embedded-terminal, deprecation, swift, execution-manager]

# Dependency graph
requires:
  - phase: 20-execution-wiring
    provides: EmbeddedTerminalService integration with ExecutionManager
provides:
  - ExecutionManager with embedded-only dispatch path
  - Deprecated TerminalService actor (kept for rollback)
  - ExecutionError.noTerminalAvailable case
  - Clean ViewModel execute calls without terminal targeting
affects: [22-02-ui-cleanup, future-terminal-removal]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Guard-else for service availability checks"
    - "Deprecation annotations for staged removal"

key-files:
  created: []
  modified:
    - Dispatch/Services/TerminalService.swift
    - Dispatch/Services/ExecutionStateMachine.swift
    - Dispatch/ViewModels/QueueViewModel.swift
    - Dispatch/ViewModels/ChainViewModel.swift
    - Dispatch/ViewModels/HistoryViewModel.swift

key-decisions:
  - "Deprecate TerminalService instead of deleting (allows rollback)"
  - "Keep unused parameters in execute() API with underscore prefix"
  - "Guard-else pattern for embedded service availability"

patterns-established:
  - "Deprecation-first removal: Mark deprecated, remove code paths, keep compilable"

# Metrics
duration: 4min
completed: 2026-02-09
---

# Phase 22 Plan 01: Terminal.app Fallback Removal Summary

**ExecutionManager now dispatches exclusively to embedded terminals with TerminalService deprecated for potential rollback**

## Performance

- **Duration:** 4 min
- **Started:** 2026-02-09T15:24:00Z
- **Completed:** 2026-02-09T15:28:49Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- ExecutionManager uses embedded terminal as sole execution path
- TerminalService actor marked deprecated with v3.0 removal message
- startPolling() method deprecated (Terminal.app-only feature)
- All ViewModel execute calls simplified (no terminal targeting params)
- New ExecutionError.noTerminalAvailable case for clear error messaging

## Task Commits

Each task was committed atomically:

1. **Task 1: Deprecate TerminalService and remove fallback** - `fd9738a` (feat)
2. **Task 2: Update ViewModels to remove Terminal.app parameters** - `c316ac1` (feat)

## Files Created/Modified
- `Dispatch/Services/TerminalService.swift` - Added @available deprecation annotation
- `Dispatch/Services/ExecutionStateMachine.swift` - Removed terminalService property, Terminal.app fallback path, added noTerminalAvailable error
- `Dispatch/ViewModels/QueueViewModel.swift` - Removed targetWindowId/Name from execute call
- `Dispatch/ViewModels/ChainViewModel.swift` - Removed targetWindowId param from startExecution and executeItem
- `Dispatch/ViewModels/HistoryViewModel.swift` - Removed targetWindowId/Name from resend execute call

## Decisions Made
- **Deprecation over deletion:** Kept TerminalService compilable with deprecation annotation to allow rollback if embedded terminal has issues
- **Underscore unused params:** Linter automatically prefixed unused execute() params with underscore - keeping API signature stable
- **Guard-else pattern:** Replaced if-else with guard for clearer flow when embedded service unavailable

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Updated HistoryViewModel.resend() execute call**
- **Found during:** Task 2 verification
- **Issue:** HistoryViewModel.resend() also called ExecutionManager.execute() with targetWindowId/Name params (not listed in plan)
- **Fix:** Removed terminal targeting params from the execute call for consistency
- **Files modified:** Dispatch/ViewModels/HistoryViewModel.swift
- **Verification:** Build succeeds, grep shows no targetWindowId in execute calls
- **Committed in:** c316ac1 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 missing critical)
**Impact on plan:** Necessary for consistency. All ViewModels now use the same execute() call pattern.

## Issues Encountered
None - plan executed cleanly.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Service layer migration complete
- Ready for UI cleanup in plan 22-02 (TerminalPickerView removal, QueueItem model cleanup)
- No blockers

---
*Phase: 22-migration-cleanup*
*Completed: 2026-02-09*
