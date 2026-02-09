---
phase: 22-migration-cleanup
plan: 02
subsystem: ui
tags: [terminal, permissions, swiftui, deprecation]

# Dependency graph
requires:
  - phase: 17-execution-manager
    provides: Embedded terminal integration for prompt execution
provides:
  - Deprecated TerminalPickerView for future removal
  - Queue UI without Terminal.app window selection
  - App without Terminal.app automation permission requirement
affects: [future-cleanup, terminal-removal]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "@available deprecation for phased removal"

key-files:
  created: []
  modified:
    - Dispatch/Views/Components/TerminalPickerView.swift
    - Dispatch/Views/Queue/QueuePanelView.swift
    - Dispatch.xcodeproj/project.pbxproj

key-decisions:
  - "Mark deprecated rather than delete for reference during migration"
  - "Remove NSAppleEventsUsageDescription entirely for clean new installs"

patterns-established:
  - "Deprecation annotation: Use @available(*, deprecated, message:) for phased removal"

# Metrics
duration: 2min
completed: 2026-02-09
---

# Phase 22 Plan 02: Remove Terminal.app UI Summary

**Deprecated TerminalPickerView and removed NSAppleEventsUsageDescription from project - new installs no longer prompt for Terminal.app permission**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-09T15:26:18Z
- **Completed:** 2026-02-09T15:28:18Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Marked TerminalPickerView and InlineTerminalPicker as deprecated with clear migration messages
- Removed terminal picker button and sheet from QueueItemRowView
- Eliminated NSAppleEventsUsageDescription from both Debug and Release configurations
- New app installs will not trigger Terminal.app automation permission prompt

## Task Commits

Each task was committed atomically:

1. **Task 1: Deprecate TerminalPickerView and remove from QueuePanelView** - `fd9738a` (refactor)
2. **Task 2: Remove AppleEvents permission from Xcode project** - `e828b26` (chore)

## Files Created/Modified
- `Dispatch/Views/Components/TerminalPickerView.swift` - Added @available deprecation annotations
- `Dispatch/Views/Queue/QueuePanelView.swift` - Removed terminal picker state, button, and sheet
- `Dispatch.xcodeproj/project.pbxproj` - Removed INFOPLIST_KEY_NSAppleEventsUsageDescription

## Decisions Made
- Kept deprecated views in codebase for reference during migration rather than deleting immediately
- Removed permission key entirely rather than leaving an unused entry

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Terminal.app UI controls are deprecated and hidden from queue
- Permission requirement removed for new installs
- Ready for plan 03 to deprecate remaining Terminal.app services

---
*Phase: 22-migration-cleanup*
*Completed: 2026-02-09*
