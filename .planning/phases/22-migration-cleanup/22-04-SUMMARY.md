---
phase: 22-migration-cleanup
plan: 04
subsystem: execution
tags: [swift, deprecation, skill, terminal, migration]

# Dependency graph
requires:
  - phase: 22-01
    provides: "Terminal.app fallback removal from ViewModel"
  - phase: 22-02
    provides: "Terminal UI removal from SwiftUI views"
provides:
  - "Deprecated external skill execution methods (runInExistingTerminal, runInNewTerminal)"
  - "Compiler warnings guide callers to use embedded terminal dispatch"
affects: [skill-execution, migration-completion]

# Tech tracking
tech-stack:
  added: []
  patterns: ["Deprecation annotations for gradual migration"]

key-files:
  created: []
  modified: ["Dispatch/Models/Skill.swift"]

key-decisions:
  - "Mark deprecated rather than remove for backward compatibility until v3.0"
  - "Clear deprecation message directs to embedded terminal dispatch"

patterns-established:
  - "Deprecation with version milestone (v3.0) gives clear removal timeline"

# Metrics
duration: 1min
completed: 2026-02-09
---

# Phase 22 Plan 04: Skill Terminal Execution Deprecation Summary

**External Terminal.app skill execution methods deprecated with compiler warnings directing to embedded terminal dispatch**

## Performance

- **Duration:** 1 min
- **Started:** 2026-02-09T07:00:29Z
- **Completed:** 2026-02-09T07:01:31Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Deprecated `runInExistingTerminal()` method with clear migration message
- Deprecated `runInNewTerminal()` method with clear migration message
- All callers now see compiler warnings to use embedded terminal dispatch

## Task Commits

Each task was committed atomically:

1. **Tasks 1-2: Deprecate skill execution methods** - `4b1c725` (feat)

**Plan metadata:** (to be committed)

## Files Created/Modified
- `Dispatch/Models/Skill.swift` - Added @available(*, deprecated) annotations to external Terminal.app skill execution methods

## Decisions Made
- Used `@available(*, deprecated, message: "...")` instead of removing methods entirely - preserves backward compatibility for reference during migration
- Deprecation message specifies "v3.0" removal timeline - gives clear deadline for migration
- Message directs to "embedded terminal dispatch" - provides clear migration path

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

**Migration cleanup phase nearing completion:**
- ✅ Terminal.app fallback removed from ViewModels (22-01)
- ✅ Terminal UI removed from SwiftUI views (22-02)
- ✅ Skill execution methods deprecated (22-04)
- 🚧 Remaining: Verify no active Terminal.app usage, finalize documentation

**Blockers/Concerns:**
- RunDetailView.swift has uncommitted changes (embedded terminal migration) - should be reviewed separately
- Phase 22 verification report (22-VERIFICATION.md) identified several areas still using Terminal.app that may need additional gap closure plans

---
*Phase: 22-migration-cleanup*
*Completed: 2026-02-09*
