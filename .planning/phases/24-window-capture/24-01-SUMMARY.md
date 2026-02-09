---
phase: 24-window-capture
plan: 01
subsystem: ui
tags: [screencapture, macos, window-capture, custom-ui]

# Dependency graph
requires:
  - phase: 23-region-capture
    provides: ScreenshotCaptureService with QuickCaptures directory structure
provides:
  - Interactive window capture with hover-highlight and control panel
  - WindowCaptureSession for managing capture flow
  - Capture Window menu item with Cmd+Shift+7 keyboard shortcut
affects: [25-annotation-editor, capture-workflow]

# Tech tracking
tech-stack:
  added: [CGWindowListCopyWindowInfo, NSPanel for control UI]
  patterns: [Custom capture session, hover-to-highlight, floating control panel]

key-files:
  created:
    - Dispatch/Services/WindowCaptureSession.swift
  modified:
    - Dispatch/Services/ScreenshotCaptureService.swift
    - Dispatch/DispatchApp.swift

key-decisions:
  - "Use custom WindowCaptureSession instead of SCContentSharingPicker for better UX"
  - "Hover to highlight windows, click to select, then capture when ready"
  - "Floating control panel with Cancel/Capture buttons"
  - "Filter out Dock, SystemUI, invisible windows from detection"

patterns-established:
  - "Interactive capture sessions with user-controlled timing"
  - "CGWindowListCopyWindowInfo for window enumeration"
  - "Floating NSPanel for capture controls"

# Metrics
duration: 15min
completed: 2026-02-09
---

# Phase 24 Plan 01: Window Capture Summary

**Interactive window capture with hover-highlight, click-to-select, and floating control panel**

## Performance

- **Duration:** 15 min (including UX iterations)
- **Started:** 2026-02-09
- **Completed:** 2026-02-09
- **Tasks:** 2 + UX refinements
- **Files created:** 1
- **Files modified:** 2

## Accomplishments
- Custom WindowCaptureSession for interactive capture flow
- Hover over windows to highlight with blue border
- Click to select window (doesn't capture immediately)
- Floating control panel with styled Cancel/Capture buttons
- User can interact with selected window before capturing
- Window filtering (excludes Dock, SystemUI, invisible windows)
- PNG saved to QuickCaptures directory
- Keyboard shortcut Cmd+Shift+7 for quick access

## Task Commits

1. **Initial SCContentSharingPicker implementation** - `5f35314`, `73b6a79`, `71f4ace`
2. **Switch to native screencapture -iW** - `1f67ec7`
3. **Custom WindowCaptureSession with control panel** - `714d8b1`

## Files Created/Modified
- `Dispatch/Services/WindowCaptureSession.swift` (NEW) - Interactive capture session with:
  - Mouse tracking for hover-to-highlight
  - CGWindowListCopyWindowInfo for window detection
  - Highlight overlay window (blue border)
  - Floating control panel with styled buttons
  - screencapture -l for window-specific capture
- `Dispatch/Services/ScreenshotCaptureService.swift` - Simplified to delegate to WindowCaptureSession
- `Dispatch/DispatchApp.swift` - Capture Window menu item with Cmd+Shift+7

## Decisions Made

**1. Custom UI over system picker**
- SCContentSharingPicker (screen share picker) had wrong UX for screenshots
- User wanted to interact with window before capture
- Custom solution provides better control

**2. Hover-highlight with click-to-select**
- Hover highlights windows (like native screencapture)
- Click SELECTS but doesn't capture
- User can then prepare the window state
- Capture button triggers actual screenshot

**3. Blue-styled floating controls**
- Transparent background
- Blue outlined Cancel button
- Blue filled Capture button
- Matches highlight border color

**4. Window filtering**
- Only layer 0 (normal windows)
- Skip Dock, Window Server, SystemUIServer
- Skip invisible windows (alpha < 0.1)

## Deviations from Plan

### Significant Changes

**1. [User feedback] Replaced SCContentSharingPicker with custom solution**
- **Issue:** Screen share picker UX not suitable for screenshot workflow
- **Fix:** Created WindowCaptureSession with hover-highlight and control panel
- **Impact:** Better UX, user can interact with window before capture

**2. [User feedback] Replaced screencapture -iW with custom hover UI**
- **Issue:** Native -iW captures immediately on click
- **Fix:** Custom solution with select-then-capture flow
- **Impact:** User can prepare window state before capturing

---

**Total deviations:** 2 major (both user-requested UX improvements)
**Impact on plan:** Significantly better UX than original plan

## Issues Encountered
None after final implementation.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Window capture functional with excellent UX
- Images saved to QuickCaptures directory
- Ready for annotation editor integration (Phase 25)

---
*Phase: 24-window-capture*
*Completed: 2026-02-09*
